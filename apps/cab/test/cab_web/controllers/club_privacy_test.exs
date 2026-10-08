defmodule CabWeb.ClubPrivacyTest do
  @moduledoc """
  Private = STANDINGS ONLY: a private club never feeds the global
  standings, and its own standings are members-only — except that
  whoever played the shown session keeps that session's data.
  Everything else about the club stays public.
  """
  use CabWeb.ConnCase, async: true

  import Cab.Fixtures

  alias Cab.Clubs

  defp log_in(conn, user) do
    conn
    |> init_test_session(%{user_id: user.id})
    |> Plug.Conn.put_private(:plug_skip_csrf_protection, true)
  end

  defp stub(fun) do
    Req.Test.stub(Core.Engine, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      params = if body == "", do: %{}, else: Jason.decode!(body)
      fun.(conn, params)
    end)
  end

  defp ok(conn, data), do: Req.Test.json(conn, %{"status" => "success", "data" => data})

  defp stub_finished(participants \\ []) do
    stub(fn conn, _params ->
      case conn.request_path do
        "/api/events/organisation/3" ->
          ok(conn, [%{"id" => 11, "name" => "Quiet night", "status" => "completed"}])

        "/api/events/11/rounds" ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        "/api/rounds/21/rooms" ->
          ok(conn, [])

        "/api/events/11" ->
          ok(conn, %{"id" => 11, "name" => "Quiet night", "status" => "completed"})

        "/api/events/11/standings/calculated/speakers" ->
          ok(conn, [%{"id" => 7, "name" => "Anna", "total_points" => 101.5}])

        "/api/events/11/participants" ->
          ok(conn, participants)
      end
    end)
  end

  setup %{conn: conn} do
    head = user_fixture(%{node_user_id: 19})
    club = club_fixture(head, %{engine_organisation_id: 3})
    {:ok, club} = Clubs.update_club(club, %{"is_private" => "true"})

    session =
      session_fixture(club,
        engine_event_id: 11,
        name: "Quiet night",
        finished_at: ~U[2026-10-08 20:00:00Z]
      )

    %{conn: conn, club: club, head: head, session: session}
  end

  test "the owner toggle flips is_private", %{club: club} do
    assert club.is_private
    {:ok, club} = Clubs.update_club(club, %{"is_private" => "false"})
    refute club.is_private
  end

  test "a private club never feeds the global standings", %{club: club} do
    stub_finished()

    # the latest-finished scan skips it entirely — no engine calls needed
    assert Cab.Standings.latest_finished() == nil
    # and the clubs tab drops it from the counts
    refute Enum.any?(Cab.Standings.clubs(), &(&1.club.id == club.id))
  end

  test "club standings: anonymous walls, outsider 403, member and admin pass",
       %{conn: conn, club: club} do
    stub_finished()

    anon = get(conn, ~p"/c/#{club.uuid}/standings/speakers")
    assert redirected_to(anon) == "/signin"

    outsider = user_fixture(%{node_user_id: 44})

    denied = conn |> log_in(outsider) |> get(~p"/c/#{club.uuid}/standings/speakers")
    assert response(denied, 403)

    member = user_fixture(%{node_user_id: 45})
    membership_fixture(member, club)

    html = conn |> log_in(member) |> get(~p"/c/#{club.uuid}/standings/speakers")
    assert html_response(html, 200) =~ "Anna"

    admin =
      user_fixture(%{node_user_id: 46})
      |> Ecto.Changeset.change(is_admin: true)
      |> Cab.Repo.update!()

    assert conn
           |> log_in(admin)
           |> get(~p"/c/#{club.uuid}/standings/speakers")
           |> html_response(200) =~ "Anna"
  end

  test "a guest who played the shown session keeps that session's standings",
       %{conn: conn, club: club} do
    guest = user_fixture(%{node_user_id: 777})
    stub_finished([%{"id" => 41, "user_id" => 777, "role" => "speaker"}])

    html = conn |> log_in(guest) |> get(~p"/c/#{club.uuid}/standings/speakers")
    assert html_response(html, 200) =~ "Anna"

    # a different session's player stays out (not in this one's list)
    other = user_fixture(%{node_user_id: 778})
    denied = conn |> log_in(other) |> get(~p"/c/#{club.uuid}/standings/speakers")
    assert response(denied, 403)
  end

  test "everything else about a private club stays public", %{conn: conn, club: club} do
    stub(fn conn, _params ->
      case conn.request_path do
        "/api/events/organisation/3" -> ok(conn, [])
      end
    end)

    assert conn |> get(~p"/c/#{club.uuid}") |> html_response(200) =~ club.name
  end
end
