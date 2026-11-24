defmodule Cab.FormatTest do
  use ExUnit.Case, async: true

  alias Cab.Format

  test "BP: four teams of two, OG first; a room seats nine" do
    bp = Format.get("bp")

    assert bp.code == "BP"
    assert Format.teams(bp) == 4
    assert Format.speeches(bp) == 8
    assert Format.room_seats(bp) == 9
    assert Format.side(bp, 1) == "og"
    assert Format.side(bp, 4) == "co"
    assert Format.position(bp, "cg") == 3
  end

  test "Australs: Government v Opposition, three a team; a room seats seven" do
    aus = Format.get("aus")

    assert aus.code == "AUS"
    assert Format.teams(aus) == 2
    assert Format.speeches(aus) == 6
    assert Format.room_seats(aus) == 7
    assert Format.side(aus, 2) == "opp"
    assert Format.side(aus, 3) == nil
    assert Format.position(aus, "og") == nil
  end

  test "a session's format, BP when it names none" do
    assert Format.of(%{format: "aus"}).key == "aus"
    assert Format.of(%{format: nil}).key == "bp"
    assert Format.of(%{}).key == "bp"
    assert Format.keys() == ["bp", "aus"]
  end

  test "scores are whole points within the range" do
    bp = Format.default()

    assert Format.valid_score?(bp, 75)
    assert Format.valid_score?(bp, 75.0)
    refute Format.valid_score?(bp, 75.5)
    refute Format.valid_score?(bp, 49)
    refute Format.valid_score?(bp, 101)
    refute Format.valid_score?(bp, "75")
  end
end
