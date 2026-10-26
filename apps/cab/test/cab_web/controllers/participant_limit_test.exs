defmodule CabWeb.ParticipantLimitTest do
  @moduledoc """
  The participant limit on the pages: places left and "full" in the
  club page's registration section, the register action refused, the
  Club Sessions table and the clubs directory, and the head's forms.
  """

  use CabWeb.ConnCase, async: true

  import Cab.Fixtures

  alias Cab.Repo
  alias Cab.Sessions.Session

  setup %{conn: conn} do
    head = user_fixture(%{node_user_id: 9})
    club = club_fixture(head, %{engine_organisation_id: 3})
    %{conn: conn, head: head, club: club}
  end

  defp log_in(conn, user) do
    conn
    |> init_test_session(%{user_id: user.id})
    |> Plug.Conn.put_private(:plug_skip_csrf_protection, true)
  end

  defp anon(conn), do: Plug.Conn.put_private(conn, :plug_skip_csrf_protection, true)

  defp ok(conn, data), do: Req.Test.json(conn, %{"status" => "success", "data" => data})

  # event 11 with `count` people signed up; a sign-up the test did not
  # expect fails it
  defp engine(count) do
    signups = for i <- 1..count//1, do: %{"id" => i, "display_name" => "P#{i}"}

    Req.Test.stub(Core.Engine, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/events/11"} -> ok(conn, %{"id" => 11, "status" => "scheduled"})
        {"GET", "/api/events/11/rounds"} -> ok(conn, [%{"id" => 21, "sequence" => 1}])
        {"GET", "/api/events/11/participants"} -> ok(conn, signups)
        {"GET", "/api/rounds/21/rooms"} -> ok(conn, [])
      end
    end)
  end

  defp guest(session),
    do: %{
      "session" => session.uuid,
      "name" => "Greta Guest",
      "answers" => %{"email" => "greta@example.com"}
    }

  describe "the club page" do
    test "shows the places left above the form", %{conn: conn, club: club} do
      session_fixture(club, max_participants: 10, signups_count: 7)
      engine(7)

      html = conn |> get(~p"/c/#{club.uuid}") |> html_response(200)

      assert html =~ "3 places left"
      assert html =~ ~s(id="guest-register-form")
    end

    test "no limit, no count", %{conn: conn, club: club} do
      session_fixture(club, signups_count: 7)
      engine(7)

      html = conn |> get(~p"/c/#{club.uuid}") |> html_response(200)

      refute html =~ "places left"
      assert html =~ "registration open"
    end

    test "a full session says so instead of the form", %{conn: conn, club: club} do
      member = user_fixture(%{node_user_id: 44})
      membership_fixture(member, club)
      session_fixture(club, max_participants: 2, signups_count: 2)
      engine(2)

      for conn <- [conn, log_in(conn, member)] do
        html = conn |> get(~p"/c/#{club.uuid}") |> html_response(200)

        assert html =~ "Registration is full."
        refute html =~ ~s(id="guest-register-form")
        refute html =~ ~s(id="register-form")
        # the Club Sessions table
        assert html =~ "registration full"
        refute html =~ "registration open"
      end
    end

    test "the register action refuses past the limit", %{conn: conn, club: club} do
      # cab's record is behind: the engine's count, read under the lock, decides
      session = session_fixture(club, max_participants: 2, signups_count: 1)
      engine(2)

      conn = conn |> anon() |> post(~p"/c/#{club.uuid}/register", guest(session))

      assert redirected_to(conn) == "/c/#{club.uuid}"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Registration is full."
      assert Repo.all(Cab.Links.Link) == []
      assert Repo.get!(Session, session.id).signups_count == 2
    end
  end

  test "the clubs directory shows a full session", %{conn: conn, club: club} do
    session_fixture(club, max_participants: 2, signups_count: 2)

    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ "registration full"
    refute html =~ "#register"
  end

  describe "the head" do
    test "sets and clears the limit on the session page", %{conn: conn, head: head, club: club} do
      session = session_fixture(club)
      engine(4)
      conn = log_in(conn, head)

      page = conn |> get(~p"/c/#{club.uuid}/owner/s/#{session.uuid}") |> html_response(200)
      assert page =~ ~s(id="participant-limit-form")

      saved =
        post(conn, ~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/limit", %{
          "max_participants" => "12"
        })

      assert Phoenix.Flash.get(saved.assigns.flash, :info) == "Participant limit saved."
      assert %{max_participants: 12, signups_count: 4} = Repo.get!(Session, session.id)

      refused =
        post(conn, ~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/limit", %{
          "max_participants" => "0"
        })

      assert Phoenix.Flash.get(refused.assigns.flash, :error) =~ "whole number above zero"
      assert Repo.get!(Session, session.id).max_participants == 12

      post(conn, ~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/limit", %{
        "max_participants" => ""
      })

      assert Repo.get!(Session, session.id).max_participants == nil
    end

    test "the open-session form refuses a bad limit before the engine",
         %{conn: conn, head: head, club: club} do
      html = conn |> log_in(head) |> get(~p"/c/#{club.uuid}/owner") |> html_response(200)
      assert html =~ ~s(name="max_participants")

      conn =
        conn
        |> log_in(head)
        |> post(~p"/c/#{club.uuid}/owner/sessions", %{
          "name" => "Night",
          "max_participants" => "x"
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "whole number above zero"
      assert Repo.all(Session) == []
    end
  end
end
