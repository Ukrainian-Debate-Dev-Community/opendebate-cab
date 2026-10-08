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
  @min_room_speakers 4
  @max_room_speakers 8

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

  @doc "Session counts for the given club ids, as `%{club_id => count}` (front-page directory)."
  def session_counts(club_ids) do
    Repo.all(
      from s in Session,
        where: s.club_id in ^club_ids,
        group_by: s.club_id,
        select: {s.club_id, count(s.id)}
    )
    |> Map.new()
  end

  # ---------------------------------------------------------------
  # Lifecycle
  # ---------------------------------------------------------------

  @doc """
  Opens a session: a one-round event in the club's engine organisation,
  ready for sign-ups, plus the gateway row. Motions are NOT set here —
  each room's judge sets their own room's motion once rooms are made.
  `scheduled_at` is the optional planned start (UTC) — see
  `parse_schedule/2` for the form's date/time pair.
  """
  def open(%User{} = head, %Club{} = club, name, scheduled_at \\ nil) do
    name = presence(name) || "Club session #{Date.utc_today()}"

    with {:ok, actor} <- actor_for(head),
         {:ok, event} <- EngineApi.create_event(actor, club.engine_organisation_id, name),
         {:ok, round} <- EngineApi.create_round(actor, event["id"], "Club round", 1) do
      %Session{
        club_id: club.id,
        opened_by_user_id: head.id,
        engine_event_id: event["id"],
        engine_round_id: round["id"],
        scheduled_at: scheduled_at
      }
      |> Session.changeset()
      |> Repo.insert()
    end
  end

  @doc """
  Parses the open-session form's optional date ("YYYY-MM-DD") and time
  ("HH:MM") into a `scheduled_at` UTC datetime. No date -> `{:ok, nil}`
  (a time alone is ignored); malformed input -> `{:error, message}`.
  """
  def parse_schedule(date, time) do
    case presence(date) do
      nil ->
        {:ok, nil}

      date_string ->
        with {:ok, date} <- parse_date(date_string),
             {:ok, time} <- parse_time(presence(time)) do
          DateTime.new(date, time, "Etc/UTC")
        end
    end
  end

  defp parse_date(string) do
    case Date.from_iso8601(string) do
      {:ok, date} -> {:ok, date}
      _ -> {:error, "date must be YYYY-MM-DD"}
    end
  end

  defp parse_time(nil), do: {:ok, ~T[00:00:00]}

  defp parse_time(string) do
    case Time.from_iso8601(string <> ":00") do
      {:ok, time} -> {:ok, time}
      _ -> {:error, "time must be HH:MM"}
    end
  end

  @doc """
  The head explicitly closes sign-ups (flow-2's "sign-ups close" edge):
  only possible while `:signup`; rooms are then composed from the
  final attendance. Returns `{:ok, session}` or
  `{:error, :conflict, message}` — the 409 gate.
  """
  def close_signups(%Session{} = session) do
    with {:ok, state} <- state(session) do
      case state.stage do
        :signup ->
          session
          |> Ecto.Changeset.change(signups_closed_at: DateTime.utc_now(:second))
          |> Repo.update()

        stage ->
          {:error, :conflict, "sign-ups can only be closed while open (session is #{stage})"}
      end
    end
  end

  @doc """
  The head reopens sign-ups: only possible while `:closed` (no rooms
  yet). Returns `{:ok, session}` or `{:error, :conflict, message}`.
  """
  def reopen_signups(%Session{} = session) do
    with {:ok, state} <- state(session) do
      case state.stage do
        :closed ->
          session
          |> Ecto.Changeset.change(signups_closed_at: nil)
          |> Repo.update()

        stage ->
          {:error, :conflict, "sign-ups can only reopen while closed (session is #{stage})"}
      end
    end
  end

  @doc """
  Registration: the member registers themselves for this session as
  "speak" or "judge" — only while the session is `:signup` (409 gate
  once sign-ups close). Their engine counterpart is ensured lazily;
  the engine enforces one registration per user per event.
  """
  def signup(%User{} = user, %Session{} = session, kind) when kind in ["speak", "judge"] do
    role = if kind == "speak", do: "speaker", else: "adjudicator"
    display_name = presence(user.name) || user.username

    with {:ok, state} <- state(session),
         :ok <- require_stage(state, :signup),
         {:ok, actor} <- actor_for(user) do
      EngineApi.add_participant(actor, session.engine_event_id, display_name, role, actor)
    end
  end

  @doc """
  The head signs an approved member up on their behalf (full-control
  doctrine). The registration is made as the head (privileged engine
  callers may register other users) but carries the member's engine
  user id, so the signup is indistinguishable from a self-signup.
  """
  def signup_for(%User{} = head, %Session{} = session, username, kind)
      when kind in ["speak", "judge"] do
    role = if kind == "speak", do: "speaker", else: "adjudicator"
    club = session_club(session)

    with {:ok, state} <- state(session),
         :ok <- require_stage(state, :signup),
         {:ok, member} <- approved_member(club, username),
         {:ok, member_actor} <- actor_for(member),
         {:ok, head_actor} <- actor_for(head) do
      display_name = presence(member.name) || member.username

      EngineApi.add_participant(
        head_actor,
        session.engine_event_id,
        display_name,
        role,
        member_actor
      )
    end
  end

  def signup_for(%User{}, %Session{}, _username, _kind),
    do: {:error, ~s(sign up "as" must be "speak" or "judge")}

  defp approved_member(club, username) do
    with %User{} = user <- Accounts.get_user_by_username(username),
         role when role in [:member, :owner] <- Clubs.role_for(club, user) do
      {:ok, user}
    else
      _ -> {:error, "#{username || "?"} is not an approved member of this club"}
    end
  end

  @doc """
  Removes a signup: the head removes anyone, a member removes their
  own. The engine call runs as the club head (participant deletion is
  owner/organiser-only in the engine) after the gateway authorises.
  The engine refuses (409) once the participant has been paired into
  a team — removal is a sign-up-stage operation.
  """
  def remove_signup(%User{} = user, %Session{} = session, participant_id)
      when is_integer(participant_id) do
    club = session_club(session)

    with {:ok, head_actor} <- Clubs.club_actor(club),
         {:ok, participants} <- EngineApi.list_participants(head_actor, session.engine_event_id),
         {:ok, participant} <- find_participant(participants, participant_id),
         :ok <- authorize_remove(participant, user, club),
         {:ok, _} <-
           EngineApi.delete_participant(head_actor, session.engine_event_id, participant_id) do
      :ok
    end
  end

  defp find_participant(participants, participant_id) do
    case Enum.find(participants, &(&1["id"] == participant_id)) do
      nil -> {:error, "participant #{participant_id} is not signed up for this session"}
      participant -> {:ok, participant}
    end
  end

  defp authorize_remove(participant, %User{} = user, club) do
    cond do
      Clubs.covers?(Clubs.role_for(club, user), :owner) -> :ok
      is_integer(user.node_user_id) and participant["user_id"] == user.node_user_id -> :ok
      true -> {:error, :forbidden}
    end
  end

  @doc """
  The session as the pages and the JSON API see it, composed from
  engine state plus the gateway's registration window:
  `%{event, round, signups, rooms, stage}` where stage is `:signup`
  (no rooms, sign-ups open), `:closed` (no rooms, sign-ups closed),
  `:running` (rooms made) or `:done` (event completed). Reads run as
  the club head's node user.
  """
  def state(%Session{} = session) do
    club = session_club(session)

    with {:ok, actor} <- Clubs.club_actor(club),
         [event_r, round_r, signups_r, rooms_r] <- state_reads(actor, session),
         {:ok, event} <- event_r,
         {:ok, round} <- round_r,
         {:ok, signups} <- signups_r,
         {:ok, rooms} <- rooms_r do
      {:ok,
       %{
         event: event,
         round: round,
         signups: signups,
         rooms: rooms,
         stage: stage(event, rooms, session)
       }}
    end
  end

  # the four engine reads are independent once the round id is known
  # (stamped at open) — fan them out instead of paying their sum
  defp state_reads(actor, %Session{engine_round_id: round_id} = session)
       when is_integer(round_id) do
    fan_out([
      fn -> EngineApi.get_event(actor, session.engine_event_id) end,
      fn -> round_by_sequence(actor, session.engine_event_id, 1) end,
      fn -> EngineApi.list_participants(actor, session.engine_event_id) end,
      fn -> EngineApi.list_rooms(actor, round_id) end
    ])
  end

  # legacy row without the stamp: the rooms read waits for the round
  defp state_reads(actor, %Session{} = session) do
    [event_r, round_r, signups_r] =
      fan_out([
        fn -> EngineApi.get_event(actor, session.engine_event_id) end,
        fn -> round_by_sequence(actor, session.engine_event_id, 1) end,
        fn -> EngineApi.list_participants(actor, session.engine_event_id) end
      ])

    rooms_r = with {:ok, round} <- round_r, do: EngineApi.list_rooms(actor, round["id"])
    [event_r, round_r, signups_r, rooms_r]
  end

  defp fan_out(funs) do
    funs
    |> Task.async_stream(& &1.(), timeout: 30_000, ordered: true)
    |> Enum.map(fn {:ok, result} -> result end)
  end

  # most flows only need the round's id — the stamp answers without
  # an engine call; legacy rows fall back to the lookup
  defp session_round_id(_actor, %Session{engine_round_id: id}) when is_integer(id), do: {:ok, id}

  defp session_round_id(actor, %Session{} = session) do
    with {:ok, round} <- round_by_sequence(actor, session.engine_event_id, 1),
         do: {:ok, round["id"]}
  end

  defp stage(%{"status" => "completed"}, _rooms, _session), do: :done
  defp stage(_event, [], %Session{signups_closed_at: nil}), do: :signup
  defp stage(_event, [], %Session{}), do: :closed
  defp stage(_event, _rooms, _session), do: :running

  # the lifecycle gates: sign-ups while :signup, composition while
  # :closed — anything else is a 409 for the API, a flash for HTML
  defp require_stage(%{stage: stage}, stage), do: :ok

  defp require_stage(%{stage: actual}, :signup),
    do: {:error, :conflict, "sign-ups are not open (session is #{actual})"}

  defp require_stage(%{stage: actual}, :closed),
    do: {:error, :conflict, "rooms are composed after sign-ups close (session is #{actual})"}

  @doc """
  The pairing PROPOSAL the head sees before making rooms: the
  engine's auto-pair order re-chunked into iron-capable rooms,
  computed WITHOUT side effects (nothing is persisted). Available
  while `state.stage == :closed` (rooms are composed from the final
  attendance) with at least #{@min_room_speakers} speakers and a
  judge; `:unavailable` otherwise.

  Returns `{:ok, rooms}` where each room is
  `%{judge_participant_id: id, teams: [[pid] | [pid, pid] x #{@teams_per_room}]}`
  — pairs first, singles (declared irons) last.
  """
  def pairing_proposal(%Session{} = session, %{stage: :closed} = state) do
    case auto_composition(session, state) do
      {:ok, rooms} -> {:ok, rooms}
      {:error, _message} -> :unavailable
    end
  end

  def pairing_proposal(%Session{}, _state), do: :unavailable

  @doc """
  The auto-pair composition (nothing persisted): the engine's random
  speaking order chunked into `room_count` rooms (default
  `floor(speakers / #{@max_room_speakers})`, min 1) of
  #{@teams_per_room} teams each. Teams hold 1-#{@speakers_per_team}
  speakers — a 1-speaker team is a declared iron — so a room holds
  #{@min_room_speakers}-#{@max_room_speakers} speakers; pairs come
  first, singles last. Speakers beyond the rooms' capacity stay
  unallocated (the head composes explicitly to choose who sits out).
  """
  def auto_composition(%Session{} = session, %{signups: signups}, room_count \\ nil) do
    speakers = Enum.filter(signups, &(&1["role"] == "speaker"))
    judges = Enum.filter(signups, &(&1["role"] == "adjudicator"))
    attendance = length(speakers)
    rooms = room_count || max(div(attendance, @max_room_speakers), 1)

    cond do
      attendance < @min_room_speakers ->
        {:error,
         "rooms need #{@min_room_speakers}-#{@max_room_speakers} speakers " <>
           "(have #{attendance} signed up)"}

      rooms > div(attendance, @min_room_speakers) ->
        {:error,
         "#{rooms} room(s) need at least #{rooms * @min_room_speakers} speakers " <>
           "(have #{attendance})"}

      length(judges) < rooms ->
        {:error, "need at least #{rooms} judge(s) (have #{length(judges)})"}

      true ->
        with {:ok, order} <- speaking_order(session, speakers) do
          {:ok,
           order
           |> Enum.take(min(attendance, rooms * @max_room_speakers))
           |> chunk_rooms(rooms)
           |> Enum.zip(judges)
           |> Enum.map(fn {teams, judge} ->
             %{judge_participant_id: judge["id"], teams: teams}
           end)}
        end
    end
  end

  # the engine's auto-generate proposal flattened to a random speaking
  # order (free-speaker aware); signups it skipped go last
  defp speaking_order(session, speakers) do
    with {:ok, actor} <- Clubs.club_actor(session_club(session)),
         {:ok, %{"proposed_teams" => proposals}} <-
           EngineApi.propose_teams(actor, session.engine_event_id) do
      signed = MapSet.new(speakers, & &1["id"])

      proposed =
        proposals
        |> Enum.flat_map(& &1["participant_ids"])
        |> Enum.filter(&MapSet.member?(signed, &1))

      {:ok, proposed ++ (Enum.map(speakers, & &1["id"]) -- proposed)}
    end
  end

  # spreads the placed speakers evenly over the rooms, then cuts each
  # room into 4 teams: pairs first, singles (irons) last
  defp chunk_rooms(placed, rooms) do
    base = div(length(placed), rooms)
    extra = rem(length(placed), rooms)

    {chunks, _rest} =
      Enum.map_reduce(0..(rooms - 1), placed, fn index, rest ->
        size = base + if(index < extra, do: 1, else: 0)
        {room, rest} = Enum.split(rest, size)
        {room_teams(room), rest}
      end)

    chunks
  end

  defp room_teams(room_speakers) do
    pairs = length(room_speakers) - @teams_per_room
    {paired, singles} = Enum.split(room_speakers, pairs * @speakers_per_team)
    Enum.chunk_every(paired, @speakers_per_team) ++ Enum.map(singles, &[&1])
  end

  @doc """
  Rooms by attendance, the gold one-click path: the auto composition
  (`auto_composition/3`) created for real — only while `:closed` (the
  graph gate: sign-ups close -> rooms by attendance), 409-style
  `{:error, :conflict, message}` otherwise. Returns `{:ok, rooms_created}`.

  Teams go in INLINE as temporary teams (the engine purges them with
  the room on `delete_rooms/2` and they never lock speakers), which
  is what makes the delete-and-recompose loop possible.
  """
  def make_rooms(%User{} = head, %Session{} = session) do
    with {:ok, state} <- state(session),
         :ok <- require_stage(state, :closed),
         {:ok, rooms} <- auto_composition(session, state),
         {:ok, actor} <- actor_for(head) do
      create_composition(actor, state, rooms)
    end
  end

  @doc """
  EXPLICIT room composition: the head says who goes where.
  `rooms_spec` is a list of
  `%{"judge_participant_id" => id, "teams" => [[pid] | [pid, pid] x #{@teams_per_room}]}`
  (atom keys and integer-strings accepted) — a 1-speaker team is a
  declared iron. Only while `:closed`, like `make_rooms/2`. Validated
  against the signups: every pid a signed-up speaker placed at most
  once, every judge a signed-up judge chairing at most one room,
  #{@teams_per_room} teams of 1-#{@speakers_per_team} per room.
  Returns `{:ok, rooms_created}`, `{:error, :conflict, message}` or a
  changeset-style `{:error, %{rooms: message}}`.
  """
  def make_rooms(%User{} = head, %Session{} = session, rooms_spec) do
    with {:ok, state} <- state(session),
         :ok <- require_stage(state, :closed),
         {:ok, rooms} <- parse_composition(rooms_spec, state.signups),
         {:ok, actor} <- actor_for(head) do
      create_composition(actor, state, rooms)
    end
  end

  defp create_composition(actor, state, rooms) do
    by_id = Map.new(state.signups, &{&1["id"], &1})

    specs =
      rooms
      |> Enum.flat_map(& &1.teams)
      |> Enum.map(fn pids ->
        %{
          name: Enum.map_join(pids, " & ", &first_name(by_id[&1]["display_name"])),
          participant_ids: pids
        }
      end)

    judges = Enum.map(rooms, &by_id[&1.judge_participant_id])
    create_session_rooms(actor, state.round, dedupe_names(specs), judges)
  end

  defp parse_composition(rooms_spec, participants)
       when is_list(rooms_spec) and rooms_spec != [] do
    speaker_ids = for p <- participants, p["role"] == "speaker", into: MapSet.new(), do: p["id"]

    judge_ids =
      for p <- participants, p["role"] == "adjudicator", into: MapSet.new(), do: p["id"]

    with {:ok, rooms} <- Enum.reduce_while(rooms_spec, {:ok, []}, &parse_room/2) do
      rooms = Enum.reverse(rooms)
      judges = Enum.map(rooms, & &1.judge_participant_id)
      pids = Enum.flat_map(rooms, fn room -> List.flatten(room.teams) end)

      cond do
        bad = Enum.find(judges, &(not MapSet.member?(judge_ids, &1))) ->
          {:error, %{rooms: "participant #{bad} is not a signed-up judge"}}

        judges != Enum.uniq(judges) ->
          {:error, %{rooms: "a judge cannot chair two rooms"}}

        bad = Enum.find(pids, &(not MapSet.member?(speaker_ids, &1))) ->
          {:error, %{rooms: "participant #{bad} is not a signed-up speaker"}}

        pids != Enum.uniq(pids) ->
          [dup | _] = pids -- Enum.uniq(pids)
          {:error, %{rooms: "participant #{dup} is placed more than once"}}

        true ->
          {:ok, rooms}
      end
    end
  end

  defp parse_composition(_rooms_spec, _participants),
    do: {:error, %{rooms: "rooms must be a non-empty list of room objects"}}

  defp parse_room(%{} = room, {:ok, acc}) do
    judge = composition_int(composition_field(room, :judge_participant_id))

    teams =
      room
      |> composition_field(:teams)
      |> List.wrap()
      |> Enum.map(fn
        team when is_list(team) -> Enum.map(team, &composition_int/1)
        _other -> [nil]
      end)

    cond do
      not is_integer(judge) ->
        {:halt, {:error, %{rooms: "every room needs a judge_participant_id"}}}

      length(teams) != @teams_per_room or
          Enum.any?(teams, fn team ->
            length(team) not in 1..@speakers_per_team or
                Enum.any?(team, &(not is_integer(&1)))
          end) ->
        {:halt,
         {:error,
          %{
            rooms:
              "every room needs #{@teams_per_room} teams of " <>
                "1-#{@speakers_per_team} speaker participant ids " <>
                "(a 1-speaker team is an iron)"
          }}}

      true ->
        {:cont, {:ok, [%{judge_participant_id: judge, teams: teams} | acc]}}
    end
  end

  defp parse_room(_room, _acc),
    do: {:halt, {:error, %{rooms: "every room must be an object"}}}

  defp composition_field(room, key) do
    case Map.fetch(room, key) do
      {:ok, value} -> value
      :error -> Map.get(room, to_string(key))
    end
  end

  defp composition_int(value) when is_integer(value), do: value

  defp composition_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp composition_int(_value), do: nil

  defp first_name(nil), do: "?"
  defp first_name(display_name), do: display_name |> String.split() |> hd()

  # team names are unique per engine event — suffix repeats
  defp dedupe_names(specs) do
    {specs, _seen} =
      Enum.map_reduce(specs, %{}, fn spec, seen ->
        count = Map.get(seen, spec.name, 0)
        name = if count == 0, do: spec.name, else: "#{spec.name} #{count + 1}"
        {%{spec | name: name}, Map.put(seen, spec.name, count + 1)}
      end)

    specs
  end

  # Rooms are created motion-less: each room's judge sets their own
  # motion afterwards via set_room_motion/3. Teams are inline
  # temporary teams — see make_rooms/2.
  defp create_session_rooms(actor, round, team_specs, judges) do
    team_specs
    |> Enum.chunk_every(@teams_per_room)
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, 0}, fn {chunk, index}, {:ok, count} ->
      slots =
        chunk
        |> Enum.with_index(1)
        |> Enum.map(fn {spec, position} -> Map.put(spec, :position, position) end)

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
  Deletes the session's rooms so the head can recompose: only
  possible while every room is still `pending` (the engine refuses
  judging/completed/confirmed rooms); the inline temporary teams go
  with their rooms, freeing the speakers for the next pairing.
  Returns `{:ok, rooms_deleted}`.
  """
  def delete_rooms(%User{} = head, %Session{} = session) do
    with {:ok, actor} <- actor_for(head),
         {:ok, round_id} <- session_round_id(actor, session),
         {:ok, rooms} <- EngineApi.list_rooms(actor, round_id) do
      cond do
        rooms == [] ->
          {:error, "this session has no rooms to delete"}

        Enum.any?(rooms, &(&1["status"] != "pending")) ->
          {:error, "only pending rooms can be deleted — this session is already in play"}

        true ->
          Enum.reduce_while(rooms, {:ok, 0}, fn room, {:ok, count} ->
            case EngineApi.delete_room(actor, room["id"]) do
              {:ok, _} -> {:cont, {:ok, count + 1}}
              {:error, message} -> {:halt, {:error, message}}
            end
          end)
      end
    end
  end

  @doc """
  Cancels the session: the engine event is archived (soft delete —
  owner-only) and the gateway row removed, so the club is back to
  "no session". Works at any stage; finished sessions should be left
  for history instead.
  """
  def cancel(%User{} = head, %Session{} = session) do
    with {:ok, actor} <- actor_for(head),
         {:ok, _} <- EngineApi.delete_event(actor, session.engine_event_id) do
      Repo.delete(session)
    end
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
  scores are whole points, 50-100.

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
         {:ok, round_id} <- session_round_id(actor, session),
         {:ok, rooms} <- EngineApi.list_rooms(actor, round_id),
         {:ok, room} <- find_room(rooms, room_id),
         :ok <- authorize_ballot(room, user, club),
         {:ok, rankings, speaker_scores} <- ballot_payload(room, entries),
         {:ok, _} <- maybe_unconfirm(head_actor, room),
         {:ok, _} <- EngineApi.submit_scores(actor, room["id"], rankings, speaker_scores),
         {:ok, _} <- EngineApi.confirm_room(head_actor, room["id"]) do
      :ok
    end
  end

  # editing a confirmed ballot: the lock/unlock dance is internal —
  # the head just edits, cab unconfirms, the resubmission atomically
  # replaces the ballot (never wiped) and it re-confirms right after
  defp maybe_unconfirm(head_actor, %{"id" => id, "status" => "confirmed"}),
    do: EngineApi.unconfirm_room(head_actor, id)

  defp maybe_unconfirm(_head_actor, _room), do: {:ok, :open}

  @doc "Is this user the room's chair (the signed-up judge)?"
  def room_chair?(room, %User{node_user_id: node_user_id}) do
    is_integer(node_user_id) and
      Enum.any?(room["RoomAdjudicators"] || [], fn adj ->
        adj["role"] == "chair" and
          get_in(adj, ["EventParticipant", "user_id"]) == node_user_id
      end)
  end

  def room_chair?(_room, _user), do: false

  # a confirmed ballot is the head's to edit; otherwise chair or head
  defp authorize_ballot(%{"status" => "confirmed"}, %User{} = user, club) do
    if Clubs.covers?(Clubs.role_for(club, user), :owner),
      do: :ok,
      else: {:error, :forbidden}
  end

  defp authorize_ballot(room, %User{} = user, club) do
    cond do
      room_chair?(room, user) -> :ok
      Clubs.covers?(Clubs.role_for(club, user), :owner) -> :ok
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
        {:error, "score #{inspect(score)} is invalid — scores are whole points, 50-100"}

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

  # whole points only — the engine stores scores as integers
  defp valid_score?(score),
    do: is_number(score) and score >= 50 and score <= 100 and trunc(score) == score

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
         {:ok, round_id} <- session_round_id(actor, session),
         {:ok, _} <- EngineApi.update_round(actor, round_id, %{status: "completed"}),
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
      winner_from_rooms(rooms)
    else
      _ -> nil
    end
  end

  @doc """
  The winning team's name from a session's rooms: the rank-1 team of
  a confirmed (or completed) ballot, or `nil` while none exists.
  """
  def winner_from_rooms(rooms) do
    rooms
    |> Enum.filter(&(&1["status"] in ["completed", "confirmed"]))
    |> Enum.flat_map(&(&1["RoomTeams"] || []))
    |> Enum.find(&(&1["rank"] == 1))
    |> case do
      nil -> nil
      winner -> get_in(winner, ["Team", "name"])
    end
  end

  @doc """
  The user's past participations across their approved clubs, newest
  first: for every finished session of such a club where the user's
  engine counterpart took part, `%{date, club, role, won}` — `date`
  is the gateway session's `inserted_at`, `role` is "speaker" or
  "judge", and `won` is true when their team took rank 1 of the
  confirmed ballot (always false for judges).
  """
  def user_history(%User{node_user_id: node_user_id} = user) when is_integer(node_user_id) do
    user
    |> Clubs.list_user_memberships()
    |> Enum.filter(&(&1.status == "approved"))
    |> Enum.flat_map(&club_user_history(&1.club, user))
    |> Enum.sort_by(& &1.date, {:desc, DateTime})
  end

  # no engine counterpart yet -> never participated
  def user_history(%User{}), do: []

  @doc """
  The user's past participations in ONE club (the P5 "my results"
  rows), newest first — same shape as `user_history/1`.
  """
  def user_club_history(%Club{} = club, %User{node_user_id: node_user_id} = user)
      when is_integer(node_user_id) do
    club
    |> club_user_history(user)
    |> Enum.sort_by(& &1.date, {:desc, DateTime})
  end

  def user_club_history(%Club{}, %User{}), do: []

  @doc """
  The sessions ARCHIVE (previous progress): the club's FINISHED
  engine events as rows `%{session_uuid, name, date, winner}`, newest
  first — every value an engine fact, verbatim (rule 0: the winner is
  the rank-1 team of the confirmed ballot, never computed cab-side).
  Engine trouble degrades to an empty list — the page stays up.
  """
  def archive(%Club{} = club) do
    with sessions when sessions != [] <- list_for_club(club),
         {:ok, actor} <- Clubs.club_actor(club),
         {:ok, events} <-
           EngineApi.list_organisation_events(actor, club.engine_organisation_id) do
      names = Map.new(events, &{&1["id"], &1["name"]})

      completed =
        for event <- events, event["status"] == "completed", into: MapSet.new() do
          event["id"]
        end

      sessions
      |> Enum.filter(&MapSet.member?(completed, &1.engine_event_id))
      |> Enum.map(fn session ->
        %{
          session_uuid: session.uuid,
          name: names[session.engine_event_id],
          date: session.scheduled_at || session.inserted_at,
          winner: event_winner(actor, %{"id" => session.engine_event_id})
        }
      end)
    else
      _ -> []
    end
  end

  defp club_user_history(%Club{} = club, user) do
    case list_for_club(club) do
      [] ->
        []

      sessions ->
        with {:ok, actor} <- Clubs.club_actor(club),
             {:ok, events} <-
               EngineApi.list_organisation_events(actor, club.engine_organisation_id) do
          completed =
            for event <- events, event["status"] == "completed", into: MapSet.new() do
              event["id"]
            end

          sessions
          |> Enum.filter(&MapSet.member?(completed, &1.engine_event_id))
          |> Enum.map(&participation(actor, club, &1, user))
          |> Enum.reject(&is_nil/1)
        else
          _ -> []
        end
    end
  end

  defp participation(actor, club, session, user) do
    with {:ok, participants} <- EngineApi.list_participants(actor, session.engine_event_id),
         %{} = me <- Enum.find(participants, &(&1["user_id"] == user.node_user_id)) do
      %{
        date: session.inserted_at,
        club: club.name,
        club_uuid: club.uuid,
        session_uuid: session.uuid,
        role: if(me["role"] == "adjudicator", do: "judge", else: "speaker"),
        won: me["role"] != "adjudicator" and won?(actor, session, me)
      }
    else
      _ -> nil
    end
  end

  # did this participant's team take rank 1 of a confirmed ballot?
  defp won?(actor, session, me) do
    with {:ok, round_id} <- session_round_id(actor, session),
         {:ok, rooms} <- EngineApi.list_rooms(actor, round_id) do
      rooms
      |> Enum.filter(&(&1["status"] in ["completed", "confirmed"]))
      |> Enum.flat_map(&(&1["RoomTeams"] || []))
      |> Enum.any?(fn room_team ->
        room_team["rank"] == 1 and
          Enum.any?(
            room_team["RoomSpeakers"] || [],
            &(get_in(&1, ["EventParticipant", "id"]) == me["id"])
          )
      end)
    else
      _ -> false
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
