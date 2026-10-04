defmodule Cab.Sessions do
  @moduledoc """
  Routine club sessions: a gateway row (public uuid) over a one-round
  engine event. All debate state lives in the engine — the gateway
  never duplicates it; `state/1` derives the stage from engine data
  on every read.

  Engine-call sequences (teams pairing, scored ballot, finishing) are
  ported from the proven v1-mvp `Cab.Clubs`/`Cab.Tournaments`.
  """

  import Ecto.Query

  alias Cab.Accounts
  alias Cab.Accounts.User
  alias Cab.Clubs
  alias Cab.Clubs.Club
  alias Cab.{EngineApi, Repo}
  alias Cab.Sessions.Session

  @teams_per_room 4
  @speakers_per_team 2

  # ---------------------------------------------------------------
  # Rows
  # ---------------------------------------------------------------

  def get_by_uuid(uuid) do
    case Ecto.UUID.cast(uuid) do
      {:ok, uuid} -> Repo.one(from s in Session, where: s.uuid == ^uuid, preload: :club)
      :error -> nil
    end
  end

  def list_for_club(%Club{} = club) do
    Repo.all(from s in Session, where: s.club_id == ^club.id, order_by: [desc: s.id])
  end

  @doc "The club's session with this uuid, or nil — guards cross-club ids."
  def get_for_club(%Club{} = club, uuid) do
    case get_by_uuid(uuid) do
      %Session{club_id: club_id} = session when club_id == club.id -> session
      _ -> nil
    end
  end

  # ---------------------------------------------------------------
  # Lifecycle
  # ---------------------------------------------------------------

  @doc """
  Opens a session: a one-round event in the club's engine organisation,
  ready for sign-ups, plus the gateway row. Motions are NOT set here —
  each room's judge sets their own room's motion once rooms are made.
  """
  def open(%User{} = head, %Club{} = club, name) do
    name = presence(name) || "Club session #{Date.utc_today()}"

    with {:ok, actor} <- actor_for(head),
         {:ok, event} <- EngineApi.create_event(actor, club.engine_organisation_id, name),
         {:ok, _round} <- EngineApi.create_round(actor, event["id"], "Club round", 1) do
      %Session{club_id: club.id, opened_by_user_id: head.id}
      |> Session.changeset(%{engine_event_id: event["id"]})
      |> Repo.insert()
    end
  end

  @doc """
  1-click self-registration: the member registers themselves for this
  session as "speak" or "judge". Their engine counterpart is ensured
  lazily; the engine enforces one registration per user per event.
  """
  def signup(%User{} = user, %Session{} = session, kind) when kind in ["speak", "judge"] do
    role = if kind == "speak", do: "speaker", else: "adjudicator"
    display_name = presence(user.name) || user.username

    with {:ok, actor} <- actor_for(user) do
      EngineApi.add_participant(actor, session.engine_event_id, display_name, role, actor)
    end
  end

  @doc """
  The session as the pages and the JSON API see it, composed from
  engine state: `%{event, round, signups, rooms, stage}` where stage
  is `:signup` (no rooms yet), `:running` (rooms made) or `:done`
  (event completed). Reads run as the club head's node user.
  """
  def state(%Session{} = session) do
    club = session_club(session)

    with {:ok, actor} <- Clubs.club_actor(club),
         {:ok, event} <- EngineApi.get_event(actor, session.engine_event_id),
         {:ok, round} <- round_by_sequence(actor, session.engine_event_id, 1),
         {:ok, signups} <- EngineApi.list_participants(actor, session.engine_event_id),
         {:ok, rooms} <- EngineApi.list_rooms(actor, round["id"]) do
      {:ok,
       %{
         event: event,
         round: round,
         signups: signups,
         rooms: rooms,
         stage: stage(event, rooms)
       }}
    end
  end

  defp stage(%{"status" => "completed"}, _rooms), do: :done
  defp stage(_event, []), do: :signup
  defp stage(_event, _rooms), do: :running

  @doc """
  Rooms by attendance (ported from v1-mvp): pairs the signed-up
  speakers into teams of #{@speakers_per_team} via the engine's
  auto-generate proposal, then creates one room per #{@teams_per_room}
  teams with signed-up judges as chairs. Requires speakers in
  multiples of #{@speakers_per_team * @teams_per_room} and one judge
  per room. Returns `{:ok, rooms_created}`.
  """
  def make_rooms(%User{} = head, %Session{} = session) do
    with {:ok, actor} <- actor_for(head),
         {:ok, round} <- round_by_sequence(actor, session.engine_event_id, 1),
         {:ok, participants} <- EngineApi.list_participants(actor, session.engine_event_id) do
      speakers = Enum.filter(participants, &(&1["role"] == "speaker"))
      judges = Enum.filter(participants, &(&1["role"] == "adjudicator"))
      room_size = @speakers_per_team * @teams_per_room
      room_count = div(length(speakers), room_size)

      cond do
        speakers == [] or rem(length(speakers), room_size) != 0 ->
          {:error,
           "need speakers in multiples of #{room_size} to fill rooms " <>
             "(have #{length(speakers)} signed up)"}

        length(judges) < room_count ->
          {:error, "need at least #{room_count} judge(s) (have #{length(judges)})"}

        true ->
          with {:ok, team_ids} <- create_attendance_teams(actor, session.engine_event_id) do
            create_session_rooms(actor, round, team_ids, judges)
          end
      end
    end
  end

  defp create_attendance_teams(actor, event_id) do
    with {:ok, %{"proposed_teams" => proposals}} <- EngineApi.propose_teams(actor, event_id) do
      Enum.reduce_while(proposals, {:ok, []}, fn proposal, {:ok, ids} ->
        name = team_name(proposal)

        case EngineApi.create_team(actor, event_id, name, proposal["participant_ids"]) do
          {:ok, team} -> {:cont, {:ok, ids ++ [team["id"]]}}
          {:error, message} -> {:halt, {:error, "#{name}: #{message}"}}
        end
      end)
    end
  end

  # "Ann & Bohdan" from the proposal's participants; falls back to the
  # engine's "Random Team N" name.
  defp team_name(%{"participants" => participants} = proposal) do
    case Enum.map(participants || [], &first_name(&1["display_name"])) do
      [] -> proposal["name"]
      names -> Enum.join(names, " & ")
    end
  end

  defp team_name(proposal), do: proposal["name"]

  defp first_name(nil), do: "?"
  defp first_name(display_name), do: display_name |> String.split() |> hd()

  # Rooms are created motion-less: each room's judge sets their own
  # motion afterwards via set_room_motion/3.
  defp create_session_rooms(actor, round, team_ids, judges) do
    team_ids
    |> Enum.chunk_every(@teams_per_room)
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, 0}, fn {chunk, index}, {:ok, count} ->
      slots =
        chunk
        |> Enum.with_index(1)
        |> Enum.map(fn {team_id, position} -> %{team_id: team_id, position: position} end)

      chair = Enum.at(judges, index)

      case EngineApi.create_room(actor, round["id"], slots, [
             %{participant_id: chair["id"], role: "chair"}
           ]) do
        {:ok, _} -> {:cont, {:ok, count + 1}}
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
  end

  @doc """
  The room's judge sets that room's motion (per-room motions — rooms
  of one session may debate different ones). Chair-guarded by the
  engine, with owner/organiser fall-through for the head.
  """
  def set_room_motion(%User{} = user, room_id, motion_text) do
    with {:ok, actor} <- actor_for(user) do
      EngineApi.set_room_motion(actor, room_id, motion_text)
    end
  end

  @doc """
  Submits a room's scored BP ballot (ported from the proven v1-mvp
  `Cab.Tournaments.ballot_payload/3`): 8 speaker scores — two per team
  in og/oo/cg/co table order — team ranks DERIVE from team totals
  (winner = rank 1, the judge never picks places), tied team totals
  rejected because BP demands a strict order of all four teams.

  `scores` is a list of 8 entries, two per team `position` 1..4, each
  `%{position, speaker_participant_id, iron, score}`: the participant
  id comes from the ballot's who-spoke dropdown, `iron` marks a
  stand-in covering a teammate's speech (same participant twice), and
  scores are 50-100 in 0.5 steps.

  Only the room's chair (the signed-up judge) or the club head may
  submit — `{:error, :forbidden}` otherwise. The ballot goes in as
  the acting user (the engine's chair guard with owner fall-through
  applies) and is then confirmed as the club head, since confirm is
  owner/organiser-only in the frozen engine.

  Returns `:ok`, `{:error, :forbidden}`, a changeset-style
  `{:error, %{scores: message}}` for invalid entries or tied totals,
  or `{:error, message}`.
  """
  def submit_ballot(%User{} = user, %Session{} = session, room_id, scores) do
    club = session_club(session)

    with {:ok, entries} <- parse_ballot_entries(scores),
         {:ok, actor} <- actor_for(user),
         {:ok, head_actor} <- Clubs.club_actor(club),
         {:ok, round} <- round_by_sequence(actor, session.engine_event_id, 1),
         {:ok, rooms} <- EngineApi.list_rooms(actor, round["id"]),
         {:ok, room} <- find_room(rooms, room_id),
         :ok <- authorize_ballot(room, user, club),
         {:ok, rankings, speaker_scores} <- ballot_payload(room, entries),
         {:ok, _} <- EngineApi.submit_scores(actor, room["id"], rankings, speaker_scores),
         {:ok, _} <- EngineApi.confirm_room(head_actor, room["id"]) do
      :ok
    end
  end

  @doc "Is this user the room's chair (the signed-up judge)?"
  def room_chair?(room, %User{node_user_id: node_user_id}) do
    is_integer(node_user_id) and
      Enum.any?(room["RoomAdjudicators"] || [], fn adj ->
        adj["role"] == "chair" and
          get_in(adj, ["EventParticipant", "user_id"]) == node_user_id
      end)
  end

  def room_chair?(_room, _user), do: false

  defp authorize_ballot(room, %User{} = user, club) do
    cond do
      room_chair?(room, user) -> :ok
      Clubs.role_for(club, user) == :owner -> :ok
      true -> {:error, :forbidden}
    end
  end

  defp find_room(rooms, room_id) do
    case Enum.find(rooms, &(&1["id"] == room_id)) do
      nil -> {:error, "room #{room_id} is not part of this session"}
      room -> {:ok, room}
    end
  end

  # ---------------------------------------------------------------
  # Ballot payload (ranks derive from totals; no tied team totals)
  # ---------------------------------------------------------------

  defp parse_ballot_entries(scores) when is_list(scores) do
    parsed = Enum.map(scores, &parse_ballot_entry/1)

    case Enum.find(parsed, &match?({:error, _}, &1)) do
      {:error, message} ->
        {:error, %{scores: message}}

      nil ->
        entries = Enum.map(parsed, fn {:ok, entry} -> entry end)
        counts = Enum.frequencies_by(entries, & &1.position)

        if map_size(counts) == 4 and Enum.all?(counts, fn {_pos, n} -> n == 2 end) do
          {:ok, entries}
        else
          {:error,
           %{scores: "a full ballot is 8 scores — two per team position 1..4 (og, oo, cg, co)"}}
        end
    end
  end

  defp parse_ballot_entries(_scores),
    do: {:error, %{scores: "scores must be a list of 8 entries"}}

  defp parse_ballot_entry(%{} = entry) do
    position = ballot_field(entry, :position)
    speaker = ballot_field(entry, :speaker_participant_id)
    score = ballot_field(entry, :score)

    cond do
      position not in [1, 2, 3, 4] ->
        {:error, "position must be 1..4 (og, oo, cg, co)"}

      not is_integer(speaker) ->
        {:error, "speaker_participant_id (integer) is required on every score"}

      not valid_score?(score) ->
        {:error, "score #{inspect(score)} is invalid — scores are 50-100 in 0.5 steps"}

      true ->
        {:ok,
         %{
           position: position,
           speaker_participant_id: speaker,
           iron: ballot_field(entry, :iron) == true,
           score: score / 1
         }}
    end
  end

  defp parse_ballot_entry(_entry), do: {:error, "every score must be an object"}

  defp ballot_field(entry, key) do
    case Map.fetch(entry, key) do
      {:ok, value} -> value
      :error -> Map.get(entry, to_string(key))
    end
  end

  defp valid_score?(score),
    do: is_number(score) and score >= 50 and score <= 100 and trunc(score * 2) == score * 2

  defp ballot_payload(room, entries) do
    room_teams = Enum.sort_by(room["RoomTeams"] || [], & &1["position"])
    by_position = Enum.group_by(entries, & &1.position)

    with :ok <- full_room(room_teams),
         {:ok, team_scores} <- assign_speaker_scores(room_teams, by_position) do
      totals =
        Enum.map(team_scores, fn {rt, scores} ->
          {rt, scores |> Enum.map(& &1.score) |> Enum.sum()}
        end)

      tied =
        totals
        |> Enum.frequencies_by(fn {_rt, total} -> total end)
        |> Enum.filter(fn {_total, count} -> count > 1 end)
        |> Enum.map(fn {total, _count} -> total end)

      if tied == [] do
        rankings =
          totals
          |> Enum.sort_by(fn {rt, total} -> {-total, rt["position"]} end)
          |> Enum.with_index(1)
          |> Enum.map(fn {{rt, _total}, rank} -> %{room_team_id: rt["id"], rank: rank} end)

        {:ok, rankings, Enum.flat_map(team_scores, fn {_rt, scores} -> scores end)}
      else
        {:error,
         %{
           scores:
             "two teams share the total #{Enum.map_join(tied, ", ", &format_total/1)} — " <>
               "BP forbids tied team totals, adjust the scores"
         }}
      end
    end
  end

  defp full_room(room_teams) when length(room_teams) == @teams_per_room, do: :ok
  defp full_room(_room_teams), do: {:error, "the room does not have #{@teams_per_room} teams"}

  defp assign_speaker_scores(room_teams, by_position) do
    Enum.reduce_while(room_teams, {:ok, []}, fn rt, {:ok, acc} ->
      case team_speaker_scores(rt, Map.get(by_position, rt["position"], [])) do
        {:ok, scores} -> {:cont, {:ok, acc ++ [{rt, scores}]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  # Maps a team's two entries onto its two engine room-speaker slots:
  # by participant id where possible, iron rows (same speaker twice)
  # fall onto the teammate's remaining slot.
  defp team_speaker_scores(rt, entries) do
    slots = rt["RoomSpeakers"] || []
    team_pids = Enum.map(slots, &get_in(&1, ["EventParticipant", "id"]))

    cond do
      length(slots) != length(entries) ->
        {:error,
         %{scores: "team at position #{rt["position"]} has #{length(slots)} speaker slot(s)"}}

      stranger = Enum.find(entries, &(&1.speaker_participant_id not in team_pids)) ->
        {:error,
         %{
           scores:
             "participant #{stranger.speaker_participant_id} does not speak " <>
               "at position #{rt["position"]}"
         }}

      true ->
        {scores, _free} =
          Enum.reduce(entries, {[], slots}, fn entry, {acc, free} ->
            {slot, free} = take_slot(free, entry.speaker_participant_id)
            {[%{room_speaker_id: slot["id"], score: entry.score} | acc], free}
          end)

        {:ok, Enum.reverse(scores)}
    end
  end

  defp take_slot(free, participant_id) do
    case Enum.split_with(free, &(get_in(&1, ["EventParticipant", "id"]) == participant_id)) do
      {[slot | same], others} -> {slot, same ++ others}
      {[], [slot | others]} -> {slot, others}
    end
  end

  defp format_total(total) when is_float(total) do
    if total == Float.round(total), do: "#{trunc(total)}", else: "#{total}"
  end

  defp format_total(total), do: "#{total}"

  @doc """
  Closes the session: round and event completed; results land in club
  history.
  """
  def finish(%User{} = head, %Session{} = session) do
    with {:ok, actor} <- actor_for(head),
         {:ok, round} <- round_by_sequence(actor, session.engine_event_id, 1),
         {:ok, _} <- EngineApi.update_round(actor, round["id"], %{status: "completed"}),
         {:ok, _} <-
           EngineApi.update_event(actor, session.engine_event_id, %{status: "completed"}) do
      :ok
    end
  end

  # ---------------------------------------------------------------
  # Engine composition helpers (ported from v1-mvp Cab.Tournaments)
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
  Winner of an event: the rank-1 team of its last round (club sessions
  have exactly one). Returns the team name or `nil`.
  """
  def event_winner(actor, event) do
    with {:ok, rounds} <- EngineApi.list_rounds(actor, event["id"]),
         last_round when not is_nil(last_round) <-
           Enum.max_by(rounds, & &1["sequence"], fn -> nil end),
         {:ok, rooms} <- EngineApi.list_rooms(actor, last_round["id"]) do
      rooms
      |> Enum.filter(&(&1["status"] in ["completed", "confirmed"]))
      |> Enum.flat_map(&(&1["RoomTeams"] || []))
      |> Enum.find(&(&1["rank"] == 1))
      |> case do
        nil -> nil
        winner -> get_in(winner, ["Team", "name"])
      end
    else
      _ -> nil
    end
  end

  defp session_club(%Session{} = session) do
    case session.club do
      %Club{} = club -> club
      _not_loaded -> Repo.get!(Club, session.club_id)
    end
  end

  defp actor_for(%User{} = user) do
    case Accounts.ensure_node_user(user) do
      %User{node_user_id: id} when is_integer(id) -> {:ok, id}
      _ -> {:error, "engine user could not be provisioned"}
    end
  end

  defp presence(nil), do: nil

  defp presence(string) when is_binary(string) do
    case String.trim(string) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
