defmodule Cab.Sessions do
  @moduledoc """
  Routine club sessions: a gateway row (public uuid) over a one-round
  engine event. All debate state lives in the engine — the gateway
  never duplicates it; `state/1` derives the stage from engine data
  on every read.

  Engine-call sequences (teams pairing, winner ballot, finishing) are
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
  Records a room's winner: an ordered synthetic ballot (winner's
  speakers 76, everyone else a flat 75; ranks winner-first then table
  order), submitted and confirmed (ported from v1-mvp winner-pick).

  The ballot is submitted as the acting user — the engine's chair
  guard (with owner fall-through) applies. Confirming is
  owner/organiser-only in the frozen engine, so the gateway confirms
  as the club head after its own role check.
  """
  def pick_winner(%User{} = user, %Session{} = session, room_id, winner_room_team_id) do
    club = session_club(session)

    with {:ok, actor} <- actor_for(user),
         {:ok, head_actor} <- Clubs.club_actor(club),
         {:ok, round} <- round_by_sequence(actor, session.engine_event_id, 1),
         {:ok, rooms} <- EngineApi.list_rooms(actor, round["id"]),
         {:ok, room} <- find_room(rooms, room_id),
         {:ok, rankings, scores} <- winner_ballot(room, winner_room_team_id),
         {:ok, _} <- EngineApi.submit_scores(actor, room["id"], rankings, scores),
         {:ok, _} <- EngineApi.confirm_room(head_actor, room["id"]) do
      :ok
    end
  end

  defp find_room(rooms, room_id) do
    case Enum.find(rooms, &(&1["id"] == room_id)) do
      nil -> {:error, "room #{room_id} is not part of this session"}
      room -> {:ok, room}
    end
  end

  defp winner_ballot(room, winner_room_team_id) do
    room_teams = Enum.sort_by(room["RoomTeams"] || [], & &1["position"])

    if Enum.any?(room_teams, &(&1["id"] == winner_room_team_id)) do
      scores =
        Enum.flat_map(room_teams, fn rt ->
          score = if rt["id"] == winner_room_team_id, do: 76, else: 75
          Enum.map(rt["RoomSpeakers"] || [], &%{room_speaker_id: &1["id"], score: score})
        end)

      rankings =
        room_teams
        |> Enum.sort_by(&{if(&1["id"] == winner_room_team_id, do: 0, else: 1), &1["position"]})
        |> Enum.with_index(1)
        |> Enum.map(fn {rt, rank} -> %{room_team_id: rt["id"], rank: rank} end)

      {:ok, rankings, scores}
    else
      {:error, "that team is not in this room"}
    end
  end

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
