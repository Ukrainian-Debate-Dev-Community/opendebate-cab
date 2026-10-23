defmodule Core.Forms do
  @moduledoc """
  Configurable forms: a definition the people running an app edit
  (fields with a type, label, hint, required flag and options), and
  the answers someone gives to it. Pure logic over plain maps and
  lists, so any app stores both as it likes (jsonb, say) and renders
  them with its own UI and words; errors are codes, never text.

  A definition is a list of fields, in form order:

      %{"id" => "k3J9xQ2a", "type" => "phone", "label" => "Phone",
        "hint" => nil, "required" => true, "options" => [],
        "locked" => false}

  The id is stable across edits. An app may give its fields
  attributes of its own (`attrs`: name => `{allowed values, default}`,
  e.g. `%{"audience" => {~w(a b), "a"}}`): each field stores a value
  for each, a stored field without one reads the default, an edit that
  sends none keeps the field's, and a value outside the allowed ones
  is `:not_allowed` under that name. Core gives them no meaning; the
  app does. A locked field is one the app always
  asks (`with_locked/2` puts the app's locked fields in front when it
  reads a definition): it cannot be removed or moved, and only its
  required flag and hint can change. Answers are a list in form order:

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

    * `:required`, `{:too_long, max}`, `:invalid` - label, hint
    * `:unknown_type` - type
    * `:not_allowed` - an app attribute (keyed by its name)
    * `{:options_count, min, max}`, `{:option_too_long, max}`,
      `:duplicate_options`, `:invalid` - options of the choice types
    * `{:too_many_fields, max}`, `:duplicate_id`, `:not_a_list`,
      `:locked_removed`, `:locked_moved` - form
    * `{:error, :locked}` - removing or moving a locked field

  Answer codes: `:required`, `{:invalid, :email | :phone | :telegram
  | :number}`, `{:too_long, max}`, `:not_an_option`, `:unknown_type`,
  `:invalid` (control characters). Text is cleaned with `Core.Text`:
  only whitespace or invisible characters count as empty.
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

  @doc """
  An address worth sending mail to - a deliberately simple check, not
  the full RFC 5322 grammar:

    * at most 254 characters, exactly one @, something on both sides
    * no spaces, control characters, percent signs (an encoded
      `%00`), quotes or the other characters only a quoted address
      may hold: `"' ( ) , : ; < > [ ] \\`
    * no dot at the start or end of either side, never two in a row
    * a domain of at least two labels, the last (the top-level
      domain) letters only, or an `xn--` name

      iex> Core.Forms.email?("ada@example.org")
      true
      iex> Core.Forms.email?("a%00b@x.com")
      false
  """
  def email?(value) when is_binary(value) do
    with true <- String.length(value) <= 254,
         false <- value =~ ~r/[\s\p{C}%"'(),:;<>\[\]\\]/u,
         [local, domain] <- String.split(value, "@"),
         true <- dotted?(local) and dotted?(domain),
         [_ | [_ | _]] = labels <- String.split(domain, ".") do
      List.last(labels) =~ ~r/^(\p{L}{2,63}|xn--[a-z0-9-]{1,59})$/iu
    else
      _ -> false
    end
  end

  def email?(_value), do: false

  # non-empty, no dot at either end, no two dots in a row
  defp dotted?(part),
    do: part != "" and not String.starts_with?(part, ".") and
      not String.ends_with?(part, ".") and not String.contains?(part, "..")

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
  def add_field(definition, params, attrs \\ %{}) when is_list(definition) do
    if length(definition) >= @max_fields do
      {:error, %{form: {:too_many_fields, @max_fields}}}
    else
      with {:ok, field} <- build_field(params, new_id(), attrs), do: {:ok, definition ++ [field]}
    end
  end

  @doc """
  Replaces a field's settings, keeping its id and place. A locked
  field takes only "required" and "hint"; its label, type and app
  attributes stay.
  """
  def update_field(definition, id, params, attrs \\ %{}) when is_list(definition) do
    with %{} = old <- field(definition, id) || {:error, :not_found},
         {:ok, field} <- rebuild(old, params, attrs) do
      {:ok, Enum.map(definition, &if(&1["id"] == id, do: field, else: &1))}
    end
  end

  defp rebuild(%{"locked" => true} = old, params, attrs) do
    old
    |> field_params(attrs)
    |> Map.merge(Map.take(params, ~w(required hint)))
    |> build_field(old["id"], attrs)
    |> lock()
  end

  # an app attribute not sent keeps the field's
  defp rebuild(old, params, attrs) do
    kept = for {name, _allowed} <- attrs, into: %{}, do: {name, attr(old, name, attrs)}
    build_field(Map.merge(kept, params), old["id"], attrs)
  end

  defp lock({:ok, field}), do: {:ok, Map.put(field, "locked", true)}
  defp lock(error), do: error

  @doc "Removes a field; answers already given keep their copy of it. Locked fields stay."
  def remove_field(definition, id) when is_list(definition) do
    case field(definition, id) do
      nil -> {:error, :not_found}
      %{"locked" => true} -> {:error, :locked}
      _field -> {:ok, Enum.reject(definition, &(&1["id"] == id))}
    end
  end

  @doc """
  Moves a field one place :up or :down; at the edge nothing moves.
  Locked fields keep their place: moving one, or past one, is
  `{:error, :locked}`.
  """
  def move_field(definition, id, direction)
      when is_list(definition) and direction in [:up, :down] do
    case Enum.find_index(definition, &(&1["id"] == id)) do
      nil ->
        {:error, :not_found}

      index ->
        other = if direction == :up, do: index - 1, else: index + 1

        cond do
          locked?(Enum.at(definition, index)) ->
            {:error, :locked}

          other < 0 or other >= length(definition) ->
            {:ok, definition}

          locked?(Enum.at(definition, other)) ->
            {:error, :locked}

          true ->
            {:ok,
             definition
             |> List.replace_at(index, Enum.at(definition, other))
             |> List.replace_at(other, Enum.at(definition, index))}
        end
    end
  end

  @doc "Is this a locked field (one the app always asks)?"
  def locked?(%{"locked" => true}), do: true
  def locked?(_field), do: false

  @doc """
  The definition with the app's locked fields in front, in the given
  order - for reading a stored definition (even an empty one). Each
  locked field keeps its stored "required" and "hint"; its id, type,
  label and options are the app's. The other stored fields follow,
  unlocked.
  """
  def with_locked(definition, locked, attrs \\ %{}) when is_list(locked) do
    definition = if is_list(definition), do: definition, else: []
    locked_ids = Enum.map(locked, & &1["id"])

    fixed =
      for default <- locked do
        stored = field(definition, default["id"]) || %{}

        default
        |> Map.merge(Map.take(stored, ~w(required hint)))
        |> put_attrs(default, attrs)
        |> Map.put("locked", true)
      end

    rest =
      for field <- definition, field["id"] not in locked_ids do
        field |> put_attrs(field, attrs) |> Map.put("locked", false)
      end

    fixed ++ rest
  end

  @doc "A field's value of an app attribute: its stored one if allowed, else the default."
  def attr(field, name, attrs) do
    {allowed, default} = Map.fetch!(attrs, name)
    if is_map(field) and field[name] in allowed, do: field[name], else: default
  end

  defp put_attrs(field, source, attrs) do
    Enum.reduce(attrs, field, fn {name, _allowed}, acc ->
      Map.put(acc, name, attr(source, name, attrs))
    end)
  end

  @doc """
  Checks a whole definition (one read back from storage or sent over
  an API): `{:ok, definition}` with every field normalised, or
  `{:error, %{field_index => errors}}` / `{:error, %{form: code}}`.
  Fields without an id get one; duplicate ids are refused. `locked`
  are the app's locked fields (as for `with_locked/2`): each must come
  at its own place, first (`:locked_removed` / `:locked_moved`), and
  takes only "required" and "hint" from what was sent. `attrs` are
  the app's attributes, checked like the editor's.
  """
  def normalize(definition, locked \\ [], attrs \\ %{})

  def normalize(definition, locked, attrs) when is_list(definition) do
    case locked_place(definition, locked) do
      :ok -> normalize_fields(definition, locked, attrs)
      code -> {:error, %{form: code}}
    end
  end

  def normalize(_definition, _locked, _attrs), do: {:error, %{form: :not_a_list}}

  defp locked_place(definition, locked) do
    ids = Enum.map(definition, &(is_map(&1) && &1["id"]))

    locked
    |> Enum.with_index()
    |> Enum.find_value(:ok, fn {default, index} ->
      cond do
        Enum.at(ids, index) == default["id"] -> nil
        default["id"] in ids -> :locked_moved
        true -> :locked_removed
      end
    end)
  end

  defp normalize_fields(definition, locked, attrs) do
    {fields, errors} =
      definition
      |> Enum.with_index()
      |> Enum.reduce({[], %{}}, fn {raw, index}, {ok, bad} ->
        raw = if is_map(raw), do: raw, else: %{}
        id = if is_binary(raw["id"]) and raw["id"] != "", do: raw["id"], else: new_id()

        built =
          case field(locked, id) do
            nil -> build_field(sent_params(raw, attrs), id, attrs)
            default -> rebuild(Map.put(default, "locked", true), field_params(raw, attrs), attrs)
          end

        case built do
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

  # a sent field as the editor's params, its app attributes as sent
  # (so a value outside the allowed ones is refused, not replaced)
  defp sent_params(raw, attrs),
    do: Map.merge(field_params(raw, attrs), Map.take(raw, Map.keys(attrs)))

  @doc "A field as the editor's params (the edit form's starting values)."
  def field_params(field, attrs \\ %{})

  def field_params(nil, attrs),
    do: put_attrs(%{"type" => "text", "required" => "no"}, nil, attrs)

  def field_params(field, attrs) when is_map(field) do
    %{
      "label" => field["label"],
      "hint" => field["hint"],
      "type" => field["type"],
      "required" => if(field["required"] in [true, "yes", "true"], do: "yes", else: "no"),
      "options" => field["options"] |> List.wrap() |> Enum.join("\n")
    }
    |> put_attrs(field, attrs)
  end

  @doc "The editor's params as a field with this id: `{:ok, field}` or `{:error, errors}`."
  def build_field(params, id, attrs \\ %{})

  def build_field(params, id, attrs) when is_map(params) do
    label = Core.Text.clean(params["label"], required: true, max: @label_max)
    hint = Core.Text.clean(params["hint"], max: @hint_max)
    type = params["type"]
    options = if choice_type?(type), do: options(params["options"]), else: []

    errors =
      %{}
      |> put_error(:label, match?({:error, _}, label), elem(label, 1))
      |> put_error(:hint, match?({:error, _}, hint), elem(hint, 1))
      |> put_error(:type, type not in @types, :unknown_type)
      |> put_error(:options, choice_type?(type) && options_error(options), options_error(options))

    # the app's attributes: the value sent (the default when none)
    values = for {name, {_allowed, default}} <- attrs, into: %{}, do: {name, params[name] || default}

    errors =
      Enum.reduce(attrs, errors, fn {name, {allowed, _default}}, acc ->
        put_error(acc, name, values[name] not in allowed, :not_allowed)
      end)

    if errors == %{} do
      {:ok,
       %{
         "id" => id,
         "type" => type,
         "label" => elem(label, 1),
         "hint" => elem(hint, 1),
         "required" => params["required"] in ["yes", "true", true],
         "options" => options,
         "locked" => false
       }
       |> Map.merge(values)}
    else
      {:error, errors}
    end
  end

  def build_field(_params, id, attrs), do: build_field(%{}, id, attrs)

  defp new_id, do: :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)

  defp options(raw) when is_binary(raw) do
    raw
    |> String.split(~r/\R/)
    |> Enum.map(&Core.Text.clean/1)
    |> Enum.reject(&(&1 == {:ok, nil}))
    |> Enum.map(fn
      {:ok, option} -> option
      {:error, _code} -> :invalid
    end)
  end

  defp options(raw) when is_list(raw),
    do: raw |> Enum.filter(&is_binary/1) |> Enum.join("\n") |> options()

  defp options(_raw), do: []

  defp options_error(options) do
    cond do
      :invalid in options ->
        :invalid

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

  @doc """
  Answers as the values a form shows again, keyed by field id - to
  prefill a form from earlier answers.

      iex> Core.Forms.answer_values([%{"id" => "a", "value" => "x"}])
      %{"a" => "x"}
  """
  def answer_values(answers) when is_list(answers),
    do: Map.new(answers, fn answer -> {answer["id"], answer["value"]} end)

  def answer_values(_answers), do: %{}

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
    case {Core.Text.clean(raw, multiline: field["type"] == "longtext"), field["required"]} do
      {{:ok, nil}, true} -> {:error, :required}
      {{:ok, nil}, _optional} -> {:ok, nil}
      {{:ok, value}, _required} -> check(field, value)
      {{:error, code}, _required} -> {:error, code}
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
    if email?(value), do: {:ok, value}, else: {:error, {:invalid, :email}}
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
