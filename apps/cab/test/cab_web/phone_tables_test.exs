defmodule CabWeb.PhoneTablesTest do
  @moduledoc """
  On a phone every table folds into cards. That holds because every table
  is drawn by Ui.Components.table/1 (apps/ui: class "t t-rows", each cell
  labelled); the one exception is the allocator, which has its own phone
  layout.
  """
  use ExUnit.Case, async: true

  @root Path.expand("../../lib/cab_web", __DIR__)

  test "every table is the shared table component, or the allocator" do
    tables =
      for file <- Path.wildcard(Path.join(@root, "**/*.{ex,heex}")),
          tag <- Regex.scan(~r/<table\b[^>]*>/, File.read!(file)) |> List.flatten(),
          do: {Path.relative_to(file, @root), tag}

    {allocator, others} = Enum.split_with(tables, fn {_file, tag} -> tag == "<table>" end)

    assert [{"components/ui.ex", _}] = allocator,
           "a bare <table> outside the allocator: use the table component so it folds into cards"

    assert others == [],
           "tables must come from Ui.Components.table/1: " <> inspect(others)
  end
end
