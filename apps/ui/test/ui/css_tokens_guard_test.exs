defmodule Ui.CssTokensGuardTest do
  @moduledoc """
  Every stylesheet of ui, cab and the public site takes its colours,
  sizes, spacing and radii from tokens.css, so a tenant's theme and the
  fluid scale reach all of it. Kept on purpose: 16px fields on phones
  (the iOS no-zoom rule), em sizes inside text, the script wordmark,
  SVG map labels, hairlines (1-3px) and the three breakpoints.
  """
  use ExUnit.Case, async: true

  @root Path.expand("../../..", __DIR__)
  @breakpoints ~w(760px 761px 1000px 1001px 80rem)

  defp sheets do
    for glob <- ["ui/assets/css/**/*.css", "cab/assets/css/*.css", "public/assets/css/*.css"],
        path <- Path.wildcard(Path.join(@root, glob)),
        not String.contains?(path, "/vendor/"),
        Path.basename(path) != "tokens.css",
        do: path
  end

  # every innermost block: {file, selector, declarations}
  defp blocks do
    for path <- sheets(),
        css = path |> File.read!() |> String.replace(~r{/\*.*?\*/}s, ""),
        [_, selector, body] <- Regex.scan(~r/([^{}]*)\{([^{}]*)\}/, css),
        do: {Path.relative_to(path, @root), String.trim(selector), body}
  end

  defp declarations(body) do
    for [_, prop, value] <- Regex.scan(~r/([a-z-]+)\s*:\s*([^;]+)/, body),
        do: {prop, String.trim(value)}
  end

  test "no colour outside the tokens" do
    offenders =
      for {file, sel, body} <- blocks(),
          {prop, value} <- declarations(body),
          not String.contains?(prop, "mask"),
          value =~ ~r/#[0-9a-fA-F]{3,8}\b|rgba?\(|hsla?\(/,
          do: "#{file} #{sel} { #{prop}: #{value} }"

    assert offenders == []
  end

  test "font sizes come from the type scale" do
    offenders =
      for {file, sel, body} <- blocks(),
          not String.contains?(body, "--font-script"),
          not (sel =~ ~r/(^|[\s,>])text\b/),
          {"font-size", value} <- declarations(body),
          value =~ ~r/^[0-9.]+(rem|px)$/,
          value != "16px",
          do: "#{file} #{sel} { font-size: #{value} }"

    assert offenders == []
  end

  test "spacing, sizes and radii use tokens or rem, not pixels" do
    offenders =
      for {file, sel, body} <- blocks(),
          {prop, value} <- declarations(body),
          prop =~
            ~r/^(padding|margin|gap|row-gap|column-gap|width|height|min-width|min-height|max-width|max-height|border-radius)/,
          Regex.match?(~r/(?<![\d.])([4-9]|\d{2,})px/, value),
          do: "#{file} #{sel} { #{prop}: #{value} }"

    assert offenders == []
  end

  test "media queries use the three breakpoints" do
    used =
      for path <- sheets(),
          [query] <- Regex.scan(~r/@media[^{]*/, File.read!(path)),
          [width] <- Regex.scan(~r/\d+(?:px|rem)/, query),
          uniq: true,
          do: width

    assert used -- @breakpoints == []
  end
end
