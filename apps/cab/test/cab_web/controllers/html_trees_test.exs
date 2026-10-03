defmodule CabWeb.HtmlTreesTest do
  use CabWeb.ConnCase, async: true

  import Cab.Fixtures

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

  setup %{conn: conn} do
    head = user_fixture(%{node_user_id: 9})
    club = club_fixture(head, %{engine_organisation_id: 3})
    %{conn: conn, head: head, club: club}
  end

  test "public page shows profile and history", %{conn: conn, club: club} do
    stub(fn conn, _params ->
      case conn.request_path do
        "/api/events/organisation/3" ->
          ok(conn, [%{"id" => 11, "name" => "Night 1", "status" => "completed"}])

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

    html = conn |> get(~p"/c/#{club.uuid}") |> html_response(200)
    assert html =~ club.name
    assert html =~ "Night 1"
    assert html =~ "Winners"
  end

  test "owner page lists join requests; approve flips them",
       %{conn: conn, club: club, head: head} do
    user = user_fixture(%{username: "wannabe"})
    {:ok, membership} = Cab.Clubs.request_join(user, club)

    html = conn |> log_in(head) |> get(~p"/c/#{club.uuid}/owner") |> html_response(200)
    assert html =~ "wannabe"
    assert html =~ "join-request-#{membership.id}"

    conn2 =
      conn
      |> log_in(head)
      |> post(~p"/c/#{club.uuid}/owner/join-requests/#{membership.id}/approve")

    assert redirected_to(conn2) == "/c/#{club.uuid}/owner"
    assert Cab.Clubs.role_for(club, user) == :member
  end

  test "approve of another club's request is 404", %{conn: conn, head: head, club: club} do
    other_head = user_fixture()
    other_club = club_fixture(other_head)
    user = user_fixture()
    {:ok, membership} = Cab.Clubs.request_join(user, other_club)

    conn =
      conn
      |> log_in(head)
      |> post(~p"/c/#{club.uuid}/owner/join-requests/#{membership.id}/approve")

    assert response(conn, 404)
  end

  test "owner opens a session via the form", %{conn: conn, club: club, head: head} do
    stub(fn conn, params ->
      case {conn.method, conn.request_path} do
        {"POST", "/api/events/3"} ->
          ok(conn, %{"id" => 11, "name" => params["name"], "status" => "scheduled"})

        {"POST", "/api/events/11/rounds"} ->
          ok(conn, %{"id" => 21, "sequence" => 1})
      end
    end)

    conn = conn |> log_in(head) |> post(~p"/c/#{club.uuid}/owner/sessions", %{name: "Tuesday"})
    assert redirected_to(conn) == "/c/#{club.uuid}/owner"
    assert [session] = Cab.Sessions.list_for_club(club)
    assert session.engine_event_id == 11
  end

  test "member signs up via the form", %{conn: conn, club: club} do
    member = user_fixture(%{node_user_id: 44})
    membership_fixture(member, club)
    session = session_fixture(club, engine_event_id: 11)

    stub(fn conn, params ->
      assert conn.request_path == "/api/events/11/participants"
      assert params["role"] == "speaker"
      ok(conn, %{"id" => 41, "role" => "speaker"})
    end)

    conn =
      conn
      |> log_in(member)
      |> post(~p"/c/#{club.uuid}/member/sessions/#{session.uuid}/signups", %{as: "speak"})

    assert redirected_to(conn) == "/c/#{club.uuid}/member"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "signed up"
  end

  test "member page shows signup buttons while in signup stage", %{conn: conn, club: club} do
    member = user_fixture(%{node_user_id: 44})
    membership_fixture(member, club)
    session_fixture(club, engine_event_id: 11)

    stub(fn conn, _params ->
      case conn.request_path do
        "/api/events/11" -> ok(conn, %{"id" => 11, "status" => "scheduled"})
        "/api/events/11/rounds" -> ok(conn, [%{"id" => 21, "sequence" => 1}])
        "/api/events/11/participants" -> ok(conn, [])
        "/api/rounds/21/rooms" -> ok(conn, [])
      end
    end)

    html = conn |> log_in(member) |> get(~p"/c/#{club.uuid}/member") |> html_response(200)
    assert html =~ "signup-speak-form"
    assert html =~ "signup-judge-form"
    assert html =~ "stage: signup"
  end

  test "signup for another club's session is 404", %{conn: conn, club: club} do
    member = user_fixture()
    membership_fixture(member, club)
    other_club = club_fixture(user_fixture())
    other_session = session_fixture(other_club)

    conn =
      conn
      |> log_in(member)
      |> post(~p"/c/#{club.uuid}/member/sessions/#{other_session.uuid}/signups", %{as: "speak"})

    assert response(conn, 404)
  end
end
