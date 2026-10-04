defmodule CabWeb.CabinetHomeTest do
  @moduledoc "P2 (anonymous front page) and P3 (signed-in cabinet) on GET /."

  use CabWeb.ConnCase, async: true

  import Cab.Fixtures

  defp log_in(conn, user) do
    conn
    |> init_test_session(%{user_id: user.id})
    |> Plug.Conn.put_private(:plug_skip_csrf_protection, true)
  end

  test "P2: anonymous front page carries the pitch and the clubs directory", %{conn: conn} do
    head = user_fixture()

    club =
      club_fixture(head, %{
        name: "Kyiv Debate Club #{System.unique_integer([:positive])}",
        city: "Kyiv"
      })

    session_fixture(club, engine_event_id: 11)

    html = conn |> get(~p"/") |> html_response(200)

    # chrome: the sign-in CTA routes to P1, never to a provider
    assert html =~ ~s(class="chrome")
    assert html =~ "Sign in"
    assert html =~ ~s(href="/signin")
    refute html =~ "/auth/github"

    # the one-line pitch banner
    assert html =~ ~s(class="banner info")
    assert html =~ "free for every Ukrainian club"

    # directory: name, city, member count, session count, open -> P4
    assert html =~ ~s(id="clubs-directory")
    assert html =~ "Kyiv Debate Club"
    assert html =~ "Kyiv"
    assert html =~ ~s(href="/c/#{club.uuid}")
    assert html =~ ~r/class="num">\s*1\s*</

    refute html =~ "My clubs"
    refute html =~ "Sign out"
  end

  test "P3: signed-in cabinet lists my clubs with tonight state and role links", %{conn: conn} do
    user = user_fixture(%{username: "anna"})
    head = user_fixture()

    club =
      club_fixture(head, %{
        name: "Kyiv Debate Club #{System.unique_integer([:positive])}",
        city: "Kyiv"
      })

    membership_fixture(user, club)

    my_club =
      club_fixture(user, %{name: "Lviv Debate Society #{System.unique_integer([:positive])}"})

    pending_club =
      club_fixture(user_fixture(), %{name: "Odesa Debates #{System.unique_integer([:positive])}"})

    {:ok, _} = Cab.Clubs.request_join(user, pending_club)

    html = conn |> log_in(user) |> get(~p"/") |> html_response(200)

    # account segments
    assert html =~ ~s(class="me")
    assert html =~ "anna"
    assert html =~ "Sign out"

    # my clubs: tonight column + per-role links (P5 member, P8 head)
    assert html =~ ~s(id="my-clubs")
    assert html =~ "Kyiv Debate Club"
    assert html =~ "no session"
    assert html =~ "my club page"
    assert html =~ ~s(href="/c/#{club.uuid}/member")
    assert html =~ "Lviv Debate Society"
    assert html =~ "owner console"
    assert html =~ ~s(href="/c/#{my_club.uuid}/owner")

    # pending request: tagged, linking only to the public page
    assert html =~ "Odesa Debates"
    assert html =~ "request pending"
    assert html =~ ~s(href="/c/#{pending_club.uuid}")
    refute html =~ ~s(href="/c/#{pending_club.uuid}/member")

    # my sessions: no participations yet -> the table's empty state
    assert html =~ ~s(id="my-sessions")
    assert html =~ "Past sessions will appear here."
  end

  test "P3: tonight banner and sign-ups-open tag when a club has an open session",
       %{conn: conn} do
    head = user_fixture(%{node_user_id: 339})
    user = user_fixture(%{username: "bo", node_user_id: 344})

    club =
      club_fixture(head, %{
        name: "Kyiv Debate Club #{System.unique_integer([:positive])}",
        engine_organisation_id: 3
      })

    membership_fixture(user, club)
    session_fixture(club, engine_event_id: 11)

    Req.Test.stub(Core.Engine, fn req ->
      case req.request_path do
        "/api/events/organisation/3" ->
          Req.Test.json(req, %{"status" => "success", "data" => []})

        "/api/events/11" ->
          Req.Test.json(req, %{
            "status" => "success",
            "data" => %{"id" => 11, "status" => "scheduled"}
          })

        "/api/events/11/participants" ->
          Req.Test.json(req, %{"status" => "success", "data" => []})

        "/api/events/11/rounds" ->
          Req.Test.json(req, %{
            "status" => "success",
            "data" => [%{"id" => 21, "sequence" => 1}]
          })

        "/api/rounds/21/rooms" ->
          Req.Test.json(req, %{"status" => "success", "data" => []})
      end
    end)

    html = conn |> log_in(user) |> get(~p"/") |> html_response(200)

    assert html =~ "a session is open"
    assert html =~ "Register →"
    assert html =~ ~s(href="/c/#{club.uuid}/member")
    assert html =~ "sign-ups open"
  end

  test "P3: my sessions lists past participations, rows linking to P6", %{conn: conn} do
    head = user_fixture(%{node_user_id: 339})
    user = user_fixture(%{username: "bo", node_user_id: 344})

    club =
      club_fixture(head, %{
        name: "Kyiv Debate Club #{System.unique_integer([:positive])}",
        engine_organisation_id: 3
      })

    membership_fixture(user, club)
    session = session_fixture(club, engine_event_id: 11)

    Req.Test.stub(Core.Engine, fn req ->
      case req.request_path do
        "/api/events/organisation/3" ->
          Req.Test.json(req, %{
            "status" => "success",
            "data" => [%{"id" => 11, "name" => "Night 1", "status" => "completed"}]
          })

        # the tonight column peeks at the latest session's stage
        "/api/events/11" ->
          Req.Test.json(req, %{
            "status" => "success",
            "data" => %{"id" => 11, "status" => "completed"}
          })

        "/api/events/11/participants" ->
          Req.Test.json(req, %{
            "status" => "success",
            "data" => [%{"id" => 41, "user_id" => 344, "role" => "speaker"}]
          })

        "/api/events/11/rounds" ->
          Req.Test.json(req, %{
            "status" => "success",
            "data" => [%{"id" => 21, "sequence" => 1}]
          })

        "/api/rounds/21/rooms" ->
          Req.Test.json(req, %{
            "status" => "success",
            "data" => [
              %{
                "id" => 71,
                "status" => "confirmed",
                "RoomTeams" => [
                  %{
                    "id" => 101,
                    "rank" => 1,
                    "RoomSpeakers" => [%{"id" => 201, "EventParticipant" => %{"id" => 41}}]
                  }
                ]
              }
            ]
          })
      end
    end)

    html = conn |> log_in(user) |> get(~p"/") |> html_response(200)

    assert html =~ ~s(id="my-sessions")
    refute html =~ "Past sessions will appear here."
    assert html =~ "Kyiv Debate Club"
    assert html =~ "speaker"
    assert html =~ "won"
    # the session row links to its P6 page
    assert html =~ ~s(href="/c/#{club.uuid}/s/#{session.uuid}")
  end
end
