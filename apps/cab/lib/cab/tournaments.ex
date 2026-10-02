defmodule Cab.Tournaments do
  @moduledoc """
  Tournament-director ("full control") flow logic for the cab pages.
  Pure orchestration over `Cab.EngineApi`: pairing checked-in teams
  into rooms, deriving team ranks from speaker scores, breaking to a
  final and finding the champion. Engine data is kept as the raw
  decoded JSON maps the engine returns.
  """

  alias Cab.EngineApi

  @teams_per_room 4
  @speakers_per_team 2

  def teams_per_room, do: @teams_per_room

  # ---------------------------------------------------------------
  # Rounds / motions
  # ---------------------------------------------------------------

  def round_by_sequence(actor, event_id, sequence) do
    with {:ok, rounds} <- EngineApi.list_rounds(actor, event_id) do
      case Enum.find(rounds, &(&1["sequence"] == sequence)) do
        nil -> {:error, "round #{sequence} does not exist yet"}
        round -> {:ok, round}
      end
    end
  end

  @doc """
  The motion of round `n` is the event motion whose infoslide carries
  the `"Round n"` marker (the engine has no round->motion link; rooms
  reference a motion optionally).
  """
  def round_motion(actor, event_id, sequence) do
    with {:ok, motions} <- EngineApi.list_motions(actor, event_id) do
      {:ok, Enum.find(motions, &(&1["infoslide"] == round_marker(sequence)))}
    end
  end

  def set_round_motion(actor, event_id, sequence, text) do
    with {:ok, existing} <- round_motion(actor, event_id, sequence) do
      case existing do
        nil ->
          EngineApi.create_motion(actor, event_id, text, %{infoslide: round_marker(sequence)})

        motion ->
          EngineApi.update_motion(actor, event_id, motion["id"], %{motion_text: text})
      end
    end
  end

  def release_round_motion(actor, event_id, sequence) do
    case round_motion(actor, event_id, sequence) do
      {:ok, nil} -> {:error, "no motion set for round #{sequence} yet"}
      {:ok, motion} -> EngineApi.release_motion(actor, event_id, motion["id"])
      error -> error
    end
  end

  defp round_marker(sequence), do: "Round #{sequence}"

  # ---------------------------------------------------------------
  # Standings (gateway-built). The engine's calculated endpoint knows
  # only total points over ALL rounds; BP needs the precedence metrics,
  # per-round cells, prelim-only counting (elimination results decide
  # advancement, never standings) and the side/pullup metadata the
  # power-paired draw consumes. One builder feeds all of it.
  # ---------------------------------------------------------------

  @semi_name "SF"
  @grand_final_name "GF"

  @elim_round_names [@semi_name, @grand_final_name, "Final"]

  @doc "Is this an elimination round (SF / GF / legacy Final)?"
  def elim_round?(round), do: round["name"] in @elim_round_names

  @doc """
  BP team standings built from the raw room results of the PRELIMINARY
  rounds only. Entries are sorted by the BP precedence
  points → firsts → seconds → thirds → name. (Speaks-sum is not in the
  precedence: the engine exposes no raw speaker scores — deferred per
  the gap map.) Each entry:

      %{id, name, eliminated, points, firsts, seconds, thirds, fourths,
        side_counts: %{1 => n, 2 => n, 3 => n, 4 => n},
        rounds: %{sequence => %{rank, points, position}}}
  """
  def standings(actor, event_id) do
    with {:ok, teams} <- EngineApi.list_teams(actor, event_id),
         {:ok, rounds} <- EngineApi.list_rounds(actor, event_id),
         {:ok, round_rooms} <- prelim_round_rooms(actor, rounds) do
      {:ok, build_standings(teams, round_rooms)}
    end
  end

  @doc "Preliminary rounds (ordered) each paired with its rooms."
  def prelim_round_rooms(actor, rounds) do
    rounds
    |> Enum.reject(&elim_round?/1)
    |> Enum.sort_by(& &1["sequence"])
    |> Enum.reduce_while({:ok, []}, fn round, {:ok, acc} ->
      case EngineApi.list_rooms(actor, round["id"]) do
        {:ok, rooms} -> {:cont, {:ok, acc ++ [{round, rooms}]}}
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
  end

  @doc """
  Pure core of `standings/2`: folds `[{round, rooms}]` (prelims only)
  into sorted standings entries. Swing teams never earn standings.
  """
  def build_standings(teams, round_rooms) do
    base =
      teams
      |> Enum.reject(& &1["is_swing"])
      |> Map.new(fn team ->
        {team["id"],
         %{
           id: team["id"],
           name: team["name"],
           eliminated: team["is_eliminated"] == true,
           points: 0,
           firsts: 0,
           seconds: 0,
           thirds: 0,
           fourths: 0,
           side_counts: %{1 => 0, 2 => 0, 3 => 0, 4 => 0},
           rounds: %{}
         }}
      end)

    round_rooms
    |> Enum.reduce(base, fn {round, rooms}, acc ->
      Enum.reduce(rooms, acc, fn room, acc ->
        room_teams = room["RoomTeams"] || []
        size = length(room_teams)

        Enum.reduce(room_teams, acc, fn room_team, acc ->
          team_id = get_in(room_team, ["Team", "id"])

          case acc do
            %{^team_id => entry} ->
              Map.put(acc, team_id, apply_result(entry, round["sequence"], room_team, size))

            _ ->
              acc
          end
        end)
      end)
    end)
    |> Map.values()
    |> Enum.sort_by(&{-&1.points, -&1.firsts, -&1.seconds, -&1.thirds, &1.name})
  end

  defp apply_result(entry, sequence, room_team, size) do
    position = room_team["position"]
    rank = room_team["rank"]

    entry =
      update_in(entry, [:side_counts, position], &((&1 || 0) + 1))

    case rank do
      nil ->
        put_in(entry, [:rounds, sequence], %{rank: nil, points: nil, position: position})

      rank ->
        points = size - rank

        %{entry | points: entry.points + points}
        |> bump_place(rank)
        |> put_in([:rounds, sequence], %{rank: rank, points: points, position: position})
    end
  end

  defp bump_place(entry, 1), do: %{entry | firsts: entry.firsts + 1}
  defp bump_place(entry, 2), do: %{entry | seconds: entry.seconds + 1}
  defp bump_place(entry, 3), do: %{entry | thirds: entry.thirds + 1}
  defp bump_place(entry, 4), do: %{entry | fourths: entry.fourths + 1}
  defp bump_place(entry, _rank), do: entry

  @doc "Points a standings entry earned in rounds strictly before `sequence`."
  def points_before(entry, sequence) do
    entry.rounds
    |> Enum.filter(fn {seq, cell} -> seq < sequence and is_integer(cell.points) end)
    |> Enum.map(fn {_seq, cell} -> cell.points end)
    |> Enum.sum()
  end

  @doc """
  The entry's position labels (OG/OO/CG/CO) in rounds strictly before
  `sequence`, in round order.
  """
  def side_history(entry, sequence) do
    entry.rounds
    |> Enum.filter(fn {seq, cell} -> seq < sequence and cell.position != nil end)
    |> Enum.sort_by(fn {seq, _cell} -> seq end)
    |> Enum.map(fn {_seq, cell} -> position_label(cell.position) end)
  end

  @position_labels %{1 => "OG", 2 => "OO", 3 => "CG", 4 => "CO"}

  @doc "Short BP label for a table position (1..4 → OG/OO/CG/CO)."
  def position_label(position), do: Map.get(@position_labels, position, "#{position}")

  # ---------------------------------------------------------------
  # Check-in (team level: a team is checked in when all speakers are)
  # ---------------------------------------------------------------

  def teams_with_checkin(actor, event_id) do
    with {:ok, teams} <- EngineApi.list_teams(actor, event_id),
         {:ok, participants} <- EngineApi.list_participants(actor, event_id) do
      checked = for p <- participants, p["checked_in"], into: MapSet.new(), do: p["id"]

      teams =
        Enum.map(teams, fn team ->
          member_ids = Enum.map(team["speakers"], & &1["participant_id"])

          Map.put(
            team,
            "checked_in",
            member_ids != [] and Enum.all?(member_ids, &(&1 in checked))
          )
        end)

      {:ok, teams}
    end
  end

  def set_team_checkin(actor, event_id, team, status) do
    EngineApi.check_in(
      actor,
      event_id,
      Enum.map(team["speakers"], & &1["participant_id"]),
      status
    )
  end

  # ---------------------------------------------------------------
  # Room generation (no engine auto-generate for rooms; explicit POST)
  # ---------------------------------------------------------------

  @doc """
  Pairs checked-in, non-eliminated teams into rooms of #{@teams_per_room}
  (ordered by current standings so later rounds approximate power
  pairing) and creates them with one judge as chair per room.
  """
  def generate_rooms(actor, event_id, round) do
    with {:ok, teams} <- teams_with_checkin(actor, event_id),
         {:ok, participants} <- EngineApi.list_participants(actor, event_id),
         {:ok, standings} <- EngineApi.team_standings(actor, event_id),
         {:ok, existing_rooms} <- EngineApi.list_rooms(actor, round["id"]) do
      cond do
        existing_rooms != [] ->
          {:error, "round already has #{length(existing_rooms)} room(s)"}

        true ->
          eligible =
            teams
            |> Enum.filter(& &1["checked_in"])
            |> Enum.reject(& &1["is_eliminated"])

          points = Map.new(standings, &{&1["id"], &1["total_points"]})

          ordered =
            Enum.sort_by(eligible, fn t -> {-(points[t["id"]] || 0), t["id"]} end)

          judges =
            participants
            |> Enum.filter(&(&1["role"] == "adjudicator"))
            |> Enum.reject(& &1["is_eliminated"])

          room_count = div(length(ordered), @teams_per_room)

          cond do
            ordered == [] or rem(length(ordered), @teams_per_room) != 0 ->
              {:error,
               "need a multiple of #{@teams_per_room} checked-in teams (have #{length(ordered)})"}

            length(judges) < room_count ->
              {:error, "need at least #{room_count} judges (have #{length(judges)})"}

            true ->
              motion_id = round_motion_id(actor, event_id, round["sequence"])
              create_rooms(actor, round["id"], ordered, judges, motion_id)
          end
      end
    end
  end

  defp round_motion_id(actor, event_id, sequence) do
    case round_motion(actor, event_id, sequence) do
      {:ok, %{"id" => id}} -> id
      _ -> nil
    end
  end

  defp create_rooms(actor, round_id, ordered_teams, judges, motion_id) do
    ordered_teams
    |> Enum.chunk_every(@teams_per_room)
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, 0}, fn {chunk, index}, {:ok, count} ->
      team_slots =
        chunk
        |> Enum.with_index(1)
        |> Enum.map(fn {team, position} -> %{team_id: team["id"], position: position} end)

      chair = Enum.at(judges, index)
      adjudicators = [%{participant_id: chair["id"], role: "chair"}]

      case EngineApi.create_room(actor, round_id, team_slots, adjudicators, motion_id: motion_id) do
        {:ok, _} -> {:cont, {:ok, count + 1}}
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
  end

  # ---------------------------------------------------------------
  # Ballots
  # ---------------------------------------------------------------

  @doc """
  Builds the engine ballot payload for `room` from a map of
  `room_speaker_id => score`. Team ranks are derived from the sum of
  each team's speaker scores (ties broken by table position).
  Returns `{:ok, team_rankings, speaker_scores}` or `{:error, msg}`.
  """
  def ballot_payload(room, scores_by_speaker_id) do
    room_teams = Enum.sort_by(room["RoomTeams"] || [], & &1["position"])

    speakers =
      Enum.flat_map(room_teams, fn rt ->
        Enum.map(rt["RoomSpeakers"] || [], &Map.put(&1, "_position", rt["position"]))
      end)

    missing =
      Enum.filter(speakers, fn sp -> not is_number(scores_by_speaker_id[sp["id"]]) end)

    if missing != [] do
      {:error, "please enter a numeric score for every speaker (#{length(missing)} missing)"}
    else
      speaker_scores =
        Enum.map(speakers, fn sp ->
          %{room_speaker_id: sp["id"], score: scores_by_speaker_id[sp["id"]]}
        end)

      team_rankings =
        room_teams
        |> Enum.map(fn rt ->
          total =
            (rt["RoomSpeakers"] || [])
            |> Enum.map(&(scores_by_speaker_id[&1["id"]] || 0))
            |> Enum.sum()

          {rt, total}
        end)
        |> Enum.sort_by(fn {rt, total} -> {-total, rt["position"]} end)
        |> Enum.with_index(1)
        |> Enum.map(fn {{rt, _total}, rank} -> %{room_team_id: rt["id"], rank: rank} end)

      {:ok, team_rankings, speaker_scores}
    end
  end

  @doc """
  Winner-pick ballot for the club flow: the chosen team is ranked 1
  (its speakers scored #{75 + 1}), everyone else keeps table order with
  a flat 75.
  """
  def winner_ballot_payload(room, winner_room_team_id) do
    scores =
      Enum.flat_map(room["RoomTeams"] || [], fn rt ->
        score = if rt["id"] == winner_room_team_id, do: 76, else: 75
        Enum.map(rt["RoomSpeakers"] || [], &{&1["id"], score})
      end)
      |> Map.new()

    ballot_payload(room, scores)
  end

  # ---------------------------------------------------------------
  # Final / champion
  # ---------------------------------------------------------------

  @final_name "Final"

  def final_name, do: @final_name

  @doc """
  Creates the final round (sequence = max + 1) with one room of the
  top-#{@teams_per_room} teams from the calculated standings.
  """
  def break_to_final(actor, event_id) do
    with {:ok, rounds} <- EngineApi.list_rounds(actor, event_id),
         :ok <- ensure_no_final(rounds),
         {:ok, standings} <- EngineApi.team_standings(actor, event_id),
         {:ok, participants} <- EngineApi.list_participants(actor, event_id) do
      top = Enum.take(standings, @teams_per_room)
      judges = Enum.filter(participants, &(&1["role"] == "adjudicator"))

      cond do
        length(top) < @teams_per_room ->
          {:error, "not enough ranked teams to break (need #{@teams_per_room})"}

        judges == [] ->
          {:error, "no judges available to chair the final"}

        true ->
          sequence = (rounds |> Enum.map(& &1["sequence"]) |> Enum.max(fn -> 0 end)) + 1

          team_slots =
            top
            |> Enum.with_index(1)
            |> Enum.map(fn {team, position} -> %{team_id: team["id"], position: position} end)

          adjudicators = [%{participant_id: hd(judges)["id"], role: "chair"}]

          with {:ok, round} <- EngineApi.create_round(actor, event_id, @final_name, sequence),
               {:ok, _} <- EngineApi.create_room(actor, round["id"], team_slots, adjudicators) do
            {:ok, round}
          end
      end
    end
  end

  defp ensure_no_final(rounds) do
    if Enum.any?(rounds, &(&1["name"] == @final_name)),
      do: {:error, "a final has already been created"},
      else: :ok
  end

  @doc """
  Winner of a round: the rank-1 team of its completed/confirmed rooms.
  Shared by the tournament champion and the club session history.
  Returns `{:ok, team_name | nil}`.
  """
  def round_winner(actor, round) do
    with {:ok, rooms} <- EngineApi.list_rooms(actor, round["id"]) do
      winner =
        rooms
        |> Enum.filter(&(&1["status"] in ["completed", "confirmed"]))
        |> Enum.flat_map(&(&1["RoomTeams"] || []))
        |> Enum.find(&(&1["rank"] == 1))

      {:ok, winner && get_in(winner, ["Team", "name"])}
    end
  end

  @doc """
  The champion is the winner of the round named "#{@final_name}".
  Returns `{:ok, team_name | nil}`.
  """
  def champion(actor, event_id) do
    with {:ok, rounds} <- EngineApi.list_rounds(actor, event_id) do
      case Enum.find(rounds, &(&1["name"] == @final_name)) do
        nil -> {:ok, nil}
        final -> round_winner(actor, final)
      end
    end
  end

  @doc """
  Winner of an event: the winner of its last round. Used by the club
  session history (one-round events).
  """
  def event_winner(actor, event) do
    with {:ok, rounds} <- EngineApi.list_rounds(actor, event["id"]),
         last_round when not is_nil(last_round) <-
           Enum.max_by(rounds, & &1["sequence"], fn -> nil end),
         {:ok, winner} <- round_winner(actor, last_round) do
      winner
    else
      _ -> nil
    end
  end

  @doc """
  Parses "Team name: Speaker1, Speaker2" lines into
  `[{team_name, [speaker_names]}]`. Blank lines are skipped.
  """
  def parse_team_lines(text) do
    text
    |> String.split(~r/\R/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.reduce_while({:ok, []}, fn line, {:ok, acc} ->
      case String.split(line, ":", parts: 2) do
        [name, speakers] ->
          speaker_names =
            speakers |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

          if String.trim(name) == "" or speaker_names == [] or
               length(speaker_names) > @speakers_per_team do
            {:halt, {:error, "bad line (want \"Team: Speaker1, Speaker2\"): #{line}"}}
          else
            {:cont, {:ok, [{String.trim(name), speaker_names} | acc]}}
          end

        _ ->
          {:halt, {:error, "bad line (want \"Team: Speaker1, Speaker2\"): #{line}"}}
      end
    end)
    |> case do
      {:ok, teams} -> {:ok, Enum.reverse(teams)}
      error -> error
    end
  end

  @doc """
  Provisions shadow users + participants for the parsed team lines and
  creates the teams. Returns `{:ok, created_count}`.
  """
  def create_teams_from_lines(actor, event_id, text) do
    with {:ok, parsed} <- parse_team_lines(text) do
      Enum.reduce_while(parsed, {:ok, 0}, fn {team_name, speaker_names}, {:ok, count} ->
        with {:ok, participant_ids} <- provision_speakers(actor, event_id, speaker_names),
             {:ok, _team} <- EngineApi.create_team(actor, event_id, team_name, participant_ids) do
          {:cont, {:ok, count + 1}}
        else
          {:error, message} -> {:halt, {:error, "#{team_name}: #{message}"}}
        end
      end)
    end
  end

  defp provision_speakers(actor, event_id, speaker_names) do
    Enum.reduce_while(speaker_names, {:ok, []}, fn name, {:ok, ids} ->
      case EngineApi.provision_participant(actor, event_id, name, "speaker") do
        {:ok, participant} -> {:cont, {:ok, ids ++ [participant["id"]]}}
        {:error, message} -> {:halt, {:error, "#{name}: #{message}"}}
      end
    end)
  end
end
