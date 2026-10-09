defmodule CabWeb.ClubScopeTest do
  use CabWeb.ConnCase, async: true

  import Cab.Fixtures

  setup %{conn: conn} do
    head = user_fixture(%{node_user_id: 9})
    club = club_fixture(head)
    %{conn: conn, head: head, club: club}
  end

  defp log_in(conn, user), do: init_test_session(conn, %{user_id: user.id})

  defp stub_empty_history do
    Req.Test.stub(Core.Engine, fn conn ->
      Req.Test.json(conn, %{"status" => "success", "data" => []})
    end)
  end

  describe "HTML role trees" do
    test "public tree renders for everyone", %{conn: conn, club: club} do
      stub_empty_history()
      conn = get(conn, ~p"/c/#{club.uuid}")
      assert html_response(conn, 200) =~ club.name
    end

    test "unknown club is 404", %{conn: conn} do
      assert get(conn, ~p"/c/#{Ecto.UUID.generate()}") |> response(404)
      assert get(conn, "/c/not-a-uuid") |> response(404)
    end

    test "roster of a public club is public", %{conn: conn, club: club} do
      assert get(conn, ~p"/c/#{club.uuid}/members") |> html_response(200) =~ "Members"

      assert conn
             |> log_in(user_fixture())
             |> get(~p"/c/#{club.uuid}/members")
             |> html_response(200)
    end

    test "roster of a private club: /signin for anonymous, 403 for pending, 200 for approved",
         %{conn: conn, club: club} do
      {:ok, club} = Cab.Clubs.update_club(club, %{"is_private" => "true"})

      # the anonymous auth wall lands on P1
      assert get(conn, ~p"/c/#{club.uuid}/members") |> redirected_to() == "/signin"

      pending = user_fixture()
      membership_fixture(pending, club, status: "pending")

      assert conn
             |> log_in(pending)
             |> get(~p"/c/#{club.uuid}/members")
             |> response(403)

      member = user_fixture()
      membership_fixture(member, club)

      assert conn
             |> log_in(member)
             |> get(~p"/c/#{club.uuid}/members")
             |> html_response(200) =~ "Members"
    end

    test "owner tree: 403 for a plain member, 200 for the head",
         %{conn: conn, club: club, head: head} do
      member = user_fixture()
      membership_fixture(member, club)

      assert conn |> log_in(member) |> get(~p"/c/#{club.uuid}/owner") |> response(403)

      assert conn |> log_in(head) |> get(~p"/c/#{club.uuid}/owner") |> html_response(200) =~
               "Club profile"
    end

    test "head covers the member tree too", %{conn: conn, club: club, head: head} do
      assert conn
             |> log_in(head)
             |> get(~p"/c/#{club.uuid}/members")
             |> html_response(200)
    end
  end

  describe "JSON role derivation" do
    test "members endpoint of a public club is public", %{conn: conn, club: club} do
      assert %{"members" => [_]} =
               conn |> get(~p"/api/v1/clubs/#{club.uuid}/members") |> json_response(200)
    end

    test "members endpoint of a private club: 401 anonymous, 403 stranger, 200 member",
         %{conn: conn, club: club} do
      {:ok, club} = Cab.Clubs.update_club(club, %{"is_private" => "true"})

      conn0 = get(conn, ~p"/api/v1/clubs/#{club.uuid}/members")
      assert json_response(conn0, 401)["error"] == "unauthenticated"

      stranger = user_fixture()
      conn1 = conn |> log_in(stranger) |> get(~p"/api/v1/clubs/#{club.uuid}/members")
      assert json_response(conn1, 403)["error"] == "forbidden"

      member = user_fixture()
      membership_fixture(member, club)
      conn2 = conn |> log_in(member) |> get(~p"/api/v1/clubs/#{club.uuid}/members")
      assert %{"members" => [_, _]} = json_response(conn2, 200)
    end

    test "owner-only endpoints are 403 for members", %{conn: conn, club: club} do
      member = user_fixture()
      membership_fixture(member, club)

      conn = conn |> log_in(member) |> post(~p"/api/v1/clubs/#{club.uuid}/sessions", %{})
      assert json_response(conn, 403)["error"] == "forbidden"
    end

    test "unknown club uuid is 404 JSON", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/clubs/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)["error"] == "not found"
    end

    test "room routes resolve the club from session_uuid and 404 without it",
         %{conn: conn, club: club} do
      member = user_fixture()
      membership_fixture(member, club)
      session = session_fixture(club)

      # missing session_uuid -> cannot resolve a club -> 404
      conn0 = conn |> log_in(member) |> post(~p"/api/v1/rooms/71/motion", %{motion_text: "THW"})
      assert json_response(conn0, 404)["error"] == "not found"

      # stranger with a valid session_uuid -> 403
      stranger = user_fixture()

      conn1 =
        conn
        |> log_in(stranger)
        |> post(~p"/api/v1/rooms/71/motion", %{
          session_uuid: session.uuid,
          motion_text: "THW"
        })

      assert json_response(conn1, 403)["error"] == "forbidden"
    end
  end
end
