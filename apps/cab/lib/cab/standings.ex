defmodule Cab.Standings do
  @moduledoc """
  RULE 0 — ENGINE STATISTICS ONLY. Standings are shown PER SESSION,
  verbatim as the engine returns them:

    * teams    — GET /events/:id/standings/calculated/teams
    * speakers — GET /events/:id/standings/calculated/speakers
    * judges   — GET /events/:id/stats/judges
    * clubs    — plain counts from cab's records (members, sessions,
                 rooms)

  Which session is shown comes from cab's records (finished_at) — one
  engine call per tab, the standings themselves. No cab-side math.
  """

  import Ecto.Query

  alias Cab.Clubs
  alias Cab.Clubs.Club
  alias Cab.{EngineApi, Repo, Sessions}
  alias Cab.Sessions.Session

  @tabs ~w(teams speakers judges clubs)

  def tabs, do: @tabs

  @doc """
  The latest finished session, platform-wide (archived and private
  clubs excluded) or scoped to one club — straight from cab's records.
  Returns `%{session, club, actor}` or `nil` (none finished).
  """
  def latest_finished do
    Repo.one(
      from s in Session,
        join: c in assoc(s, :club),
        where: not is_nil(s.finished_at) and is_nil(c.archived_at) and not c.is_private,
        order_by: [desc: s.finished_at],
        limit: 1,
        preload: [club: c]
    )
    |> scope()
  end

  def latest_finished(%Club{} = club) do
    Repo.one(
      from s in Session,
        where: s.club_id == ^club.id and not is_nil(s.finished_at),
        order_by: [desc: s.finished_at],
        limit: 1
    )
    |> then(&(&1 && %{&1 | club: club}))
    |> scope()
  end

  @doc """
  The scope for ONE chosen session (the club standings selector) —
  same shape as `latest_finished/1`, nil unless that session finished.
  """
  def finished(%Session{} = session), do: scope(session)

  defp scope(%Session{finished_at: %DateTime{}} = session) do
    case Clubs.club_actor(session.club) do
      {:ok, actor} -> %{session: session, club: session.club, actor: actor}
      _ -> nil
    end
  end

  defp scope(_session), do: nil

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
  Judges of the scope's session — the ENGINE's judge stats verbatim
  (`GET /events/:id/stats/judges`): `[{id, name, rooms_judged,
  avg_feedback}]`, rule 0.
  """
  def judges(%{actor: actor, session: session}) do
    case EngineApi.judge_stats(actor, session.engine_event_id) do
      {:ok, rows} -> rows
      {:error, _message} -> []
    end
  end

  @doc """
  The clubs tab: plain counts per public club from cab's records —
  members, sessions and rooms made. Most members first.
  """
  def clubs do
    clubs = Enum.reject(Clubs.list_clubs(), & &1.is_private)
    ids = Enum.map(clubs, & &1.id)
    members = Clubs.member_counts(ids)
    sessions = Sessions.session_counts(ids)
    rooms = Sessions.room_counts(ids)

    clubs
    |> Enum.map(fn club ->
      %{
        club: club,
        members: members[club.id] || 0,
        sessions: sessions[club.id] || 0,
        rooms: rooms[club.id] || 0
      }
    end)
    |> Enum.sort_by(&{-&1.members, &1.club.name})
  end
end
