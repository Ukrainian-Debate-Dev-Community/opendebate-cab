defmodule Ui.PhoneTablesTest do
  @moduledoc """
  On a phone every table folds into cards: the apps draw every table
  with table/1 (class "t t-rows", each cell labelled with data-label),
  the one table ui draws.
  """
  use ExUnit.Case, async: true

  @root Path.expand("../../lib", __DIR__)

  test "the only table is the table component, every cell labelled" do
    tables =
      for file <- Path.wildcard(Path.join(@root, "**/*.{ex,heex}")),
          tag <- Regex.scan(~r/<table\b[^>]*>/, File.read!(file)) |> List.flatten(),
          do: {Path.relative_to(file, @root), tag}

    assert tables == [{"ui/components.ex", ~s(<table class="t t-rows" id={@id}>)}]

    # every body cell is cell/1, which labels it
    source = File.read!(Path.join(@root, "ui/components.ex"))
    [tbody] = Regex.run(~r/<tbody>.*<\/tbody>/s, source)
    assert tbody =~ ~s(<.cell :for={col <- @col})
    [cell] = Regex.run(~r/defp cell\(assigns\).*?"""\n  end/s, source)
    assert cell =~ ~s(data-label={@col[:label]})
  end
end
