defmodule Cab.StandingsTest do
  @moduledoc """
  RULE 0 at the context level: standings are the engine's calculated
  output verbatim for ONE session, plus plain counts. WHICH session
  is shown comes from cab's own records (finished_at) — no engine
  scan.
  """

  use Cab.DataCase, async: true

  import Cab.Fixtures

  alias Cab.{Sessions, Standings}

  defp stub(fun) do
    Req.Test.stub(Core.Engine, fn conn ->
      {:ok, _body, conn} = Plug.Conn.read_body(conn)
      fun.(conn)
    end)
  end

  defp ok(conn, data), do: Req.Test.json(conn, %{"status" => "success", "data" => data})

  defp finished(club, opts) do
    session_fixture(
      club,
      Keyword.merge([finished_at: DateTime.utc_now(:second), name: "Walk night"], opts)
    )
  end

  test "latest_finished reads cab's records — no engine call" do
    head = user_fixture(%{node_user_id: 9})
    club = club_fixture(head, %{engine_organisation_id: 3})
    _open = session_fixture(club, engine_event_id: 12)
    earlier = finished(club, engine_event_id: 10, finished_at: ~U[2026-10-01 20:00:00Z])
    latest = finished(club, engine_event_id: 11, finished_at: ~U[2026-10-08 20:00:00Z])

    # any engine call would crash this stub
    stub(fn _conn -> raise "the scope must not call the engine" end)

    assert %{session: found, club: found_club} = Standings.latest_finished()
    assert found.id == latest.id
    assert found_club.id == club.id
    assert %{session: %{id: id}} = Standings.latest_finished(club)
    assert id == latest.id

    # an unfinished session is never a scope; a finished one is
    assert Standings.finished(%{session_fixture(club, engine_event_id: 13) | club: club}) == nil
    assert %{session: %{id: e}} = Standings.finished(%{earlier | club: club})
    assert e == earlier.id
  end

  test "archived and private clubs never scope the global standings" do
    head = user_fixture(%{node_user_id: 9})
    archived = club_fixture(head, %{engine_organisation_id: 3})
    finished(archived, engine_event_id: 11)
    {:ok, _} = Cab.Clubs.archive_club(archived)

    private = club_fixture(user_fixture(%{node_user_id: 10}), %{engine_organisation_id: 4})
    {:ok, private} = Cab.Clubs.update_club(private, %{"is_private" => "true"})
    finished(private, engine_event_id: 12)

    assert Standings.latest_finished() == nil
  end

  test "teams, speakers and judges are the engine's output, verbatim" do
    head = user_fixture(%{node_user_id: 9})
    club = club_fixture(head, %{engine_organisation_id: 3})
    finished(club, engine_event_id: 11)

    stub(fn conn ->
      case conn.request_path do
        "/api/events/11/standings/calculated/teams" ->
          ok(conn, [%{"id" => 1, "name" => "Anna & Bohdan", "total_points" => 3}])

        "/api/events/11/standings/calculated/speakers" ->
          ok(conn, [%{"id" => 7, "name" => "Anna Kovalenko", "total_points" => 101.53}])

        "/api/events/11/stats/judges" ->
          ok(conn, [%{"id" => 90, "name" => "Petro", "rooms_judged" => 2, "avg_feedback" => 8.5}])
      end
    end)

    scope = Standings.latest_finished()

    assert [%{"name" => "Anna & Bohdan", "total_points" => 3}] = Standings.teams(scope)
    assert [%{"name" => "Anna Kovalenko", "total_points" => 101.53}] = Standings.speakers(scope)

    assert [%{"name" => "Petro", "rooms_judged" => 2, "avg_feedback" => 8.5}] =
             Standings.judges(scope)
  end

  test "clubs rows are plain counts from cab's records; archived and private clubs absent" do
    head = user_fixture(%{node_user_id: 9})
    club = club_fixture(head, %{engine_organisation_id: 3})
    membership_fixture(user_fixture(), club)
    session_fixture(club, engine_event_id: 11, rooms_count: 2)
    session_fixture(club, engine_event_id: 12, rooms_count: 1)

    gone = club_fixture(user_fixture())
    {:ok, _} = Cab.Clubs.archive_club(gone)

    stub(fn _conn -> raise "the clubs tab must not call the engine" end)

    assert [%{club: %{id: id}, members: 2, sessions: 2, rooms: 3}] = Standings.clubs()
    assert id == club.id
  end

  test "Sessions.archive lists finished sessions with recorded winners, newest first" do
    head = user_fixture(%{node_user_id: 9})
    club = club_fixture(head, %{engine_organisation_id: 3})

    older =
      finished(club,
        engine_event_id: 10,
        name: "Old night",
        winner_name: "Old winners",
        finished_at: ~U[2026-10-01 20:00:00Z]
      )

    newer =
      finished(club,
        engine_event_id: 11,
        name: "Done night",
        winner_name: "Winners",
        finished_at: ~U[2026-10-08 20:00:00Z]
      )

    _open = session_fixture(club, engine_event_id: 12)

    stub(fn _conn -> raise "the archive must not call the engine" end)

    assert [first, second] = Sessions.archive(club)
    assert {first.session_uuid, first.name, first.winner} == {newer.uuid, "Done night", "Winners"}
    assert second.session_uuid == older.uuid
  end
end
