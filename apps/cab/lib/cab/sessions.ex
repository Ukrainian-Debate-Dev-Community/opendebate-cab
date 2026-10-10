defmodule Cab.Sessions do
  @moduledoc """
  Routine club sessions: a gateway row (public uuid) over a one-round
  engine event. Debate state (signups, rooms, ballots) lives in the
  engine and `state/1` reads it for the live pages. cab records the
  lifecycle facts it performs itself — open, rooms made, finish and
  the winner — on the row, so lists never walk the engine
  (`stage_of/1`, `club_sessions/1`, `archive/1`).
  """

  import Ecto.Query

  alias Cab.Accounts
  alias Cab.Accounts.User
  alias Cab.Clubs
  alias Cab.Clubs.Club
  alias Cab.{EngineApi, Repo}
  alias Cab.Sessions.{RoomPrep, Session}

  @teams_per_room 4
  @speakers_per_team 2
  @room_seats 9
  # the engine needs a role on every participant; signups enter as
  # speakers and Start re-roles whoever the head dragged into a chair
  @signup_role "speaker"
  # what a removed person's engine row keeps instead of their name
  @removed_name "removed"

  # ---------------------------------------------------------------
  # Rows
  # ---------------------------------------------------------------

  @doc """
  Live updates: every write that changes what a session page shows
  announces it on the session's topic; live pages re-read the state.
  """
  def subscribe(%Session{uuid: uuid}), do: Phoenix.PubSub.subscribe(Cab.PubSub, topic(uuid))

  @doc """
  Announces a change to everyone watching the session. The writer reads
  the engine state ONCE and pushes it, so a hundred open pages cost the
  engine one read instead of a hundred; pages fall back to reading it
  themselves only when that read failed.
  """
  def broadcast(%Session{uuid: uuid} = session) do
    if watched?(uuid) do
      # the first writer becomes the reader; writers arriving while it
      # reads only count themselves, and the reader reads once more for
      # all of them — twenty simultaneous ballots cost a read or two
      if :ets.update_counter(:cab_session_changes, uuid, 1, {uuid, 0}) == 1 do
        try do
          publish_until_settled(session, 1)
        rescue
          error ->
            # never leave the session stuck as "being read"
            :ets.insert(:cab_session_changes, {uuid, 0})
            reraise error, __STACKTRACE__
        end
      end
    else
      Phoenix.PubSub.broadcast(Cab.PubSub, topic(uuid), {:session_changed, uuid})
    end

    :ok
  end

  defp publish_until_settled(%Session{uuid: uuid} = session, seen) do
    message =
      with %Session{} = fresh <- get_by_uuid(uuid),
           {:ok, state} <- state(%{fresh | club: session_club(session)}) do
        {:session_state, uuid, state}
      else
        _ -> {:session_changed, uuid}
      end

    Phoenix.PubSub.broadcast(Cab.PubSub, topic(uuid), message)

    case :ets.update_counter(:cab_session_changes, uuid, -seen) do
      0 -> :ok
      pending -> publish_until_settled(session, pending)
    end
  end

  # nobody watching (API-only writes, tests) = no state read at all
  defp watched?(uuid), do: Registry.lookup(Cab.PubSub, topic(uuid)) != []

  # a drag changes only cab's draft: owner pages take the new draft,
  # nothing reads the engine
  defp broadcast_draft({:ok, %Session{uuid: uuid, draft_allocation: draft}} = result) do
    Phoenix.PubSub.broadcast(Cab.PubSub, topic(uuid), {:draft_changed, uuid, draft})
    result
  end

  defp broadcast_draft(result), do: result

  defp topic(uuid), do: "session:" <> uuid

  defp notify(result, session) do
    if result == :ok or match?({:ok, _}, result), do: broadcast(session)
    result
  end

  @doc "The session behind a short link code, with its club, or nil."
  def get_by_short_code(code) when is_binary(code) do
    Repo.one(from s in Session, where: s.short_code == ^code, preload: :club)
  end

  @doc "The session's short link, e.g. https://cab.uadebate.com/k7m2q9 (room n appended)."
  def short_url(%Session{short_code: code}, room_no \\ nil) do
    base = CabWeb.Endpoint.url() <> "/" <> code
    if room_no, do: "#{base}/#{room_no}", else: base
  end

  @doc """
  The engine id of room number `no` (rooms are numbered by creation
  order): one rooms read when the round is known, else the full state.
  """
  def room_id_by_number(%Session{room_ids: [_ | _] = ids}, no), do: Enum.at(ids, no - 1)

  def room_id_by_number(%Session{engine_round_id: round_id} = session, no)
      when is_integer(round_id) do
    with {:ok, actor} <- Clubs.club_actor(session_club(session)),
         {:ok, rooms} <- EngineApi.list_rooms(actor, round_id) do
      rooms |> Enum.map(& &1["id"]) |> Enum.sort() |> Enum.at(no - 1)
    else
      _ -> nil
    end
  end

  def room_id_by_number(%Session{} = session, no) do
    with {:ok, state} <- state(session),
         %{"id" => id} <- Enum.find(state.rooms, &(&1["no"] == no)),
         do: id,
         else: (_ -> nil)
  end

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

  @doc "Rooms made per club, as `%{club_id => count}` (cab's records)."
  def room_counts(club_ids) do
    Repo.all(
      from s in Session,
        where: s.club_id in ^club_ids,
        group_by: s.club_id,
        select: {s.club_id, sum(s.rooms_count)}
    )
    |> Map.new()
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

    with {:ok, actor} <- owner_actor(head, club),
         {:ok, event} <- EngineApi.create_event(actor, club.engine_organisation_id, name),
         {:ok, round} <- EngineApi.create_round(actor, event["id"], "Club round", 1) do
      %Session{
        club_id: club.id,
        opened_by_user_id: head.id,
        engine_event_id: event["id"],
        engine_round_id: round["id"],
        name: event["name"] || name,
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
      _ -> {:error, "Enter the date as YYYY-MM-DD."}
    end
  end

  defp parse_time(nil), do: {:ok, ~T[00:00:00]}

  defp parse_time(string) do
    case Time.from_iso8601(string <> ":00") do
      {:ok, time} -> {:ok, time}
      _ -> {:error, "Enter the time as HH:MM."}
    end
  end

  @doc """
  The head explicitly closes sign-ups (flow-2's "sign-ups close" edge):
  only possible while `:signup`; rooms are then composed from the
  final attendance. Returns `{:ok, session}` or
  `{:error, :conflict, message}` — the 409 gate.
  """
  def close_signups(%Session{} = session) do
    result =
      with {:ok, state} <- state(session) do
        case state.stage do
          :signup ->
            session
            |> Ecto.Changeset.change(signups_closed_at: DateTime.utc_now(:second))
            |> Repo.update()

          _stage ->
            {:error, :conflict, "Registration can only be closed while it is open."}
        end
      end

    notify(result, session)
  end

  @doc """
  REOPEN REGISTRATION (M9): from a running session whose rooms are
  still all pending — the rooms (and their temporary teams) are
  deleted and the public window opens again.
  """
  def reopen_registration(%User{} = head, %Session{} = session) do
    with {:ok, _count} <- delete_rooms(head, session),
         {:ok, reopened} <- reopen_signups(session) do
      {:ok, reopened}
    end
  end

  @doc """
  START SESSION (M9): one gold action — closes public registration
  and creates the rooms FROM THE ALLOCATOR STATE. Only the room
  COUNT is ever automatic; people are placed by the head's drag,
  never by cab. If room creation fails the window reopens, so the
  session stays at :signup with the error on the page.
  """
  def start(%User{} = head, %Session{} = session, rooms_spec) do
    with {:ok, closed} <- close_signups(session) do
      closed = %{closed | club: session.club}

      case make_rooms(head, closed, rooms_spec) do
        {:ok, _count} = ok ->
          ok

        error ->
          reopen_signups(closed)
          error
      end
    end
  end

  @doc """
  THE ALLOCATOR DRAFT (server-held): the head drops a person on a
  slot — `"<room>:<og|oo|cg|co>:<1|2>"` for speakers,
  `"<room>:judge"` for the chair. Registration carries no role, so
  anyone fits any slot — the drag decides who judges. The person
  leaves any previous slot; an occupied target sends its occupant to
  that previous slot (a swap) or back to the tray. Editable while
  the session is :signup or :closed. Returns `{:ok, session}`.
  """
  def place(%Session{} = session, participant_id, slot) when is_integer(participant_id) do
    session = get_by_uuid(session.uuid)

    result =
      with {:ok, state} <- state(session),
           :ok <- require_draftable(state),
           {:ok, _person} <- find_participant(state.signups, participant_id),
           {:ok, _room, _side} <- parse_slot(slot, room_count(state.signups)) do
        edit_draft(session, fn current ->
          draft = clean_draft(current, state.signups)
          from = Enum.find_value(draft, fn {key, pid} -> pid == participant_id && key end)
          occupant = draft[slot]

          draft
          |> Map.delete(from)
          |> Map.put(slot, participant_id)
          |> then(fn d ->
            if occupant && occupant != participant_id && from,
              do: Map.put(d, from, occupant),
              else: d
          end)
        end)
      end

    broadcast_draft(result)
  end

  @doc "Sends a person from the draft back to the tray."
  def unplace(%Session{} = session, participant_id) when is_integer(participant_id) do
    session = get_by_uuid(session.uuid)

    result =
      edit_draft(session, fn current ->
        current
        |> Enum.reject(fn {_key, pid} -> pid == participant_id end)
        |> Map.new()
      end)

    broadcast_draft(result)
  end

  # read-modify-write of the draft under a row lock: two owner tabs
  # dragging at the same moment must not overwrite each other
  defp edit_draft(%Session{id: id}, change) do
    Repo.transaction(fn ->
      locked = Repo.one!(from s in Session, where: s.id == ^id, lock: "FOR UPDATE")

      case save_draft(locked, change.(locked.draft_allocation || %{})) do
        {:ok, saved} -> saved
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  The draft as the allocator renders it: only people still signed
  up, only slots inside today's automatic room count.
  """
  def draft(%Session{} = session, signups), do: clean_draft(session.draft_allocation, signups)

  @doc """
  START SESSION from the server-held draft: the draft becomes the
  rooms spec for `start/3`; on success the draft is cleared.
  """
  def start_from_draft(%User{} = head, %Session{} = session) do
    from_draft(session, &start(head, &1, &2))
  end

  @doc """
  At :closed (registration already closed), the draft becomes the
  rooms exactly like `start_from_draft/2`, without touching the window.
  """
  def make_rooms_from_draft(%User{} = head, %Session{} = session) do
    from_draft(session, &make_rooms(head, &1, &2))
  end

  defp from_draft(%Session{} = session, create) do
    session = get_by_uuid(session.uuid)

    with {:ok, state} <- state(session),
         spec = draft_spec(clean_draft(session.draft_allocation, state.signups), state.signups),
         {:ok, count} <- create.(session, spec) do
      record(session, draft_allocation: %{})
      {:ok, count}
    end
  end

  defp draft_spec(draft, signups) do
    for room <- 1..room_count(signups) do
      %{
        "adjudicator_participant_id" => draft["#{room}:judge"],
        "teams" =>
          for side <- ~w(og oo cg co) do
            Enum.reject([draft["#{room}:#{side}:1"], draft["#{room}:#{side}:2"]], &is_nil/1)
          end
      }
    end
  end

  defp require_draftable(%{stage: stage}) when stage in [:signup, :closed], do: :ok

  defp require_draftable(_session),
    do: {:error, :conflict, "The rooms are fixed once the session runs."}

  defp parse_slot(slot, rooms) when is_binary(slot) do
    case String.split(slot, ":") do
      [room, "judge"] ->
        with {r, ""} when r in 1..rooms//1 <- Integer.parse(room), do: {:ok, r, "judge"}

      [room, side, n] when side in ~w(og oo cg co) and n in ["1", "2"] ->
        with {r, ""} when r in 1..rooms//1 <- Integer.parse(room), do: {:ok, r, side}

      _ ->
        :error
    end
    |> case do
      {:ok, _room, _side} = ok -> ok
      _ -> {:error, "That seat doesn't exist."}
    end
  end

  defp parse_slot(_slot, _rooms), do: {:error, "That seat doesn't exist."}

  defp clean_draft(draft, signups) do
    signed = MapSet.new(signups, & &1["id"])
    rooms = room_count(signups)

    for {key, pid} <- draft || %{},
        MapSet.member?(signed, pid),
        {room, _} <- [Integer.parse(key)],
        room in 1..rooms//1,
        into: %{} do
      {key, pid}
    end
  end

  defp save_draft(session, draft) do
    session
    |> Ecto.Changeset.change(draft_allocation: draft)
    |> Repo.update()
  end

  @doc """
  The allocator's automatic ROOM COUNT: a room seats #{@room_seats}
  people (eight speakers and a judge), so ceil(people / #{@room_seats}),
  minimum one. Registration carries no role, so the count follows
  everyone signed up; 13 speakers + 1 judge = 2 rooms. The only
  automatic part of allocation.
  """
  def room_count(signups) do
    max(div(length(signups) + @room_seats - 1, @room_seats), 1)
  end

  @doc """
  The head reopens sign-ups: only possible while `:closed` (no rooms
  yet). Returns `{:ok, session}` or `{:error, :conflict, message}`.
  """
  def reopen_signups(%Session{} = session) do
    result =
      with {:ok, state} <- state(session) do
        case state.stage do
          :closed ->
            session
            |> Ecto.Changeset.change(signups_closed_at: nil)
            |> Repo.update()

          _stage ->
            {:error, :conflict, "Registration can only reopen while it is closed."}
        end
      end

    notify(result, session)
  end

  @doc """
  Registration: the user registers themselves for this session — no
  role; the head decides who judges and who speaks at allocation.
  Only while the session is `:signup` (409 gate once sign-ups close).
  Their engine counterpart is ensured lazily; the engine enforces one
  registration per user per event.
  """
  def signup(%User{} = user, %Session{} = session) do
    display_name = presence(user.name) || user.username

    result =
      with {:ok, state} <- state(session),
           :ok <- require_stage(state, :signup),
           {:ok, actor} <- actor_for(user) do
        EngineApi.add_participant(
          actor,
          session.engine_event_id,
          display_name,
          @signup_role,
          actor
        )
      end

    notify(result, session)
  end

  @doc """
  The head seats a registered person who has not accepted yet: the
  engine participant carries their name but no user, and the engine
  returns a one-time claim token the person redeems when they accept
  (`Cab.Invitations`). Only while `:signup`. Returns the engine
  participant, `raw_claim_token` included.
  """
  def add_unclaimed(%User{} = head, %Session{} = session, display_name) do
    result =
      with {:ok, state} <- state(session),
           :ok <- require_stage(state, :signup),
           {:ok, head_actor} <- owner_actor(head, session_club(session)) do
        EngineApi.add_participant(
          head_actor,
          session.engine_event_id,
          display_name,
          @signup_role,
          nil
        )
      end

    notify(result, session)
  end

  @doc """
  A guest registers through the shared URL or is added by name: an
  engine participant with no engine account behind it, made as the
  club head. Only while `:signup`. Returns the engine participant,
  `raw_claim_token` included — the guest's link keeps both.
  """
  def add_guest(%Session{} = session, display_name) do
    club = session_club(session)

    result =
      with {:ok, state} <- state(%{session | club: club}),
           :ok <- require_stage(state, :signup),
           {:ok, head_actor} <- Clubs.club_actor(club) do
        EngineApi.add_participant(
          head_actor,
          session.engine_event_id,
          display_name,
          @signup_role,
          nil
        )
      end

    notify(result, session)
  end

  @doc """
  An invited person declines: off the waitlist their place goes like
  any removal; seated, the place stays (its scores are the session's
  record) but their name is overwritten. Runs as the club head.
  """
  def release_unclaimed(%Session{} = session, participant_id) do
    club = session_club(session)

    result =
      with {:ok, state} <- state(%{session | club: club}),
           {:ok, _participant} <- find_participant(state.signups, participant_id),
           {:ok, head_actor} <- Clubs.club_actor(club),
           {:ok, _} <-
             EngineApi.update_participant(head_actor, session.engine_event_id, participant_id, %{
               display_name: @removed_name
             }) do
        if MapSet.member?(seated_ids(state.rooms), participant_id) do
          :ok
        else
          with {:ok, _} <-
                 EngineApi.delete_participant(head_actor, session.engine_event_id, participant_id),
               do: :ok
        end
      end

    notify(result, session)
  end

  @doc """
  The head signs an approved member up on their behalf (full-control
  doctrine). The registration is made as the head (privileged engine
  callers may register other users) but carries the member's engine
  user id, so the signup is indistinguishable from a self-signup.
  """
  def signup_for(%User{} = head, %Session{} = session, username) do
    club = session_club(session)

    result =
      with {:ok, state} <- state(session),
           :ok <- require_stage(state, :signup),
           {:ok, member} <- approved_member(club, username),
           {:ok, member_actor} <- actor_for(member),
           {:ok, head_actor} <- owner_actor(head, session_club(session)) do
        display_name = presence(member.name) || member.username

        EngineApi.add_participant(
          head_actor,
          session.engine_event_id,
          display_name,
          @signup_role,
          member_actor
        )
      end

    notify(result, session)
  end

  defp approved_member(club, username) do
    with %User{} = user <- Accounts.get_user_by_username(username),
         true <- Clubs.covers?(Clubs.role_for(club, user), :member) do
      {:ok, user}
    else
      _ -> {:error, "#{username || "That person"} is not a member of this club."}
    end
  end

  @doc """
  REMOVE — the one verb for taking a person out of a session: the head
  removes anyone, a person removes themselves. Only people on the
  waitlist go: everyone before rooms exist, afterwards whoever is not
  seated in a room (a seated person's scores are the session's
  record). Removal keeps no personal data: the engine row's name is
  overwritten before the engine archives it, and a guest's cab
  account and personal link are deleted. The engine calls run as the
  club head after the gateway authorises.
  """
  def remove_signup(%User{} = user, %Session{} = session, participant_id)
      when is_integer(participant_id) do
    club = session_club(session)

    result =
      with {:ok, state} <- state(%{session | club: club}),
           {:ok, participant} <- find_participant(state.signups, participant_id),
           :ok <- authorize_remove(participant, user, club),
           :ok <- require_waitlisted(state, participant),
           {:ok, head_actor} <- Clubs.club_actor(club),
           {:ok, _} <-
             EngineApi.update_participant(head_actor, session.engine_event_id, participant_id, %{
               display_name: @removed_name
             }),
           {:ok, _} <-
             EngineApi.delete_participant(head_actor, session.engine_event_id, participant_id) do
        Cab.Links.purge_guest(participant["id"])
        Cab.Invitations.forget_participant(session, participant_id)
        :ok
      end

    notify(result, session)
  end

  @doc "Participant ids seated in a room — as a speaker or the chair."
  def seated_ids(rooms) do
    for room <- rooms,
        seat <-
          Enum.flat_map(room["RoomTeams"] || [], &(&1["RoomSpeakers"] || [])) ++
            (room["RoomAdjudicators"] || []),
        id = get_in(seat, ["EventParticipant", "id"]) || seat["participant_id"],
        is_integer(id),
        into: MapSet.new(),
        do: id
  end

  defp require_waitlisted(%{stage: :done}, _participant),
    do: {:error, :conflict, "This session is finished, so its people stay on record."}

  defp require_waitlisted(%{rooms: rooms}, participant) do
    if MapSet.member?(seated_ids(rooms), participant["id"]),
      do:
        {:error, :conflict,
         "#{participant["display_name"]} is seated in a room. Only people still waiting can be removed."},
      else: :ok
  end

  defp find_participant(participants, participant_id) do
    case Enum.find(participants, &(&1["id"] == participant_id)) do
      nil -> {:error, "That person isn't in this session."}
      participant -> {:ok, participant}
    end
  end

  defp authorize_remove(participant, %User{} = user, club) do
    cond do
      Clubs.covers?(Clubs.role_for(club, user), :owner) -> :ok
      own_participant?(participant, user) -> :ok
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
         rooms: rooms |> number_rooms() |> attach_preps(session),
         stage: stage(event, rooms, session)
       }}
    end
  end

  # rooms carry their number inside the session ("no": 1, 2, …) in
  # creation order; the engine id stays the room's address
  defp number_rooms(rooms) do
    rooms
    |> Enum.sort_by(& &1["id"])
    |> Enum.with_index(1)
    |> Enum.map(fn {room, no} -> Map.put(room, "no", no) end)
  end

  # each room's prep timer, when one runs: "prep_until", the instant prep ends
  defp attach_preps(rooms, %Session{id: id}) when is_integer(id) do
    preps =
      Repo.all(from p in RoomPrep, where: p.session_id == ^id)
      |> Map.new(&{&1.room_id, &1.ends_at})

    Enum.map(rooms, fn room ->
      case preps[room["id"]] do
        nil -> room
        ends_at -> Map.put(room, "prep_until", DateTime.to_iso8601(ends_at))
      end
    end)
  end

  defp attach_preps(rooms, _session), do: rooms

  @doc "Sets when the room's prep ends; `nil` removes the timer."
  def set_prep_until(%Session{} = session, room_id, nil) do
    from(p in RoomPrep, where: p.session_id == ^session.id and p.room_id == ^room_id)
    |> Repo.delete_all()

    notify({:ok, nil}, session)
  end

  def set_prep_until(%Session{} = session, room_id, %DateTime{} = ends_at) do
    (Repo.get_by(RoomPrep, session_id: session.id, room_id: room_id) ||
       %RoomPrep{session_id: session.id, room_id: room_id})
    |> Ecto.Changeset.change(ends_at: DateTime.truncate(ends_at, :second))
    |> Repo.insert_or_update()
    |> notify(session)
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

  defp require_stage(_session, :signup),
    do: {:error, :conflict, "Registration is not open."}

  defp require_stage(_session, :closed),
    do: {:error, :conflict, "Rooms are made after registration closes."}

  @doc """
  EXPLICIT room composition: the head says who goes where.
  `rooms_spec` is a list of
  `%{"adjudicator_participant_id" => id, "teams" => [[pid] | [pid, pid] x #{@teams_per_room}]}`
  (atom keys and integer-strings accepted) — a 1-speaker team is a
  declared iron. Only while `:closed`. People are ALWAYS placed by
  the head; cab never pairs anyone automatically. Validated
  against the signups: every pid a signed-up speaker placed at most
  once, every judge a signed-up judge chairing at most one room,
  #{@teams_per_room} teams of 1-#{@speakers_per_team} per room.
  Returns `{:ok, rooms_created}`, `{:error, :conflict, message}` or a
  changeset-style `{:error, %{rooms: message}}`.
  """
  def make_rooms(%User{} = head, %Session{} = session, rooms_spec) do
    result =
      with {:ok, state} <- state(session),
           :ok <- require_stage(state, :closed),
           {:ok, rooms} <- parse_composition(rooms_spec, state.signups),
           {:ok, actor} <- owner_actor(head, session_club(session)),
           :ok <- assign_roles(actor, session, state.signups, rooms),
           {:ok, count} <- create_composition(actor, state, rooms) do
        record(session,
          started_at: DateTime.utc_now(:second),
          rooms_count: count,
          room_ids: created_room_ids(actor, state.round)
        )

        {:ok, count}
      end

    notify(result, session)
  end

  # the drag decides roles: chairs become adjudicators, everyone in a
  # team a speaker — only rows whose engine role differs are written
  defp assign_roles(actor, session, signups, rooms) do
    wanted =
      Map.merge(
        Map.new(Enum.flat_map(rooms, &List.flatten(&1.teams)), &{&1, "speaker"}),
        Map.new(rooms, &{&1.adjudicator_participant_id, "adjudicator"})
      )

    signups
    |> Enum.filter(fn p -> wanted[p["id"]] && wanted[p["id"]] != p["role"] end)
    |> Enum.reduce_while(:ok, fn p, :ok ->
      case EngineApi.update_participant(actor, session.engine_event_id, p["id"], %{
             role: wanted[p["id"]]
           }) do
        {:ok, _} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  # one rooms read right after creating them: short links resolve room
  # numbers from the recorded ids, never asking the engine again
  defp created_room_ids(actor, %{"id" => round_id}) do
    case EngineApi.list_rooms(actor, round_id) do
      {:ok, rooms} -> rooms |> Enum.map(& &1["id"]) |> Enum.sort()
      _ -> []
    end
  end

  defp created_room_ids(_actor, _round), do: []

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

    judges = Enum.map(rooms, &by_id[&1.adjudicator_participant_id])
    create_session_rooms(actor, state.round, dedupe_names(specs), judges)
  end

  defp parse_composition(rooms_spec, participants)
       when is_list(rooms_spec) and rooms_spec != [] do
    signed_ids = MapSet.new(participants, & &1["id"])

    with {:ok, rooms} <- Enum.reduce_while(rooms_spec, {:ok, []}, &parse_room/2) do
      rooms = Enum.reverse(rooms)
      judges = Enum.map(rooms, & &1.adjudicator_participant_id)
      pids = Enum.flat_map(rooms, fn room -> List.flatten(room.teams) end)

      cond do
        Enum.any?(judges ++ pids, &(not MapSet.member?(signed_ids, &1))) ->
          {:error, %{rooms: "Someone placed in a room isn't in this session."}}

        judges ++ pids != Enum.uniq(judges ++ pids) ->
          {:error, %{rooms: "Someone is placed in two seats."}}

        true ->
          {:ok, rooms}
      end
    end
  end

  defp parse_composition(_rooms_spec, _participants),
    do: {:error, %{rooms: "Rooms must be a non-empty list of room objects."}}

  defp parse_room(%{} = room, {:ok, acc}) do
    judge = composition_int(composition_field(room, :adjudicator_participant_id))

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
        {:halt, {:error, %{rooms: "Every room needs an adjudicator."}}}

      length(teams) != @teams_per_room or
          Enum.any?(teams, fn team ->
            length(team) not in 1..@speakers_per_team or
                Enum.any?(team, &(not is_integer(&1)))
          end) ->
        {:halt,
         {:error,
          %{
            rooms:
              "Every room needs #{@teams_per_room} teams of one or two speakers " <>
                "(a one-speaker team is an iron)."
          }}}

      true ->
        {:cont, {:ok, [%{adjudicator_participant_id: judge, teams: teams} | acc]}}
    end
  end

  defp parse_room(_room, _acc),
    do: {:halt, {:error, %{rooms: "Every room must be an object."}}}

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
  # motion afterwards via set_room_motion/5. Teams go in INLINE as
  # temporary teams (the engine purges them with the room on
  # delete_rooms/2 and they never lock speakers) — the
  # delete-and-recompose loop depends on it.
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
    result =
      with {:ok, actor} <- owner_actor(head, session_club(session)),
           {:ok, round_id} <- session_round_id(actor, session),
           {:ok, rooms} <- EngineApi.list_rooms(actor, round_id) do
        cond do
          rooms == [] ->
            {:error, "This session has no rooms to delete."}

          Enum.any?(rooms, &(&1["status"] != "pending")) ->
            {:error, "Rooms can only be deleted before any ballot is in."}

          true ->
            with {:ok, count} <-
                   Enum.reduce_while(rooms, {:ok, 0}, fn room, {:ok, count} ->
                     case EngineApi.delete_room(actor, room["id"]) do
                       {:ok, _} -> {:cont, {:ok, count + 1}}
                       {:error, message} -> {:halt, {:error, message}}
                     end
                   end) do
              record(session, started_at: nil, rooms_count: 0, room_ids: [])
              {:ok, count}
            end
        end
      end

    notify(result, session)
  end

  @doc """
  Cancels the session: the engine event is archived (soft delete —
  owner-only) and the gateway row removed, so the club is back to
  "no session". Works at any stage; finished sessions should be left
  for history instead.
  """
  def cancel(%User{} = head, %Session{} = session) do
    result =
      with {:ok, actor} <- owner_actor(head, session_club(session)),
           {:ok, _} <- EngineApi.delete_event(actor, session.engine_event_id) do
        Repo.delete(session)
      end

    notify(result, session)
  end

  @doc """
  The room's judge sets that room's motion (per-room motions — rooms
  of one session may debate different ones). Chair-guarded by the
  engine, with owner/organiser fall-through for the head.
  """
  def set_room_motion(%User{} = user, %Session{} = session, room_id, motion_text, attrs \\ %{}) do
    result =
      with {:ok, actor} <- acting_for(user, session, room_id) do
        EngineApi.set_room_motion(actor, room_id, motion_text, attrs)
      end

    notify(result, session)
  end

  @doc """
  Submits a room's scored BP ballot: 8 speaker scores — two per team
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

    result =
      with {:ok, entries} <- parse_ballot_entries(scores),
           {:ok, actor} <- ballot_actor(user, club),
           {:ok, head_actor} <- Clubs.club_actor(club),
           {:ok, round_id} <- session_round_id(actor, session),
           {:ok, rooms} <- EngineApi.list_rooms(actor, round_id),
           {:ok, room} <- find_room(rooms, room_id),
           :ok <- authorize_ballot(room, user, club),
           :ok <- require_motion(room),
           {:ok, rankings, speaker_scores} <- ballot_payload(room, entries),
           {:ok, _} <- maybe_unconfirm(head_actor, room),
           {:ok, _} <- EngineApi.submit_scores(actor, room["id"], rankings, speaker_scores),
           {:ok, _} <- EngineApi.confirm_room(head_actor, room["id"]) do
        :ok
      end

    notify(result, session)
  end

  # editing a confirmed ballot: the lock/unlock dance is internal —
  # the head just edits, cab unconfirms, the resubmission atomically
  # replaces the ballot (never wiped) and it re-confirms right after
  defp maybe_unconfirm(head_actor, %{"id" => id, "status" => "confirmed"}),
    do: EngineApi.unconfirm_room(head_actor, id)

  defp maybe_unconfirm(_head_actor, _room), do: {:ok, :open}

  @doc "Has this room's motion been published? Ballots open only then."
  def motion?(room), do: is_map(room["Motion"])

  defp require_motion(room) do
    if motion?(room), do: :ok, else: {:error, "Publish the room's motion first."}
  end

  @doc "Is this user the room's chair (the signed-up judge)?"
  def room_chair?(room, %User{} = user) do
    Enum.any?(room["RoomAdjudicators"] || [], fn adj ->
      adj["role"] == "chair" and own_participant?(adj["EventParticipant"] || %{}, user)
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
      nil -> {:error, "That room is not part of this session."}
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
    do: {:error, %{scores: "Scores must be a list of 8 entries."}}

  defp parse_ballot_entry(%{} = entry) do
    position = ballot_field(entry, :position)
    speaker = ballot_field(entry, :speaker_participant_id)
    score = ballot_field(entry, :score)

    cond do
      position not in [1, 2, 3, 4] ->
        {:error, "Position must be 1 to 4 (OG, OO, CG, CO)."}

      not is_integer(speaker) ->
        {:error, "Every score needs a speaker_participant_id."}

      not valid_score?(score) ->
        {:error, "Scores are whole points from 50 to 100."}

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

  defp parse_ballot_entry(_entry), do: {:error, "Every score must be an object."}

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
             "Two teams share the total #{Enum.map_join(tied, ", ", &format_total/1)}. " <>
               "BP allows no ties, so adjust the scores."
         }}
      end
    end
  end

  defp full_room(room_teams) when length(room_teams) == @teams_per_room, do: :ok
  defp full_room(_room_teams), do: {:error, "This ballot doesn't match the room's draw."}

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
        {:error, %{scores: "This ballot doesn't match the room's draw."}}

      Enum.any?(entries, &(&1.speaker_participant_id not in team_pids)) ->
        {:error,
         %{
           scores: "This ballot doesn't match the room's draw."
         }}

      true ->
        # an iron's speech marked on the ballot stays out of the speaker
        # tab (the engine's is_iron); one per iron team, none elsewhere
        iron_team? = length(Enum.uniq(team_pids)) < length(team_pids)
        marked = if iron_team?, do: Enum.find_index(entries, & &1.iron)

        {scores, _free} =
          entries
          |> Enum.with_index()
          |> Enum.reduce({[], slots}, fn {entry, index}, {acc, free} ->
            {slot, free} = take_slot(free, entry.speaker_participant_id)
            score = %{room_speaker_id: slot["id"], score: entry.score}
            score = if index == marked, do: Map.put(score, :is_iron, true), else: score
            {[score | acc], free}
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
    result =
      with {:ok, actor} <- owner_actor(head, session_club(session)),
           {:ok, state} <- state(session),
           {:ok, _} <- EngineApi.update_round(actor, state.round["id"], %{status: "completed"}),
           {:ok, _} <-
             EngineApi.update_event(actor, session.engine_event_id, %{status: "completed"}) do
        record(session,
          finished_at: DateTime.utc_now(:second),
          winner_name: winner_from_rooms(state.rooms),
          winner_user_ids: winner_user_ids(state)
        )

        :ok
      end

    notify(result, session)
  end

  @doc """
  A guest's place claimed after the session finished: if that place
  was on a winning team, the account that claimed it is credited with
  the win (the winners were recorded when the guest had no account).
  """
  def credit_claimed_win(
        %Session{finished_at: %DateTime{}} = session,
        participant_id,
        node_user_id
      )
      when is_integer(node_user_id) do
    with {:ok, state} <- state(session),
         true <- won_by?(state.rooms, participant_id),
         false <- node_user_id in session.winner_user_ids do
      record(session, winner_user_ids: session.winner_user_ids ++ [node_user_id])
    end

    :ok
  end

  def credit_claimed_win(_session, _participant_id, _node_user_id), do: :ok

  defp won_by?(rooms, participant_id) do
    rooms
    |> Enum.filter(&(&1["status"] in ["completed", "confirmed"]))
    |> Enum.flat_map(&(&1["RoomTeams"] || []))
    |> Enum.filter(&(&1["rank"] == 1))
    |> Enum.flat_map(&(&1["RoomSpeakers"] || []))
    |> Enum.any?(&(get_in(&1, ["EventParticipant", "id"]) == participant_id))
  end

  # the winning team's members as gateway-visible engine user ids —
  # copied once at finish so history never re-walks the rooms
  defp winner_user_ids(%{rooms: rooms, signups: signups}) do
    user_of = Map.new(signups, &{&1["id"], &1["user_id"]})

    rooms
    |> Enum.filter(&(&1["status"] in ["completed", "confirmed"]))
    |> Enum.flat_map(&(&1["RoomTeams"] || []))
    |> Enum.filter(&(&1["rank"] == 1))
    |> Enum.flat_map(&(&1["RoomSpeakers"] || []))
    |> Enum.map(&user_of[get_in(&1, ["EventParticipant", "id"])])
    |> Enum.filter(&is_integer/1)
    |> Enum.uniq()
  end

  # writes a lifecycle fact onto the session row — unconditionally: the
  # struct in hand may be stale, so a changeset diff could skip it
  defp record(%Session{id: id}, changes) do
    from(s in Session, where: s.id == ^id)
    |> Repo.update_all(set: Keyword.put(changes, :updated_at, DateTime.utc_now(:second)))
  end

  @doc """
  One-off backfill for rows that predate the lifecycle columns: reads
  the engine once and records name, start, room count, finish and the
  winner. Idempotent. Returns `:ok` or `{:error, message}`.
  """
  def backfill(%Session{} = session) do
    with {:ok, state} <- state(session) do
      done? = state.event["status"] == "completed"

      record(session,
        name: state.event["name"],
        rooms_count: length(state.rooms),
        started_at:
          if(state.rooms != [], do: session.started_at || session.updated_at, else: nil),
        finished_at: if(done?, do: session.finished_at || session.updated_at, else: nil),
        winner_name: if(done?, do: winner_from_rooms(state.rooms), else: nil),
        winner_user_ids: if(done?, do: winner_user_ids(state), else: [])
      )

      :ok
    end
  end

  @doc """
  The session's stage from cab's own records — for lists and
  overviews, no engine call. Detail pages use `state/1`, which reads
  the engine and is authoritative.
  """
  def stage_of(%Session{finished_at: %DateTime{}}), do: :done
  def stage_of(%Session{started_at: %DateTime{}}), do: :running
  def stage_of(%Session{signups_closed_at: %DateTime{}}), do: :closed
  def stage_of(%Session{}), do: :signup

  @doc "The club's session that is not finished yet, or nil."
  def current_for_club(%Club{} = club) do
    Repo.one(
      from s in Session,
        where: s.club_id == ^club.id and is_nil(s.finished_at),
        order_by: [desc: s.id],
        limit: 1
    )
  end

  @doc """
  Each club's unfinished session and its stage, as
  %{club_id => {session, stage, rooms}} — cab's own records, no engine
  call; a club with no unfinished session maps to nil.
  """
  def next_by_club(clubs) do
    for club <- clubs, into: %{} do
      case current_for_club(club) do
        %Session{} = session -> {club.id, {session, stage_of(session), session.rooms_count}}
        nil -> {club.id, nil}
      end
    end
  end

  # ---------------------------------------------------------------
  # Engine helpers
  # ---------------------------------------------------------------

  def round_by_sequence(actor, event_id, sequence) do
    with {:ok, rounds} <- EngineApi.list_rounds(actor, event_id) do
      case Enum.find(rounds, &(&1["sequence"] == sequence)) do
        nil -> {:error, "Something went wrong, try again."}
        round -> {:ok, round}
      end
    end
  end

  @doc """
  Each room's winning team, in room order: `[{room, team_name}]` from
  the rank-1 team of every completed or confirmed ballot.
  """
  def winners_by_room(rooms) do
    for room <- Enum.sort_by(rooms, &(&1["no"] || &1["id"])),
        room["status"] in ["completed", "confirmed"],
        team = Enum.find(room["RoomTeams"] || [], &(&1["rank"] == 1)),
        do: {room, get_in(team, ["Team", "name"])}
  end

  @doc """
  The session's winners in one line: the team name for one room,
  "Team A (R1), Team B (R2)" for several, or `nil` while no ballot is in.
  """
  def winner_from_rooms(rooms) do
    case winners_by_room(rooms) do
      [] ->
        nil

      [{_room, name}] ->
        name

      several ->
        Enum.map_join(several, ", ", fn {room, name} ->
          "#{name} (R#{room["no"] || room["id"]})"
        end)
    end
  end

  @doc """
  The user's past participations, newest first — ONE engine call
  (`GET /users/history`, self-scoped) mapped onto cab's session rows:
  `%{date, club, club_uuid, session_uuid, role, won}`. `won` reads the
  winner recorded at finish; judges never "win". Sessions cab does
  not know (foreign events) are dropped.
  """
  def user_history(%User{node_user_id: node_user_id} = user) when is_integer(node_user_id) do
    with {:ok, actor} <- actor_for(user),
         {:ok, data} <- EngineApi.user_history(actor) do
      by_event =
        Enum.flat_map([{"adjudicator", "as_adjudicator"}, {"speaker", "as_player"}], fn {role,
                                                                                         key} ->
          for event <- data[key] || [], do: {event["id"], role}
        end)

      sessions =
        Repo.all(
          from s in Session,
            where: s.engine_event_id in ^Enum.map(by_event, &elem(&1, 0)),
            preload: :club
        )
        |> Map.new(&{&1.engine_event_id, &1})

      for {event_id, role} <- by_event, session = sessions[event_id], session != nil do
        %{
          date: session.finished_at || session.inserted_at,
          club: session.club.name,
          club_uuid: session.club.uuid,
          session_uuid: session.uuid,
          role: role,
          won: role == "speaker" and node_user_id in session.winner_user_ids
        }
      end
      |> Enum.sort_by(& &1.date, {:desc, DateTime})
    else
      _ -> []
    end
  end

  def user_history(%User{}), do: []

  @doc """
  The user's upcoming signups ACROSS CLUBS (the cabinet's schedule):
  the engine's self-scoped schedule read mapped back onto gateway
  sessions — `%{session, club, role}` rows, soonest first. Sessions
  the gateway does not know (foreign events) are dropped.
  """
  def user_schedule(%User{node_user_id: node_user_id} = user) when is_integer(node_user_id) do
    with {:ok, actor} <- actor_for(user),
         {:ok, data} <- EngineApi.user_schedule(actor) do
      by_role =
        Enum.flat_map([{"adjudicator", "as_adjudicator"}, {"speaker", "as_player"}], fn {role,
                                                                                         key} ->
          for event <- data[key] || [], do: {event["id"], role}
        end)

      sessions =
        Repo.all(
          from s in Session,
            where: s.engine_event_id in ^Enum.map(by_role, &elem(&1, 0)),
            preload: :club
        )

      by_event = Map.new(sessions, &{&1.engine_event_id, &1})

      for {event_id, role} <- by_role, session = by_event[event_id], session != nil do
        %{session: session, club: session.club, role: role}
      end
      |> Enum.sort_by(&(&1.session.scheduled_at || &1.session.inserted_at), DateTime)
    else
      _ -> []
    end
  end

  def user_schedule(%User{}), do: []

  @doc """
  The club page's "Club Sessions" table: EVERY session, newest first,
  with its status from cab's records — done (+ the winner recorded at
  finish) | live | open. Pure database, no engine call.
  """
  def club_sessions(%Club{} = club) do
    for session <- list_for_club(club) do
      %{
        session_uuid: session.uuid,
        name: session.name,
        date: session.scheduled_at || session.inserted_at,
        status:
          case stage_of(session) do
            :done -> :done
            :signup -> :open
            _ -> :live
          end,
        winner: session.winner_name
      }
    end
  end

  @doc """
  The FINISHED sessions (the standings selector), newest finish
  first, from cab's records — the winner is the engine's, copied
  verbatim at finish (rule 0).
  """
  def archive(%Club{} = club) do
    Repo.all(
      from s in Session,
        where: s.club_id == ^club.id and not is_nil(s.finished_at),
        order_by: [desc: s.finished_at]
    )
    |> Enum.map(fn session ->
      %{
        session_uuid: session.uuid,
        name: session.name,
        date: session.scheduled_at || session.inserted_at,
        winner: session.winner_name
      }
    end)
  end

  defp session_club(%Session{} = session) do
    case session.club do
      %Club{} = club -> club
      _not_loaded -> Repo.get!(Club, session.club_id)
    end
  end

  # an owner action runs in the engine as the person taking it; a
  # platform admin acting in someone else's club acts through that
  # club's head, since the engine knows only the club's own owners
  defp owner_actor(%User{} = user, %Club{} = club) do
    if Clubs.role_for(club, user) == :admin and Clubs.head_of(club) != nil and
         Clubs.head_of(club).id != user.id,
       do: Clubs.club_actor(club),
       else: actor_for(user)
  end

  @doc """
  Is this engine participant the user's own? A signed-in person by
  their engine account; a guest by the participant their personal
  link holds (a guest has no engine account).
  """
  def own_participant?(participant, %User{node_user_id: node_user_id} = user) do
    (is_integer(node_user_id) and participant["user_id"] == node_user_id) or
      participant["id"] in Cab.Links.participant_ids(user.id)
  end

  # a guest has no engine account: once cab has checked the seat, the
  # engine call runs as the club head; everyone else acts as themselves
  defp ballot_actor(%User{} = user, club) do
    if Cab.Links.guest?(user.id), do: Clubs.club_actor(club), else: actor_for(user)
  end

  # the motion: a guest must chair the room (the engine would only see
  # the head), everyone else is chair-checked by the engine itself
  defp acting_for(%User{} = user, %Session{} = session, room_id) do
    club = session_club(session)

    if Cab.Links.guest?(user.id) do
      with {:ok, state} <- state(%{session | club: club}),
           %{} = room <- Enum.find(state.rooms, &(&1["id"] == room_id)) || {:error, :forbidden},
           true <- room_chair?(room, user) || {:error, :forbidden} do
        Clubs.club_actor(club)
      end
    else
      actor_for(user)
    end
  end

  defp actor_for(%User{} = user) do
    case Accounts.ensure_node_user(user) do
      %User{node_user_id: id} when is_integer(id) -> {:ok, id}
      _ -> {:error, "Something went wrong, try again."}
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
