defmodule PublicWeb.PhoneTablesTest do
  @moduledoc """
  On a phone every table folds into cards (class "ua-t"): the first cell
  of a row is the card's title, every other cell is labelled with
  data-label, except action cells (class "r"), which sit beside the title.
  """
  use ExUnit.Case, async: true

  @root Path.expand("../../lib/public_web", __DIR__)

  defp templates, do: Path.wildcard(Path.join(@root, "**/*.{ex,heex}"))

  test "every table is a ua-t table" do
    bad =
      for file <- templates(),
          tag <- Regex.scan(~r/<table\b[^>]*>/, File.read!(file)) |> List.flatten(),
          not String.contains?(tag, ~s(class="ua-t")),
          do: "#{Path.relative_to(file, @root)}: #{tag}"

    assert bad == [],
           "tables must have class=\"ua-t\" to fold into cards:\n" <> Enum.join(bad, "\n")
  end

  test "every cell but a row's first is labelled, or is an action" do
    bad =
      for file <- templates(),
          [tbody] <-
            Regex.scan(~r/<tbody>(.*?)<\/tbody>/s, File.read!(file), capture: :all_but_first),
          [row] <- Regex.scan(~r/<tr\b[^>]*>(.*?)<\/tr>/s, tbody, capture: :all_but_first),
          td <- row |> then(&Regex.scan(~r/<td\b[^>]*>/, &1)) |> List.flatten() |> Enum.drop(1),
          not String.contains?(td, "data-label"),
          not String.contains?(td, ~s(class="r")),
          do: "#{Path.relative_to(file, @root)}: #{td}"

    assert bad == [], "label these cells with data-label:\n" <> Enum.join(bad, "\n")
  end
end
