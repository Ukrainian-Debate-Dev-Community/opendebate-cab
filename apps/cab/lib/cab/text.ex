defmodule Cab.Text do
  @moduledoc """
  `Core.Text` for cab's forms: a changeset step and plain checks, with
  the codes worded in the errors domain. Required text with nothing
  visible in it is blank; optional text like that is stored as nil.
  """

  use Gettext, backend: CabWeb.Gettext

  import Ecto.Changeset

  @doc """
  Cleans the changed `fields` with `Core.Text.clean/2`. Options:
  `max:` and `multiline:` as there, `required:` with `message:` for
  `validate_required/3` (the field's own words, else "Fill this in.").
  """
  def clean_text(changeset, fields, opts \\ []) do
    fields = List.wrap(fields)

    changeset =
      Enum.reduce(fields, changeset, fn field, acc ->
        case fetch_change(acc, field) do
          {:ok, value} when is_binary(value) -> put_clean(acc, field, value, opts)
          _unchanged -> acc
        end
      end)

    if opts[:required],
      do:
        validate_required(changeset, fields,
          message: opts[:message] || dgettext("errors", "Fill this in.")
        ),
      else: changeset
  end

  defp put_clean(changeset, field, value, opts) do
    case Core.Text.clean(value, Keyword.take(opts, [:max, :multiline])) do
      {:ok, text} ->
        put_change(changeset, field, text)

      {:error, {:too_long, max} = code} ->
        add_error(changeset, field, message(code),
          count: max,
          validation: :length,
          kind: :max,
          type: :string
        )

      {:error, code} ->
        add_error(changeset, field, message(code), validation: :format)
    end
  end

  @doc """
  One value outside a changeset: `{:ok, text | nil}` or
  `{:error, message}`. Options as `Core.Text.clean/2`, plus `message:`
  for empty required text.
  """
  def check(value, opts \\ []) do
    case Core.Text.clean(value, Keyword.take(opts, [:required, :max, :multiline])) do
      {:ok, text} -> {:ok, text}
      {:error, :required} -> {:error, opts[:message] || message(:required)}
      {:error, code} -> {:error, message(code)}
    end
  end

  @doc "A `Core.Text` error code as a message."
  def message(:required), do: dgettext("errors", "Fill this in.")

  def message({:too_long, max}),
    do: dgettext("errors", "%{count} characters at most.", count: max)

  def message(:invalid),
    do: dgettext("errors", "Use plain text without control characters.")

  @doc "The changeset's first error on these fields, in order, as `{field, message}`, or nil."
  def first_error(%Ecto.Changeset{errors: errors}, fields) do
    Enum.find_value(fields, fn field ->
      case Keyword.get(errors, field) do
        {message, opts} -> {field, interpolate(message, opts)}
        nil -> nil
      end
    end)
  end

  defp interpolate(message, opts),
    do: Gettext.dgettext(CabWeb.Gettext, "errors", message, Map.new(opts))
end
