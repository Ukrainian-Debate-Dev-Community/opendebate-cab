defmodule Public.OrganisationFreeTest do
  @moduledoc """
  The site is generic: what belongs to the organisation running it comes
  from its tenant folder, never from the code. No file under lib names
  the organisation, its country or its addresses. The language name
  `gettext("Ukrainian")` is the one exception: it names the uk locale.
  """
  use ExUnit.Case, async: true

  @lib Path.expand("../../lib", __DIR__)
  @words ~w(ukrain federation dfu uadebate)

  test "no file under lib names the organisation" do
    offences =
      for file <- Path.wildcard(Path.join(@lib, "**/*.{ex,exs,heex}")),
          text = file |> File.read!() |> String.replace(~s{gettext("Ukrainian")}, ""),
          word <- @words,
          String.contains?(String.downcase(text), word),
          do: "#{Path.relative_to(file, @lib)}: #{word}"

    assert offences == []
  end
end
