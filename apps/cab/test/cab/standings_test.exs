defmodule Cab.StandingsTest do
  @moduledoc """
  RULE 0 at the context level: standings are the engine's calculated
  output verbatim for ONE session, plus plain counts — no cab-side
  math, ever.
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

  defp stub_finished(opts \\ []) do
    teams = Keyword.get(opts, :teams, [])
    speakers = Keyword.get(opts, :speakers, [])
    rooms = Keyword.get(opts, :rooms, [])
    judges = Keyword.get(opts, :judges, [])

    stub(fn conn ->
      case conn.request_path do
        "/api/events/11" ->
          ok(conn, %{"id" => 11, "name" => "Walk night", "status" => "completed"})

        "/api/events/11/standings/calculated/teams" ->
          ok(conn, teams)

        "/api/events/11/standings/calculated/speakers" ->
          ok(conn, speakers)

        "/api/events/11/rounds" ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        "/api/rounds/21/rooms" ->
          ok(conn, rooms)

        "/api/events/11/stats/judges" ->
          ok(conn, judges)

        "/api/events/organisation/3" ->
          ok(conn, [%{"id" => 11, "name" => "Walk night", "status" => "completed"}])
      end
    end)
  end

  test "latest_finished picks the newest completed session; none -> nil" do
    head = user_fixture(%{node_user_id: 9})
    club = club_fixture(head, %{engine_organisation_id: 3})
    session = session_fixture(club, engine_event_id: 11)

    stub_finished()

    assert %{session: found, club: found_club, event: event} = Standings.latest_finished()
    assert found.id == session.id
    assert found_club.id == club.id
    assert event["status"] == "completed"

    assert %{session: scoped} = Standings.latest_finished(club)
    assert scoped.id == session.id

    # a still-running session is never the standings scope
    stub(fn conn ->
      case conn.request_path do
        "/api/events/11" -> ok(conn, %{"id" => 11, "status" => "scheduled"})
      end
    end)

    assert Standings.latest_finished() == nil
    assert Standings.latest_finished(club) == nil
  end

  test "an archived club's sessions never scope the global standings" do
    head = user_fixture(%{node_user_id: 9})
    club = club_fixture(head, %{engine_organisation_id: 3})
    session_fixture(club, engine_event_id: 11)
    {:ok, _} = Cab.Clubs.archive_club(club)

    stub_finished()

    assert Standings.latest_finished() == nil
  end

  test "teams and speakers are the engine's calculated standings, verbatim" do
    head = user_fixture(%{node_user_id: 9})
    club = club_fixture(head, %{engine_organisation_id: 3})
    session_fixture(club, engine_event_id: 11)

    stub_finished(
      teams: [%{"id" => 1, "name" => "Anna & Bohdan", "total_points" => 3}],
      speakers: [%{"id" => 7, "name" => "Anna Kovalenko", "total_points" => 101.53}]
    )

    scope = Standings.latest_finished()

    assert [%{"name" => "Anna & Bohdan", "total_points" => 3}] = Standings.teams(scope)

    assert [%{"name" => "Anna Kovalenko", "total_points" => 101.53}] =
             Standings.speakers(scope)
  end

  test "judges are the engine's judge stats, verbatim" do
    head = user_fixture(%{node_user_id: 9})
    club = club_fixture(head, %{engine_organisation_id: 3})
    session_fixture(club, engine_event_id: 11)

    stub_finished(
      judges: [
        %{"id" => 90, "name" => "Petro", "rooms_judged" => 2, "avg_feedback" => 8.5},
        %{"id" => 91, "name" => "Nadia", "rooms_judged" => 1, "avg_feedback" => nil}
      ]
    )

    scope = Standings.latest_finished()

    assert [
             %{"name" => "Petro", "rooms_judged" => 2, "avg_feedback" => 8.5},
             %{"name" => "Nadia", "rooms_judged" => 1, "avg_feedback" => nil}
           ] = Standings.judges(scope)
  end

  test "clubs rows are plain counts; archived clubs are absent" do
    head = user_fixture(%{node_user_id: 9})
    club = club_fixture(head, %{engine_organisation_id: 3})
    membership_fixture(user_fixture(), club)
    session_fixture(club, engine_event_id: 11)

    gone = club_fixture(user_fixture())
    {:ok, _} = Cab.Clubs.archive_club(gone)

    stub_finished(rooms: [%{"id" => 71, "RoomAdjudicators" => []}])

    rows = Standings.clubs()
    assert [%{club: %{id: id}, members: 2, sessions: 1, rooms: 1}] = rows
    assert id == club.id
  end

  test "Sessions.archive lists finished sessions with engine winners, newest first" do
    head = user_fixture(%{node_user_id: 9})
    club = club_fixture(head, %{engine_organisation_id: 3})
    done = session_fixture(club, engine_event_id: 11)
    _open = session_fixture(club, engine_event_id: 12)

    stub(fn conn ->
      case conn.request_path do
        "/api/events/organisation/3" ->
          ok(conn, [
            %{"id" => 11, "name" => "Done night", "status" => "completed"},
            %{"id" => 12, "name" => "Tonight", "status" => "scheduled"}
          ])

        "/api/events/11/rounds" ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        "/api/rounds/21/rooms" ->
          ok(conn, [
            %{
              "id" => 71,
              "status" => "confirmed",
              "RoomTeams" => [%{"id" => 1, "rank" => 1, "Team" => %{"name" => "Winners"}}]
            }
          ])
      end
    end)

    assert [row] = Sessions.archive(club)
    assert row.session_uuid == done.uuid
    assert row.name == "Done night"
    assert row.winner == "Winners"
  end
end
