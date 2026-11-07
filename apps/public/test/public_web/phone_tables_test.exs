defmodule PublicWeb.PhoneTablesTest do
  @moduledoc """
  On a phone every table folds into cards: the site draws its tables
  with ui's table component (`<.table>`, whose cells carry their column
  labels), never with a hand-written <table>.
  """
  use ExUnit.Case, async: true

  @root Path.expand("../../lib/public_web", __DIR__)

  defp templates, do: Path.wildcard(Path.join(@root, "**/*.{ex,heex}"))

  test "no hand-written table: every table is ui's table component" do
    bad =
      for file <- templates(),
          tag <- Regex.scan(~r/<table\b[^>]*>/, File.read!(file)) |> List.flatten(),
          do: "#{Path.relative_to(file, @root)}: #{tag}"

    assert bad == [], "draw these with <.table> to fold into cards:\n" <> Enum.join(bad, "\n")
  end

  test "the site does draw tables, with the component" do
    assert Enum.any?(templates(), &(File.read!(&1) =~ "<.table"))
  end
end
