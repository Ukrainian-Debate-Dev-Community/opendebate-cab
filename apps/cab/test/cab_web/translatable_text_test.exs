defmodule CabWeb.TranslatableTextTest do
  @moduledoc """
  Every word people read goes through gettext, so Ukrainian (and any
  later language) needs only a translation file. This scans every HEEx
  template and every ~H block under lib/cab_web and fails on visible
  text - a text node or an attribute people see - written as a bare
  literal instead of `{gettext(...)}`.
  """
  use ExUnit.Case, async: true

  @root Path.expand("../../lib/cab_web", __DIR__)

  # attributes whose values people read
  @visible_attrs ~w(label placeholder title aria-label hint note description empty here link alt)

  # literals that are the same in every language
  @allowed MapSet.new(~w(cab English Українська EN UA))

  test "no template shows bare, untranslatable text" do
    offences =
      for {file, source} <- templates(),
          offence <- offences(source),
          do: "#{Path.relative_to(file, @root)}: #{offence}"

    assert offences == [], "wrap these in gettext:\n" <> Enum.join(offences, "\n")
  end

  defp templates do
    heex =
      for file <- Path.wildcard(Path.join(@root, "**/*.heex")),
          do: {file, File.read!(file)}

    inline =
      for file <- Path.wildcard(Path.join(@root, "**/*.ex")),
          block <- Regex.scan(~r/~H"""\n(.*?)"""/s, File.read!(file), capture: :all_but_first),
          do: {file, hd(block)}

    heex ++ inline
  end

  defp offences(source) do
    source =
      source
      |> String.replace(~r/<%!--.*?--%>/s, "")
      |> String.replace(~r/<(script|style)\b.*?<\/\1>/s, "")

    attrs =
      for [name, value] <-
            Regex.scan(~r/\s(#{Enum.join(@visible_attrs, "|")})="([^"]*)"/, source,
              capture: :all_but_first
            ),
          words?(value),
          do: ~s(#{name}="#{value}")

    texts =
      source
      |> strip_expressions()
      |> String.replace(~r/<%.*?%>/s, " ")
      |> String.replace(~r/<[^>]*>/s, "\n")
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.filter(&words?/1)

    attrs ++ texts
  end

  # drop {...} interpolations, braces nested to any depth
  defp strip_expressions(source) do
    {out, _depth} =
      source
      |> String.graphemes()
      |> Enum.reduce({[], 0}, fn
        "{", {acc, depth} -> {acc, depth + 1}
        "}", {acc, depth} when depth > 0 -> {acc, depth - 1}
        char, {acc, 0} -> {[char | acc], 0}
        _char, {acc, depth} -> {acc, depth}
      end)

    out |> Enum.reverse() |> Enum.join()
  end

  # visible words: letters left once entities, email addresses, domain
  # names and constants are set aside
  defp words?(text) do
    text
    |> String.replace(~r/&[a-z]+;|&#\d+;/, " ")
    |> String.replace(~r/[\w.+-]+@[\w-]+(\.[\w-]+)+/, " ")
    |> String.replace(~r/\b[\w-]+(\.[a-z]{2,})+\b/, " ")
    |> String.split(~r/[^\p{L}]+/u, trim: true)
    |> Enum.reject(&MapSet.member?(@allowed, &1))
    |> Enum.any?()
  end
end
