defmodule Cab.TournamentsTest do
  use ExUnit.Case, async: true

  alias Cab.Tournaments

  describe "parse_team_lines/1" do
    test "parses team and speaker names, skipping blank lines" do
      assert {:ok, [{"Alpha", ["Alice", "Aaron"]}, {"Bravo", ["Bob"]}]} =
               Tournaments.parse_team_lines("Alpha: Alice, Aaron\n\nBravo: Bob\n")
    end

    test "rejects lines without a colon" do
      assert {:error, "bad line" <> _} = Tournaments.parse_team_lines("just some words")
    end

    test "rejects more than two speakers" do
      assert {:error, "bad line" <> _} = Tournaments.parse_team_lines("Alpha: A, B, C")
    end
  end

  describe "ballot_payload/2" do
    defp room do
      %{
        "RoomTeams" => [
          %{
            "id" => 1,
            "position" => 1,
            "RoomSpeakers" => [%{"id" => 11}, %{"id" => 12}]
          },
          %{
            "id" => 2,
            "position" => 2,
            "RoomSpeakers" => [%{"id" => 21}, %{"id" => 22}]
          }
        ]
      }
    end

    test "derives ranks from team score sums" do
      scores = %{11 => 70, 12 => 70, 21 => 80, 22 => 80}

      assert {:ok, rankings, speaker_scores} = Tournaments.ballot_payload(room(), scores)

      assert rankings == [
               %{room_team_id: 2, rank: 1},
               %{room_team_id: 1, rank: 2}
             ]

      assert length(speaker_scores) == 4
      assert %{room_speaker_id: 11, score: 70} in speaker_scores
    end

    test "breaks ties by table position" do
      scores = %{11 => 75, 12 => 75, 21 => 75, 22 => 75}

      assert {:ok, [%{room_team_id: 1, rank: 1}, %{room_team_id: 2, rank: 2}], _} =
               Tournaments.ballot_payload(room(), scores)
    end

    test "reports missing scores" do
      assert {:error, message} = Tournaments.ballot_payload(room(), %{11 => 70})
      assert message =~ "3 missing"
    end
  end

  describe "build_standings/2" do
    defp team(id, name, opts \\ []) do
      %{
        "id" => id,
        "name" => name,
        "is_swing" => Keyword.get(opts, :swing, false),
        "is_eliminated" => Keyword.get(opts, :eliminated, false)
      }
    end

    defp result_room(results) do
      # results: [{team_id, position, rank}]
      %{
        "RoomTeams" =>
          Enum.map(results, fn {team_id, position, rank} ->
            %{"position" => position, "rank" => rank, "Team" => %{"id" => team_id}}
          end)
      }
    end

    test "sums points as size - rank over prelim rounds and counts places" do
      teams = [team(1, "Alpha"), team(2, "Bravo"), team(3, "Charlie"), team(4, "Delta")]

      r1 = {%{"sequence" => 1}, [result_room([{1, 1, 1}, {2, 2, 2}, {3, 3, 3}, {4, 4, 4}])]}
      r2 = {%{"sequence" => 2}, [result_room([{1, 2, 1}, {2, 1, 2}, {3, 4, 4}, {4, 3, 3}])]}

      [first, second, third, fourth] = Tournaments.build_standings(teams, [r1, r2])

      assert %{name: "Alpha", points: 6, firsts: 2, seconds: 0} = first
      assert %{name: "Bravo", points: 4, seconds: 2} = second
      # Charlie and Delta tie on every metric — alphabetical order
      assert %{name: "Charlie", points: 1, thirds: 1, fourths: 1} = third
      assert %{name: "Delta", points: 1, thirds: 1, fourths: 1} = fourth
      assert first.rounds[2] == %{rank: 1, points: 3, position: 2}
      assert first.side_counts == %{1 => 1, 2 => 1, 3 => 0, 4 => 0}
    end

    test "precedence: points, then firsts, then seconds, then thirds, then name" do
      teams = [team(1, "Zulu"), team(2, "Alpha")]

      # Zulu: 3+0 points via one 1st and one 4th; Alpha: 2+1 via two middles
      rounds = [
        {%{"sequence" => 1},
         [
           result_room([{1, 1, 1}, {10, 2, 2}, {11, 3, 3}, {12, 4, 4}]),
           result_room([{2, 1, 2}, {13, 2, 1}, {14, 3, 3}, {15, 4, 4}])
         ]},
        {%{"sequence" => 2},
         [
           result_room([{1, 1, 4}, {10, 2, 1}, {11, 3, 2}, {12, 4, 3}]),
           result_room([{2, 1, 3}, {13, 2, 1}, {14, 3, 2}, {15, 4, 4}])
         ]}
      ]

      [a, b] = Tournaments.build_standings(teams, rounds)
      # equal on points (3 vs 3): Zulu has a 1st, Alpha none
      assert {a.name, a.points} == {"Zulu", 3}
      assert {b.name, b.points} == {"Alpha", 3}
    end

    test "ignores swing teams, unranked rooms and unknown teams" do
      teams = [team(1, "Alpha"), team(2, "Swing", swing: true)]

      rounds = [
        {%{"sequence" => 1},
         [result_room([{1, 1, nil}, {2, 2, nil}, {99, 3, nil}, {98, 4, nil}])]}
      ]

      assert [entry] = Tournaments.build_standings(teams, rounds)
      assert %{name: "Alpha", points: 0, firsts: 0} = entry
      assert entry.rounds[1] == %{rank: nil, points: nil, position: 1}
      assert entry.side_counts[1] == 1
    end

    test "points_before and side_history look strictly before a round" do
      teams = [team(1, "Alpha")]

      rounds = [
        {%{"sequence" => 1}, [result_room([{1, 1, 1}, {7, 2, 2}, {8, 3, 3}, {9, 4, 4}])]},
        {%{"sequence" => 2}, [result_room([{1, 4, 2}, {7, 1, 1}, {8, 2, 3}, {9, 3, 4}])]}
      ]

      [entry] = Tournaments.build_standings(teams, rounds)

      assert Tournaments.points_before(entry, 2) == 3
      assert Tournaments.points_before(entry, 3) == 5
      assert Tournaments.side_history(entry, 2) == ["OG"]
      assert Tournaments.side_history(entry, 3) == ["OG", "CO"]
    end

    test "elim_round? recognises SF, GF and legacy Final" do
      assert Tournaments.elim_round?(%{"name" => "SF"})
      assert Tournaments.elim_round?(%{"name" => "GF"})
      assert Tournaments.elim_round?(%{"name" => "Final"})
      refute Tournaments.elim_round?(%{"name" => "Round 3"})
      refute Tournaments.elim_round?(%{"name" => "Club round"})
    end
  end

  describe "winner_ballot_payload/2" do
    test "ranks the chosen team first" do
      room = %{
        "RoomTeams" => [
          %{"id" => 1, "position" => 1, "RoomSpeakers" => [%{"id" => 11}]},
          %{"id" => 2, "position" => 2, "RoomSpeakers" => [%{"id" => 21}]}
        ]
      }

      assert {:ok, [%{room_team_id: 2, rank: 1}, %{room_team_id: 1, rank: 2}], scores} =
               Tournaments.winner_ballot_payload(room, 2)

      assert %{room_speaker_id: 21, score: 76} in scores
      assert %{room_speaker_id: 11, score: 75} in scores
    end
  end
end
