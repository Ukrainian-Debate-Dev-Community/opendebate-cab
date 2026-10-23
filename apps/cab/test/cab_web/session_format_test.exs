defmodule CabWeb.SessionFormatTest do
  use ExUnit.Case, async: true

  alias CabWeb.SessionFormat

  test "judges: the chair first, names from the room or the signups" do
    room = %{
      "RoomAdjudicators" => [
        %{"role" => "panelist", "EventParticipant" => %{"id" => 7}},
        %{"role" => "chair", "EventParticipant" => %{"id" => 5, "display_name" => "Olena"}}
      ]
    }

    assert SessionFormat.judges(room, [%{"id" => 7, "display_name" => "Taras"}]) == [
             %{name: "Olena", chair: true},
             %{name: "Taras", chair: false}
           ]

    assert SessionFormat.judges(%{}, []) == []
  end

  test "speaker_list: the people who speak, an iron speaker once" do
    iron = %{"EventParticipant" => %{"id" => 1, "display_name" => "Anna"}}
    assert SessionFormat.speaker_list(%{"RoomSpeakers" => [iron, iron]}) == ["Anna"]
    assert SessionFormat.speaker_list(%{}) == []
  end

  test "rank_points: N - rank, as the engine's standings count it" do
    room = %{"RoomTeams" => [%{}, %{}, %{}, %{}]}
    assert SessionFormat.rank_points(room, %{"rank" => 1}) == 3
    assert SessionFormat.rank_points(room, %{"rank" => 4}) == 0
    assert SessionFormat.rank_points(room, %{}) == nil
  end
end
