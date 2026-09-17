defmodule Cab.Clubs do
  @moduledoc """
  Debate clubs directory and routine club sessions (design flow
  graph 2). Clubs are gateway-owned records linked to an engine
  organisation via `engine_organisation_id`.

  A routine session (graph 2, "ROUTINE CLUB EVENTS") is a one-round
  engine event. Members register THEMSELVES per registration flow
  (graph 4, "signed in: 1 click") choosing speak or judge; rooms are
  then made from attendance — teams paired by the engine's
  auto-generate, chunked into rooms of four with signed-up judges as
  chairs. All session state lives in the engine, so any member's
  browser sees the same stage.
  """

  import Ecto.Query

  alias Cab.Clubs.Club
  alias Cab.{EngineApi, Repo, Tournaments}

  def list_clubs, do: Repo.all(from c in Club, order_by: c.name)

  def list_visible_clubs do
    Repo.all(from c in Club, where: c.visible == true, order_by: c.name)
  end

  def get_club(id), do: Repo.get(Club, id)

  def get_club!(id), do: Repo.get!(Club, id)

  def create_club(attrs) do
    %Club{}
    |> Club.changeset(attrs)
    |> Repo.insert()
  end

  def update_club(%Club{} = club, attrs) do
    club
    |> Club.changeset(attrs)
    |> Repo.update()
  end

  def delete_club(%Club{} = club), do: Repo.delete(club)

  def change_club(%Club{} = club, attrs \\ %{}), do: Club.changeset(club, attrs)

  @doc """
  Session history of a club's engine organisation: its events, each
  annotated with `"winner"` (winner of the event's last round; club
  sessions have exactly one round — no finals involved).
  """
  def club_history(actor, org_id) do
    with {:ok, events} <- EngineApi.list_organisation_events(actor, org_id) do
      {:ok, Enum.map(events, &Map.put(&1, "winner", Cab.Tournaments.event_winner(actor, &1)))}
    end
  end

  # ---------------------------------------------------------------
  # Routine sessions (graph 2) with self-registration (graph 4)
  # ---------------------------------------------------------------

  @doc """
  The engine organisation backing this club — reused when linked,
  created (with `actor` as owner) and linked on first need.
  """
  def ensure_club_org(actor, %Club{} = club) do
    case club.engine_organisation_id do
      nil ->
        with {:ok, org} <- EngineApi.create_organisation(actor, "#{club.name} (club)"),
             {:ok, _} <- update_club(club, %{engine_organisation_id: org["id"]}) do
          {:ok, org["id"]}
        end

      org_id ->
        {:ok, org_id}
    end
  end

  @doc """
  Opens a routine session: a one-round event in the club's engine
  organisation, ready for sign-ups. Motions are NOT set here — each
  room's judge sets their own room's motion once rooms are made.
  """
  def open_session(actor, %Club{} = club, name) do
    with {:ok, org_id} <- ensure_club_org(actor, club),
         {:ok, event} <- EngineApi.create_event(actor, org_id, name),
         {:ok, _round} <- EngineApi.create_round(actor, event["id"], "Club round", 1) do
      {:ok, event}
    end
  end

  @doc """
  The judge of a room sets that room's motion (per-room motions —
  rooms of one session may debate different motions). Chair-guarded
  in the engine, with owner/organiser fall-through for the host.
  """
  def set_room_motion(actor, room_id, motion_text) do
    EngineApi.set_room_motion(actor, room_id, motion_text)
  end

  @doc """
  1-click self-registration (graph 4): the signed-in member registers
  themselves for tonight, choosing "speaker" or "adjudicator". The
  engine enforces one registration per user per event.
  """
  def signup(actor, event_id, display_name, role)
      when role in ["speaker", "adjudicator"] do
    EngineApi.add_participant(actor, event_id, display_name, role, actor)
  end

  @doc """
  The club's current session — the latest not-completed event of its
  organisation — loaded with everything the page needs:
  `%{event, round, participants, rooms, stage}` where stage is
  `:signup` (no rooms yet), `:running` (rooms made, ballots open) or
  `:closing` (all rooms confirmed, session not finished yet).
  Returns `{:ok, nil}` when no session is open.
  """
  def current_session(actor, org_id) do
    with {:ok, events} <- EngineApi.list_organisation_events(actor, org_id) do
      case Enum.find(Enum.reverse(events), &(&1["status"] != "completed")) do
        nil ->
          {:ok, nil}

        event ->
          with {:ok, round} <- Tournaments.round_by_sequence(actor, event["id"], 1),
               {:ok, participants} <- EngineApi.list_participants(actor, event["id"]),
               {:ok, rooms} <- EngineApi.list_rooms(actor, round["id"]) do
            {:ok,
             %{
               event: event,
               round: round,
               participants: participants,
               rooms: rooms,
               stage: session_stage(rooms)
             }}
          end
      end
    end
  end

  def session_stage([]), do: :signup

  def session_stage(rooms) do
    if Enum.all?(rooms, &(&1["status"] == "confirmed")), do: :closing, else: :running
  end

  @teams_per_room 4

  @doc """
  Rooms by attendance (graph 2): pairs the signed-up speakers into
  teams of two via the engine's auto-generate proposal, then creates
  one room per #{@teams_per_room} teams with signed-up judges as
  chairs. Requires speakers in multiples of #{2 * @teams_per_room}
  and one judge per room.
  """
  def make_rooms(actor, event_id, round) do
    with {:ok, participants} <- EngineApi.list_participants(actor, event_id) do
      speakers = Enum.filter(participants, &(&1["role"] == "speaker"))
      judges = Enum.filter(participants, &(&1["role"] == "adjudicator"))
      room_count = div(length(speakers), 2 * @teams_per_room)

      cond do
        speakers == [] or rem(length(speakers), 2 * @teams_per_room) != 0 ->
          {:error,
           "need speakers in multiples of #{2 * @teams_per_room} to fill rooms " <>
             "(have #{length(speakers)} signed up)"}

        length(judges) < room_count ->
          {:error, "need at least #{room_count} judge(s) (have #{length(judges)})"}

        true ->
          with {:ok, team_ids} <- create_attendance_teams(actor, event_id),
               {:ok, count} <- create_session_rooms(actor, round, team_ids, judges) do
            {:ok, count}
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
  Records a room's winner: winner-pick ballot, submitted and locked.
  """
  def pick_winner(actor, room, winner_room_team_id) do
    with {:ok, rankings, scores} <- Tournaments.winner_ballot_payload(room, winner_room_team_id),
         {:ok, _} <- EngineApi.submit_scores(actor, room["id"], rankings, scores),
         {:ok, _} <- EngineApi.confirm_room(actor, room["id"]) do
      :ok
    end
  end

  @doc """
  Closes the session once every room is confirmed: round and event
  completed, results land in club history.
  """
  def finish_session(actor, event_id, round) do
    with {:ok, _} <- EngineApi.update_round(actor, round["id"], %{status: "completed"}),
         {:ok, _} <- EngineApi.update_event(actor, event_id, %{status: "completed"}) do
      :ok
    end
  end
end
