defmodule Core.Text do
  @moduledoc """
  Typed text, cleaned one way in every form. `clean/2` trims
  whitespace and invisible characters at both ends (Unicode spaces,
  no-break spaces included, zero-width spaces and joiners, the
  byte-order mark, bidi marks, Hangul fillers, the braille blank):
  text with nothing visible left is empty, `nil`. It refuses control
  characters (a long text keeps newlines and tabs, its line breaks
  made LF) and anything that is not UTF-8 text, and counts the length
  in characters. Errors are codes, never text, as in `Core.Forms`:

    * `:required` - empty, while `required: true`
    * `{:too_long, max}` - more than `max:` characters
    * `:invalid` - a control character, or not text at all
  """

  @doc """
  The cleaned text: `{:ok, text}`, `{:ok, nil}` for empty text, or
  `{:error, code}`. Options: `required:` (empty is an error), `max:`
  (characters), `multiline:` (newlines and tabs allowed).
  """
  def clean(value, opts \\ [])

  def clean(nil, opts), do: empty(opts)

  def clean(value, opts) when is_binary(value) do
    multiline = Keyword.get(opts, :multiline, false)
    max = opts[:max]

    if String.valid?(value) do
      text = value |> line_breaks(multiline) |> trim()

      cond do
        text == "" -> empty(opts)
        control?(text, multiline) -> {:error, :invalid}
        max && String.length(text) > max -> {:error, {:too_long, max}}
        true -> {:ok, text}
      end
    else
      {:error, :invalid}
    end
  end

  def clean(_value, _opts), do: {:error, :invalid}

  @doc """
  The text without whitespace and invisible characters at its ends,
  `""` when nothing visible is left (or for anything but UTF-8 text) -
  for search fields and other input that is looked up, not stored.
  """
  def trim(value) when is_binary(value) do
    if String.valid?(value),
      do:
        String.replace(
          value,
          ~r/\A[\s\p{Z}\p{Cf}\x{034F}\x{115F}\x{1160}\x{2800}\x{3164}\x{FFA0}]+|[\s\p{Z}\p{Cf}\x{034F}\x{115F}\x{1160}\x{2800}\x{3164}\x{FFA0}]+\z/u,
          ""
        ),
      else: ""
  end

  def trim(_value), do: ""

  @doc "Is nothing visible typed?"
  def blank?(value), do: trim(value) == ""

  defp empty(opts) do
    if opts[:required], do: {:error, :required}, else: {:ok, nil}
  end

  defp line_breaks(text, true), do: String.replace(text, ~r/\r\n?/, "\n")
  defp line_breaks(text, false), do: text

  defp control?(text, true), do: text =~ ~r/[^\P{Cc}\n\t]/u
  defp control?(text, false), do: text =~ ~r/\p{Cc}/u
end
