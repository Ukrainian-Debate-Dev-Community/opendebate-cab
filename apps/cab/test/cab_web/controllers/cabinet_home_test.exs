defmodule CabWeb.CabinetHomeTest do
  @moduledoc """
  GET / on the sidenav shell: the anonymous front page (clubs
  directory with the words Tonight column) and the signed-in cabinet
  (my clubs, my sessions).
  """

  use CabWeb.ConnCase, async: true

  import Cab.Fixtures

  defp log_in(conn, user) do
    conn
    |> init_test_session(%{user_id: user.id})
    |> Plug.Conn.put_private(:plug_skip_csrf_protection, true)
  end

  test "anonymous front page: sidenav shell, pitch, clubs directory", %{conn: conn} do
    head = user_fixture()

    club =
      club_fixture(head, %{
        name: "Kyiv Debate Club #{System.unique_integer([:positive])}",
        city: "Kyiv"
      })

    html = conn |> get(~p"/") |> html_response(200)

    # the sidenav shell: brand cap, global items, Sign in profile
    assert html =~ ~s(id="sidenav")
    assert html =~ ~s(class="cap")
    assert html =~ ">Clubs<"
    assert html =~ ~s(href="/standings/teams")
    assert html =~ ~s(id="sidenav-profile")
    assert html =~ ~s(href="/signin")
    refute html =~ "/auth/github"
    refute html =~ ">Admin<"

    # the one-line pitch banner
    assert html =~ ~s(class="banner info")
    assert html =~ "free for every Ukrainian club"

    # directory: name, city, members, Tonight words
    assert html =~ ~s(id="clubs-directory")
    assert html =~ "Kyiv Debate Club"
    assert html =~ ~s(href="/c/#{club.uuid}")
    assert html =~ "quiet"

    refute html =~ "My clubs"
    refute html =~ "Sign out"
  end

  test "an archived club is absent from the public directory", %{conn: conn} do
    head = user_fixture()
    club = club_fixture(head, %{name: "Gone Club #{System.unique_integer([:positive])}"})
    {:ok, _} = Cab.Clubs.archive_club(club)

    html = conn |> get(~p"/") |> html_response(200)
    refute html =~ club.name
  end

  test "signed-in cabinet lists my clubs with Tonight words, no pills", %{conn: conn} do
    user = user_fixture(%{username: "anna"})
    head = user_fixture()
    stub_empty_schedule()

    club =
      club_fixture(head, %{
        name: "Kyiv Debate Club #{System.unique_integer([:positive])}",
        city: "Kyiv"
      })

    membership_fixture(user, club)

    _my_club =
      club_fixture(user, %{name: "Lviv Debate Society #{System.unique_integer([:positive])}"})

    pending_club =
      club_fixture(user_fixture(), %{name: "Odesa Debates #{System.unique_integer([:positive])}"})

    {:ok, _} = Cab.Clubs.request_join(user, pending_club, %{"message" => "hi", "contact" => "@a"})

    html = conn |> log_in(user) |> get(~p"/") |> html_response(200)

    # the profile block pinned to the sidenav bottom
    assert html =~ ~s(id="sidenav-profile")
    assert html =~ "anna"
    assert html =~ ~s(href="/account")
    assert html =~ "sign out"

    # my clubs: rows link to the club page; roles written as words
    assert html =~ ~s(id="my-clubs")
    assert html =~ "Kyiv Debate Club"
    assert html =~ "member"
    assert html =~ ~s(href="/c/#{club.uuid}")
    assert html =~ "Lviv Debate Society"
    assert html =~ "head"
    assert html =~ "quiet"

    # pending request: words, not a pill
    assert html =~ "Odesa Debates"
    assert html =~ "request pending"
    refute html =~ "tag-warn"

    # my sessions: no participations yet -> the table's empty state
    assert html =~ ~s(id="my-sessions")
    assert html =~ "Past sessions will appear here."
  end

  test "tonight banner and sign-ups-open words when a club has an open session",
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
        "/api/users/schedule" ->
          Req.Test.json(req, %{
            "status" => "success",
            "data" => %{"as_adjudicator" => [], "as_player" => []}
          })

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
    assert html =~ ~s(href="/c/#{club.uuid}")
    assert html =~ "sign-ups open"
  end

  test "my sessions lists past participations, rows linking to the session page",
       %{conn: conn} do
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
        "/api/users/schedule" ->
          Req.Test.json(req, %{
            "status" => "success",
            "data" => %{"as_adjudicator" => [], "as_player" => []}
          })

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
    # the session row links to its page
    assert html =~ ~s(href="/c/#{club.uuid}/s/#{session.uuid}")
  end
  defp stub_empty_schedule do
    Req.Test.stub(Core.Engine, fn req ->
      case req.request_path do
        "/api/users/schedule" ->
          Req.Test.json(req, %{
            "status" => "success",
            "data" => %{"as_adjudicator" => [], "as_player" => []}
          })
      end
    end)
  end

  test "my schedule lists upcoming signups across clubs", %{conn: conn} do
    user = user_fixture(%{username: "vera", node_user_id: 344})
    head_a = user_fixture(%{node_user_id: 9})
    head_b = user_fixture(%{node_user_id: 10})
    club_a = club_fixture(head_a, %{name: "Kyiv A #{System.unique_integer([:positive])}"})
    club_b = club_fixture(head_b, %{name: "Lviv B #{System.unique_integer([:positive])}"})
    membership_fixture(user, club_a)

    s1 = session_fixture(club_a, engine_event_id: 11, scheduled_at: ~U[2026-10-09 18:30:00Z])
    s2 = session_fixture(club_b, engine_event_id: 12, scheduled_at: ~U[2026-10-10 19:00:00Z])

    Req.Test.stub(Core.Engine, fn req ->
      case req.request_path do
        "/api/users/schedule" ->
          Req.Test.json(req, %{
            "status" => "success",
            "data" => %{
              "as_adjudicator" => [%{"id" => 12, "name" => "Friday open"}],
              "as_player" => [%{"id" => 11, "name" => "Thursday practice"}]
            }
          })

        "/api/events/organisation/" <> _ ->
          Req.Test.json(req, %{"status" => "success", "data" => []})

        "/api/events/11/rounds" ->
          Req.Test.json(req, %{
            "status" => "success",
            "data" => [%{"id" => 21, "sequence" => 1}]
          })

        "/api/events/11/participants" ->
          Req.Test.json(req, %{"status" => "success", "data" => []})

        "/api/rounds/21/rooms" ->
          Req.Test.json(req, %{"status" => "success", "data" => []})

        "/api/events/11" ->
          Req.Test.json(req, %{
            "status" => "success",
            "data" => %{"id" => 11, "status" => "scheduled"}
          })
      end
    end)

    html = conn |> log_in(user) |> get(~p"/") |> html_response(200)

    assert html =~ ~s(id="my-schedule")
    # one row per signup, across clubs — membership not required
    assert html =~ ~s(href="/c/#{club_a.uuid}/s/#{s1.uuid}")
    assert html =~ ~s(href="/c/#{club_b.uuid}/s/#{s2.uuid}")
    assert html =~ "speaker"
    assert html =~ "judge"
  end

end
