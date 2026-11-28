defmodule CabWeb.BallotFormTest do
  use ExUnit.Case, async: true

  alias CabWeb.BallotForm

  defp speaker(id, participant),
    do: %{
      "id" => id,
      "EventParticipant" => %{"id" => participant, "display_name" => "P#{participant}"}
    }

  test "an Australs room: Gov and Opp, three roles each, a repeat speech prefilled iron" do
    room = %{
      "RoomTeams" => [
        # Opposition sent two people: the first speaks again third
        %{"position" => 2, "RoomSpeakers" => [speaker(4, 21), speaker(5, 22), speaker(6, 21)]},
        %{"position" => 1, "RoomSpeakers" => [speaker(1, 11), speaker(2, 12), speaker(3, 13)]}
      ]
    }

    [gov, opp] = BallotForm.teams(room, Cab.Format.get("aus"))

    assert {gov.side, opp.side} == {"gov", "opp"}
    assert Enum.map(gov.rows, & &1.role) == ["PM", "DPM", "GW"]
    assert Enum.map(opp.rows, & &1.role) == ["LO", "DLO", "OW"]
    assert Enum.map(opp.rows, & &1.iron) == [false, false, true]
    assert Enum.map(opp.rows, & &1.selected) == [21, 22, 21]
    assert length(opp.rows |> hd() |> Map.get(:speakers)) == 2
  end

  test "the submitted params as six entries, positions 1 and 2" do
    params = %{
      "gov" => %{
        "PM" => %{"speaker" => "11", "score" => "75"},
        "DPM" => %{"speaker" => "12", "score" => "74"},
        "GW" => %{"speaker" => "13", "score" => "73"}
      },
      "opp" => %{
        "LO" => %{"speaker" => "21", "score" => "76"},
        "DLO" => %{"speaker" => "22", "score" => "75"},
        "OW" => %{"speaker" => "21", "iron" => "on", "score" => "70"}
      }
    }

    scores = BallotForm.scores_from_params(params, Cab.Format.get("aus"))

    assert length(scores) == 6
    assert Enum.frequencies_by(scores, & &1["position"]) == %{1 => 3, 2 => 3}
    assert Enum.find(scores, &(&1["score"] == 70.0))["iron"]
  end
end
