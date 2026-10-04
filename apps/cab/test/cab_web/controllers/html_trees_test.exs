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

    # assembled from the kit: chrome + sections of table/cards
    assert html =~ ~s(class="chrome")
    assert html =~ ~s(class="section")
    assert html =~ ~s(class="t" id="club-history")
    assert html =~ ~s(class="stage ok")

    # anonymous: quiet Sign in + the gold conversion routes to sign-in
    assert html =~ "Sign in"
    assert html =~ "Request to join"
    assert html =~ ~s(class="go")
    refute html =~ "Member area"
  end

  test "public page as a member swaps the join segment for the member area",
       %{conn: conn, club: club, head: head} do
    stub(fn conn, _params ->
      case conn.request_path do
        "/api/events/organisation/3" -> ok(conn, [])
      end
    end)

    html = conn |> log_in(head) |> get(~p"/c/#{club.uuid}") |> html_response(200)
    assert html =~ "Member area"
    assert html =~ "Owner area"
    refute html =~ "Request to join"
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

    # the two sign-up actions are chrome segments; the speak one is gold
    assert html =~ "I speak tonight"
    assert html =~ "I judge"
    assert html =~ "signups?as=speak"
    assert html =~ "signups?as=judge"
    assert html =~ ~s(data-method="post")
    assert html =~ ~s(class="stage ok")
    assert html =~ "sign-up open"

    # member templates never reference owner segments
    refute html =~ "Make rooms"
    refute html =~ "Open session"
    refute html =~ "Finish session"
    refute html =~ "/owner"
  end

  test "owner page shows role-scoped chrome segments and the session form",
       %{conn: conn, club: club, head: head} do
    html = conn |> log_in(head) |> get(~p"/c/#{club.uuid}/owner") |> html_response(200)

    # no session yet: the gold segment and the form both open one
    assert html =~ "Open session"
    assert html =~ ~s(class="go")
    assert html =~ ~s(id="open-session-form")
    assert html =~ ~s(class="form")
    assert html =~ ~s(id="members-list")
    assert html =~ ~s(id="join-requests")
    refute html =~ "Make rooms"
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
