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

  describe "pair_teams/2" do
    defp entry(id, points, opts \\ []) do
      %{
        id: id,
        name: "T#{id}",
        eliminated: false,
        points: points,
        firsts: 0,
        seconds: 0,
        thirds: 0,
        fourths: 0,
        side_counts: Keyword.get(opts, :side_counts, %{1 => 0, 2 => 0, 3 => 0, 4 => 0}),
        rounds: Keyword.get(opts, :rounds, %{1 => %{rank: 1, points: points, position: 1}})
      }
    end

    defp room_team_ids(room), do: Enum.map(room.teams, & &1.entry.id)

    test "round 1 (no ranked results): shuffles into one level-0 bracket" do
      entries = for id <- 1..8, do: entry(id, 0, rounds: %{})

      rooms = Tournaments.pair_teams(entries, shuffle: &Enum.reverse/1)

      assert length(rooms) == 2
      assert Enum.map(rooms, & &1.bracket) == [0, 0]
      # reversed seeds 8..1 folded (m=2): rooms seat seeds 1/4/5/8 and 2/3/6/7
      assert room_team_ids(Enum.at(rooms, 0)) == [8, 5, 4, 1]
      assert room_team_ids(Enum.at(rooms, 1)) == [7, 6, 3, 2]
      refute Enum.any?(rooms, fn room -> Enum.any?(room.teams, & &1.pullup) end)
    end

    test "brackets by points with pullups for odd brackets (20 teams -> 5 rooms)" do
      points =
        List.duplicate(9, 3) ++
          List.duplicate(6, 5) ++
          List.duplicate(3, 4) ++
          List.duplicate(2, 4) ++ List.duplicate(0, 4)

      entries = points |> Enum.with_index(1) |> Enum.map(fn {p, id} -> entry(id, p) end)

      rooms = Tournaments.pair_teams(entries)

      assert length(rooms) == 5
      # 3 nines + 1 pulled-up six; then 4 sixes; the pullup is flagged
      assert Enum.map(rooms, & &1.bracket) == [9, 6, 3, 2, 0]

      [top | _] = rooms
      pullups = Enum.filter(top.teams, & &1.pullup)
      assert Enum.map(pullups, & &1.entry.points) == [6]

      all_ids = rooms |> Enum.flat_map(&room_team_ids/1) |> Enum.sort()
      assert all_ids == Enum.to_list(1..20)

      # every room's positions are a permutation of 1..4
      for room <- rooms do
        assert room.teams |> Enum.map(& &1.position) |> Enum.sort() == [1, 2, 3, 4]
      end
    end

    test "folds within a bracket of 8: seeds 1/4/5/8 and 2/3/6/7" do
      entries = for id <- 1..8, do: entry(id, 4)

      [room_a, room_b] = Tournaments.pair_teams(entries)

      assert room_team_ids(room_a) == [1, 4, 5, 8]
      assert room_team_ids(room_b) == [2, 3, 6, 7]
    end

    test "rotates sides against each team's history" do
      # each team has sat everywhere except one position — the draw
      # must give each its missing side (total cost 0)
      missing = %{1 => 4, 2 => 3, 3 => 2, 4 => 1}

      entries =
        for id <- 1..4 do
          counts = Map.new(1..4, fn p -> {p, if(p == missing[id], do: 0, else: 1)} end)
          entry(id, 2, side_counts: counts)
        end

      [room] = Tournaments.pair_teams(entries)

      for %{entry: entry, position: position} <- room.teams do
        assert position == missing[entry.id]
      end
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
