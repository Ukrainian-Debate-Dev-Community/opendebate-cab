defmodule Cab.Standings do
  @moduledoc """
  RULE 0 — ENGINE STATISTICS ONLY. Standings are shown PER SESSION,
  verbatim as the engine returns them:

    * teams    — GET /events/:id/standings/calculated/teams
    * speakers — GET /events/:id/standings/calculated/speakers
    * judges   — plain COUNT of engine room chairs in that session
    * clubs    — plain counts (members, sessions, rooms)

  The default session is the latest FINISHED one (platform-wide for
  the global tabs, per club for the club tabs); previous sessions are
  browsed via the Sessions archive. No summing, averaging or any
  cab-side math across sessions — ever.
  """

  import Ecto.Query

  alias Cab.Clubs
  alias Cab.Clubs.Club
  alias Cab.{EngineApi, Repo, Sessions}
  alias Cab.Sessions.Session

  @tabs ~w(teams speakers judges clubs)
  # how many recent sessions the latest-finished scan may touch
  @scan_limit 25

  def tabs, do: @tabs

  @doc """
  The latest finished session, platform-wide (archived clubs
  excluded) or scoped to one club. Returns
  `%{session, club, actor, event}` or `nil` (none finished / engine
  unreachable).
  """
  def latest_finished do
    Repo.all(
      from s in Session,
        join: c in assoc(s, :club),
        where: is_nil(c.archived_at),
        order_by: [desc: s.id],
        limit: @scan_limit,
        preload: [club: c]
    )
    |> Enum.find_value(&finished_scope/1)
  end

  def latest_finished(%Club{} = club) do
    Repo.all(
      from s in Session,
        where: s.club_id == ^club.id,
        order_by: [desc: s.id],
        limit: @scan_limit
    )
    |> Enum.map(&%{&1 | club: club})
    |> Enum.find_value(&finished_scope/1)
  end

  defp finished_scope(%Session{} = session) do
    with {:ok, actor} <- Clubs.club_actor(session.club),
         {:ok, %{"status" => "completed"} = event} <-
           EngineApi.get_event(actor, session.engine_event_id) do
      %{session: session, club: session.club, actor: actor, event: event}
    else
      _ -> nil
    end
  end

  @doc """
  Engine calculated team standings for the scope's session, verbatim
  (`[%{"name" => _, "total_points" => _}, ...]` as returned).
  """
  def teams(%{actor: actor, session: session}) do
    case EngineApi.team_standings(actor, session.engine_event_id) do
      {:ok, rows} -> rows
      {:error, _message} -> []
    end
  end

  @doc "Engine calculated speaker standings for the scope's session, verbatim."
  def speakers(%{actor: actor, session: session}) do
    case EngineApi.speaker_standings(actor, session.engine_event_id) do
      {:ok, rows} -> rows
      {:error, _message} -> []
    end
  end

  @doc """
  Judges of the scope's session: a plain COUNT of engine room chairs
  — `[%{name, rooms_judged}]`, most rooms first.
  """
  def judges(%{actor: actor, session: session}) do
    with {:ok, round} <- Sessions.round_by_sequence(actor, session.engine_event_id, 1),
         {:ok, rooms} <- EngineApi.list_rooms(actor, round["id"]) do
      rooms
      |> Enum.flat_map(&(&1["RoomAdjudicators"] || []))
      |> Enum.filter(&(&1["role"] == "chair"))
      |> Enum.map(&get_in(&1, ["EventParticipant", "display_name"]))
      |> Enum.reject(&is_nil/1)
      |> Enum.frequencies()
      |> Enum.map(fn {name, count} -> %{name: name, rooms_judged: count} end)
      |> Enum.sort_by(&{-&1.rooms_judged, &1.name})
    else
      _ -> []
    end
  end

  @doc """
  The clubs tab: plain counts per live club — members (approved
  rows), sessions (gateway rows), rooms (engine rooms across the
  club's sessions; engine trouble degrades that count to 0). Most
  members first.
  """
  def clubs(clubs \\ nil) do
    clubs = clubs || Clubs.list_clubs()
    ids = Enum.map(clubs, & &1.id)
    members = Clubs.member_counts(ids)
    sessions = Sessions.session_counts(ids)

    clubs
    |> Enum.map(fn club ->
      %{
        club: club,
        members: members[club.id] || 0,
        sessions: sessions[club.id] || 0,
        rooms: room_count(club)
      }
    end)
    |> Enum.sort_by(&{-&1.members, &1.club.name})
  end

  defp room_count(%Club{} = club) do
    with sessions when sessions != [] <- Sessions.list_for_club(club),
         {:ok, actor} <- Clubs.club_actor(club) do
      Enum.reduce(sessions, 0, fn session, count ->
        with {:ok, round} <- Sessions.round_by_sequence(actor, session.engine_event_id, 1),
             {:ok, rooms} <- EngineApi.list_rooms(actor, round["id"]) do
          count + length(rooms)
        else
          _ -> count
        end
      end)
    else
      _ -> 0
    end
  end
end
