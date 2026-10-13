defmodule Core.Forms do
  @moduledoc """
  Configurable forms: a definition the people running an app edit
  (fields with a type, label, hint, required flag and options), and
  the answers someone gives to it. Pure logic over plain maps and
  lists, so any app stores both as it likes (jsonb, say) and renders
  them with its own UI and words; errors are codes, never text.

  A definition is a list of fields, in form order:

      %{"id" => "k3J9xQ2a", "type" => "phone", "label" => "Phone",
        "hint" => nil, "required" => true, "options" => []}

  The id is stable across edits. Answers are a list in form order:

      %{"id" => "k3J9xQ2a", "label" => "Phone", "type" => "phone",
        "value" => "+380 44 123 45 67"}

  with the field's label and type copied at answer time, so editing or
  removing a field later never changes or loses what someone answered.
  Values: a string for the text-like types, number and single choice
  (a Telegram username without its @), a list of strings for multiple
  choice, true/false for yes/no. An optional field left empty is left
  out; yes/no is always answered.

  Editing functions take the editor's params ("label", "hint",
  "required" "yes"/"no", "type", "options" one per line) and return
  `{:ok, definition}`, `{:error, :not_found}` or `{:error, errors}`
  keyed by param (or `:form`), with these codes:

    * `:required`, `{:too_long, max}` - label, hint
    * `:unknown_type` - type
    * `{:options_count, min, max}`, `{:option_too_long, max}`,
      `:duplicate_options` - options of the choice types
    * `{:too_many_fields, max}`, `:duplicate_id`, `:not_a_list` - form

  Answer codes: `:required`, `{:invalid, :email | :phone | :telegram
  | :number}`, `{:too_long, max}`, `:not_an_option`, `:unknown_type`.
  """

  @types ~w(text longtext number email phone telegram yesno choice multi)
  @choice_types ~w(choice multi)
  @max_fields 30
  @label_max 120
  @hint_max 200
  @option_max 80
  @options_min 2
  @options_max 20
  @text_max 200
  @longtext_max 2000

  @doc "Every field type, in the editor's order."
  def types, do: @types

  @doc "Does this type pick from options?"
  def choice_type?(type), do: type in @choice_types

  @doc "One field of the definition by id, or nil."
  def field(definition, id) when is_list(definition),
    do: Enum.find(definition, &(&1["id"] == id))

  def field(_definition, _id), do: nil

  # ---------------------------------------------------------------
  # Editing a definition
  # ---------------------------------------------------------------

  @doc "Adds a field at the end, with a new id."
  def add_field(definition, params) when is_list(definition) do
    if length(definition) >= @max_fields do
      {:error, %{form: {:too_many_fields, @max_fields}}}
    else
      with {:ok, field} <- build_field(params, new_id()), do: {:ok, definition ++ [field]}
    end
  end

  @doc "Replaces a field's settings, keeping its id and place."
  def update_field(definition, id, params) when is_list(definition) do
    with %{} <- field(definition, id) || {:error, :not_found},
         {:ok, field} <- build_field(params, id) do
      {:ok, Enum.map(definition, &if(&1["id"] == id, do: field, else: &1))}
    end
  end

  @doc "Removes a field; answers already given keep their copy of it."
  def remove_field(definition, id) when is_list(definition) do
    case field(definition, id) do
      nil -> {:error, :not_found}
      _field -> {:ok, Enum.reject(definition, &(&1["id"] == id))}
    end
  end

  @doc "Moves a field one place :up or :down; at the edge nothing moves."
  def move_field(definition, id, direction)
      when is_list(definition) and direction in [:up, :down] do
    case Enum.find_index(definition, &(&1["id"] == id)) do
      nil ->
        {:error, :not_found}

      index ->
        other = if direction == :up, do: index - 1, else: index + 1

        if other < 0 or other >= length(definition) do
          {:ok, definition}
        else
          {:ok,
           definition
           |> List.replace_at(index, Enum.at(definition, other))
           |> List.replace_at(other, Enum.at(definition, index))}
        end
    end
  end

  @doc """
  Checks a whole definition (one read back from storage or sent over
  an API): `{:ok, definition}` with every field normalised, or
  `{:error, %{field_index => errors}}` / `{:error, %{form: code}}`.
  Fields without an id get one; duplicate ids are refused.
  """
  def normalize(definition) when is_list(definition) do
    {fields, errors} =
      definition
      |> Enum.with_index()
      |> Enum.reduce({[], %{}}, fn {raw, index}, {ok, bad} ->
        raw = if is_map(raw), do: raw, else: %{}
        id = if is_binary(raw["id"]) and raw["id"] != "", do: raw["id"], else: new_id()

        case build_field(field_params(raw), id) do
          {:ok, field} -> {[field | ok], bad}
          {:error, field_errors} -> {ok, Map.put(bad, index, field_errors)}
        end
      end)

    ids = Enum.map(fields, & &1["id"])

    cond do
      errors != %{} ->
        {:error, errors}

      length(fields) > @max_fields ->
        {:error, %{form: {:too_many_fields, @max_fields}}}

      length(Enum.uniq(ids)) != length(ids) ->
        {:error, %{form: :duplicate_id}}

      true ->
        {:ok, Enum.reverse(fields)}
    end
  end

  def normalize(_definition), do: {:error, %{form: :not_a_list}}

  @doc "A field as the editor's params (the edit form's starting values)."
  def field_params(nil), do: %{"type" => "text", "required" => "no"}

  def field_params(field) when is_map(field) do
    %{
      "label" => field["label"],
      "hint" => field["hint"],
      "type" => field["type"],
      "required" => if(field["required"] in [true, "yes", "true"], do: "yes", else: "no"),
      "options" => field["options"] |> List.wrap() |> Enum.join("\n")
    }
  end

  @doc "The editor's params as a field with this id: `{:ok, field}` or `{:error, errors}`."
  def build_field(params, id) when is_map(params) do
    label = text(params["label"])
    hint = text(params["hint"])
    type = params["type"]
    options = if choice_type?(type), do: options(params["options"]), else: []

    errors =
      %{}
      |> put_error(:label, label == nil, :required)
      |> put_error(
        :label,
        label && String.length(label) > @label_max,
        {:too_long, @label_max}
      )
      |> put_error(
        :hint,
        hint && String.length(hint) > @hint_max,
        {:too_long, @hint_max}
      )
      |> put_error(:type, type not in @types, :unknown_type)
      |> put_error(:options, choice_type?(type) && options_error(options), options_error(options))

    if errors == %{} do
      {:ok,
       %{
         "id" => id,
         "type" => type,
         "label" => label,
         "hint" => hint,
         "required" => params["required"] in ["yes", "true", true],
         "options" => options
       }}
    else
      {:error, errors}
    end
  end

  def build_field(_params, id), do: build_field(%{}, id)

  defp new_id, do: :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)

  defp options(raw) when is_binary(raw) do
    raw |> String.split(~r/\R/) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  defp options(raw) when is_list(raw),
    do: raw |> Enum.filter(&is_binary/1) |> Enum.join("\n") |> options()

  defp options(_raw), do: []

  defp options_error(options) do
    cond do
      length(options) < @options_min or length(options) > @options_max ->
        {:options_count, @options_min, @options_max}

      Enum.any?(options, &(String.length(&1) > @option_max)) ->
        {:option_too_long, @option_max}

      length(Enum.uniq(options)) != length(options) ->
        :duplicate_options

      true ->
        false
    end
  end

  defp put_error(errors, field, condition, message) do
    if condition && !Map.has_key?(errors, field),
      do: Map.put(errors, field, message),
      else: errors
  end

  defp text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp text(_value), do: nil

  # ---------------------------------------------------------------
  # Answering
  # ---------------------------------------------------------------

  @doc """
  Checks answers (`params` keyed by field id, as `form_fields` posts
  them) against the definition: `{:ok, answers}` or
  `{:error, %{field_id => message}}`. Params for ids the definition
  does not have are ignored.
  """
  def validate_answers(definition, params) when is_list(definition) do
    params = if is_map(params), do: params, else: %{}

    {answers, errors} =
      Enum.reduce(definition, {[], %{}}, fn field, {ok, bad} ->
        case answer(field, params[field["id"]]) do
          {:ok, nil} ->
            {ok, bad}

          {:ok, value} ->
            {[field |> Map.take(~w(id label type)) |> Map.put("value", value) | ok], bad}

          {:error, message} ->
            {ok, Map.put(bad, field["id"], message)}
        end
      end)

    if errors == %{}, do: {:ok, Enum.reverse(answers)}, else: {:error, errors}
  end

  def validate_answers(_definition, _params), do: {:ok, []}

  @doc "The first answer's value of that type (e.g. the first e-mail given), or nil."
  def first_value(answers, type) when is_list(answers) do
    Enum.find_value(answers, fn
      %{"type" => ^type, "value" => value} when value not in [nil, ""] -> value
      _answer -> nil
    end)
  end

  def first_value(_answers, _type), do: nil

  defp answer(%{"type" => "yesno"} = field, raw) do
    yes = raw in ["yes", "true", "on", true]

    if field["required"] == true and not yes,
      do: {:error, :required},
      else: {:ok, yes}
  end

  defp answer(%{"type" => "multi"} = field, raw) do
    picked = raw |> List.wrap() |> Enum.filter(&is_binary/1) |> Enum.uniq()

    cond do
      Enum.any?(picked, &(&1 not in field["options"])) ->
        {:error, :not_an_option}

      picked == [] and field["required"] == true ->
        {:error, :required}

      picked == [] ->
        {:ok, nil}

      true ->
        # in the form's order, not the click order
        {:ok, Enum.filter(field["options"], &(&1 in picked))}
    end
  end

  defp answer(field, raw) do
    case {text(raw), field["required"]} do
      {nil, true} -> {:error, :required}
      {nil, _optional} -> {:ok, nil}
      {value, _required} -> check(field, value)
    end
  end

  defp check(%{"type" => "text"}, value), do: length_ok(value, @text_max)
  defp check(%{"type" => "longtext"}, value), do: length_ok(value, @longtext_max)

  defp check(%{"type" => "number"}, value) do
    if value =~ ~r/^-?\d{1,15}([.,]\d{1,6})?$/,
      do: {:ok, String.replace(value, ",", ".")},
      else: {:error, {:invalid, :number}}
  end

  defp check(%{"type" => "email"}, value) do
    if String.length(value) <= 254 and value =~ ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/,
      do: {:ok, value},
      else: {:error, {:invalid, :email}}
  end

  # an optional + in front, then digits with spaces, dashes or brackets
  # between them; 7 to 20 digits in all
  defp check(%{"type" => "phone"}, value) do
    digits = value |> String.replace(~r/\D/, "") |> String.length()

    if value =~ ~r/^\+?[0-9 ()\-]+$/ and digits in 7..20,
      do: {:ok, String.replace(value, ~r/\s+/, " ")},
      else: {:error, {:invalid, :phone}}
  end

  defp check(%{"type" => "telegram"}, value) do
    name = String.replace_prefix(value, "@", "")

    if name =~ ~r/^[A-Za-z0-9_]{5,32}$/,
      do: {:ok, name},
      else: {:error, {:invalid, :telegram}}
  end

  defp check(%{"type" => "choice"} = field, value) do
    if value in field["options"],
      do: {:ok, value},
      else: {:error, :not_an_option}
  end

  defp check(_field, _value), do: {:error, :unknown_type}

  defp length_ok(value, max) do
    if String.length(value) <= max,
      do: {:ok, value},
      else: {:error, {:too_long, max}}
  end
end
