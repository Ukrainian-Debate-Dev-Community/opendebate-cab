defmodule CabWeb.HtmlTreesTest do
  @moduledoc """
  The role-scoped club trees after M8a: the club page (view +
  owner edit-in-place), the join form, the sessions archive, the
  members pages, the interim owner session surface (the M7 console's
  Registration/Tonight/Rooms content) and the session-page flows.
  """

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

  defp join_answers, do: %{"message" => "I debated at school", "contact" => "@tg"}

  setup %{conn: conn} do
    head = user_fixture(%{node_user_id: 9})
    club = club_fixture(head, %{engine_organisation_id: 3})
    %{conn: conn, head: head, club: club}
  end

  # ---------------------------------------------------------------
  # Club page: profile view + owner edit-in-place
  # ---------------------------------------------------------------

  test "club page: about card with the profile columns, recent sessions, join CTA", %{
    conn: conn,
    club: club
  } do
    {:ok, club} =
      Cab.Clubs.update_club(club, %{
        meeting_info: "Thursdays 18:30",
        description: "BP club at the university",
        contacts: "@kyivdebate"
      })

    session = session_fixture(club, engine_event_id: 11)

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
              "RoomTeams" => [
                %{"id" => 1, "rank" => 1, "position" => 1, "Team" => %{"name" => "Winners"}}
              ]
            }
          ])
      end
    end)

    html = conn |> get(~p"/c/#{club.uuid}") |> html_response(200)
    assert html =~ club.name

    # the about card carries the new profile columns
    assert html =~ "Thursdays 18:30"
    assert html =~ "BP club at the university"
    assert html =~ "@kyivdebate"

    # recent sessions: rows -> session page, progress as words
    assert html =~ ~s(id="recent-sessions")
    assert html =~ "Night 1"
    assert html =~ "won by Winners"
    assert html =~ ~s(href="/c/#{club.uuid}/s/#{session.uuid}")

    # anonymous: the gold join CTA routes to /signin; club sidenav
    assert html =~ "Request to join"
    assert html =~ ~s(class="go")
    assert html =~ ~s(href="/signin")
    refute html =~ "/auth/github"

    # signed-in non-members get the join FORM link, never a bare POST
    joiner = user_fixture()
    signed = conn |> log_in(joiner) |> get(~p"/c/#{club.uuid}") |> html_response(200)
    assert signed =~ ~s(href="/c/#{club.uuid}/join")
  end

  test "owner path is the same page as an edit-in-place form", %{
    conn: conn,
    club: club,
    head: head
  } do
    html = conn |> log_in(head) |> get(~p"/c/#{club.uuid}/owner") |> html_response(200)

    # the profile form with Save in the chrome
    assert html =~ ~s(id="club-profile-form")
    assert html =~ ~s(name="meeting_info")
    assert html =~ ~s(name="description")
    assert html =~ ~s(name="contacts")
    assert html =~ ~s(form="club-profile-form")
    assert html =~ "Save"

    saved =
      conn
      |> log_in(head)
      |> post(~p"/c/#{club.uuid}/owner/club", %{
        name: "Renamed",
        city: "Lviv",
        meeting_info: "Fridays",
        description: "About",
        contacts: "@tg"
      })

    assert redirected_to(saved) == "/c/#{club.uuid}/owner"
    reloaded = Cab.Clubs.get_by_uuid(club.uuid)
    assert reloaded.name == "Renamed"
    assert reloaded.meeting_info == "Fridays"
    assert reloaded.contacts == "@tg"

    # owner-tree only
    member = user_fixture()
    membership_fixture(member, club)
    assert conn |> log_in(member) |> get(~p"/c/#{club.uuid}/owner") |> response(403)
    assert conn |> log_in(member) |> post(~p"/c/#{club.uuid}/owner/club") |> response(403)
  end

  # ---------------------------------------------------------------
  # The join form
  # ---------------------------------------------------------------

  test "join: the FORM page with required answers; the owner reads them in Requests", %{
    conn: conn,
    club: club,
    head: head
  } do
    user = user_fixture(%{username: "wannabe"})

    # the form page: both required blocks
    form = conn |> log_in(user) |> get(~p"/c/#{club.uuid}/join") |> html_response(200)
    assert form =~ ~s(id="join-request-form")
    assert form =~ ~s(name="message")
    assert form =~ ~s(name="contact")

    # missing answers re-render with the errors — no request created
    failed = conn |> log_in(user) |> post(~p"/c/#{club.uuid}/join", %{message: "hi"})
    assert html_response(failed, 422) =~ "tell the head"
    assert Cab.Clubs.list_join_requests(club) == []

    sent =
      conn
      |> log_in(user)
      |> post(~p"/c/#{club.uuid}/join", %{message: "I debated at school", contact: "@wb"})

    assert redirected_to(sent) == "/c/#{club.uuid}"
    assert Phoenix.Flash.get(sent.assigns.flash, :info) =~ "club head will approve"
    assert [request] = Cab.Clubs.list_join_requests(club)
    assert request.message == "I debated at school"
    assert request.contact == "@wb"

    # the owner's members page shows the answers
    owner_html =
      conn |> log_in(head) |> get(~p"/c/#{club.uuid}/owner/members") |> html_response(200)

    assert owner_html =~ "wannabe"
    assert owner_html =~ "I debated at school"
    assert owner_html =~ "@wb"

    # anonymous visitors hit the auth wall -> /signin
    anon = get(conn, ~p"/c/#{club.uuid}/join")
    assert redirected_to(anon) == "/signin"
  end

  test "owner approves and declines from the members page", %{
    conn: conn,
    club: club,
    head: head
  } do
    user = user_fixture(%{username: "wannabe"})
    {:ok, membership} = Cab.Clubs.request_join(user, club, join_answers())

    html = conn |> log_in(head) |> get(~p"/c/#{club.uuid}/owner/members") |> html_response(200)
    assert html =~ "join-request-#{membership.id}"

    conn2 =
      conn
      |> log_in(head)
      |> post(~p"/c/#{club.uuid}/owner/join-requests/#{membership.id}/approve")

    assert redirected_to(conn2) == "/c/#{club.uuid}/owner/members"
    assert Cab.Clubs.role_for(club, user) == :member
  end

  test "approve of another club's request is 404", %{conn: conn, head: head, club: club} do
    other_club = club_fixture(user_fixture())
    user = user_fixture()
    {:ok, membership} = Cab.Clubs.request_join(user, other_club, join_answers())

    conn =
      conn
      |> log_in(head)
      |> post(~p"/c/#{club.uuid}/owner/join-requests/#{membership.id}/approve")

    assert response(conn, 404)
  end

  # ---------------------------------------------------------------
  # Members pages
  # ---------------------------------------------------------------

  test "members: member path = roster only; owner path adds requests and revoke", %{
    conn: conn,
    club: club,
    head: head
  } do
    member = user_fixture(%{username: "plainmember"})
    membership_fixture(member, club)
    {:ok, _} = Cab.Clubs.request_join(user_fixture(%{username: "nina"}), club, join_answers())

    roster =
      conn |> log_in(member) |> get(~p"/c/#{club.uuid}/members") |> html_response(200)

    assert roster =~ ~s(id="members-list")
    assert roster =~ "plainmember"
    refute roster =~ ~s(id="join-requests")
    refute roster =~ "/owner/members/"

    owner =
      conn |> log_in(head) |> get(~p"/c/#{club.uuid}/owner/members") |> html_response(200)

    assert owner =~ ~s(id="join-requests")
    assert owner =~ "nina"
    assert owner =~ "/c/#{club.uuid}/owner/members/#{member.id}/remove"
    refute owner =~ "/c/#{club.uuid}/owner/members/#{head.id}/remove"

    removed =
      conn |> log_in(head) |> post(~p"/c/#{club.uuid}/owner/members/#{member.id}/remove")

    assert redirected_to(removed) == "/c/#{club.uuid}/owner/members"
    assert Cab.Clubs.role_for(club, member) == :public
  end

  # ---------------------------------------------------------------
  # Sessions archive + open new session
  # ---------------------------------------------------------------

  test "sessions archive: on the club pages; the owner opens new sessions from /owner", %{
    conn: conn,
    club: club,
    head: head
  } do
    member = user_fixture()
    membership_fixture(member, club)
    done = session_fixture(club, engine_event_id: 11)

    stub(fn conn, params ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/events/organisation/3"} ->
          ok(conn, [
            %{"id" => 11, "name" => "Done night", "status" => "completed"}
          ])

        {"GET", "/api/events/11/rounds"} ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        {"GET", "/api/rounds/21/rooms"} ->
          ok(conn, [
            %{
              "id" => 71,
              "status" => "confirmed",
              "RoomTeams" => [%{"id" => 1, "rank" => 1, "Team" => %{"name" => "Winners"}}]
            }
          ])

        {"POST", "/api/events/3"} ->
          ok(conn, %{"id" => 12, "name" => params["name"], "status" => "scheduled"})

        {"POST", "/api/events/12/rounds"} ->
          ok(conn, %{"id" => 22, "sequence" => 1})
      end
    end)

    # the club page IS the archive now — public, full list, no form
    member_html =
      conn |> log_in(member) |> get(~p"/c/#{club.uuid}") |> html_response(200)

    assert member_html =~ ~s(id="recent-sessions")
    assert member_html =~ "Done night"
    assert member_html =~ ~s(href="/c/#{club.uuid}/s/#{done.uuid}")
    refute member_html =~ ~s(id="open-session-form")
    refute member_html =~ "Open new session"

    # owner path: the archive + open-session form live on /owner now
    owner_html =
      conn |> log_in(head) |> get(~p"/c/#{club.uuid}/owner") |> html_response(200)

    assert owner_html =~ ~s(id="sessions-archive")
    assert owner_html =~ ~s(id="open-session-form")
    assert owner_html =~ ~s(form="open-session-form")
    assert owner_html =~ "Open new session"

    # the separate owner Sessions page is gone (v3.1: two trees, no extras)
    assert conn |> log_in(head) |> get("/c/#{club.uuid}/owner/sessions") |> response(404)

    opened =
      conn
      |> log_in(head)
      |> post(~p"/c/#{club.uuid}/owner/sessions", %{
        name: "Tuesday",
        date: "2026-10-09",
        time: "18:30"
      })

    assert [session, _done] = Cab.Sessions.list_for_club(club)
    assert redirected_to(opened) == "/c/#{club.uuid}/owner/s/#{session.uuid}"
    assert session.engine_event_id == 12
    assert session.scheduled_at == ~U[2026-10-09 18:30:00Z]

    # the old member archive route is gone
    assert conn |> get("/c/#{club.uuid}/member/sessions") |> response(404)
  end

  # ---------------------------------------------------------------
  # Old routes: the M7 member page and the ?tab console are gone
  # ---------------------------------------------------------------

  test "the member tree is gone — v3.1 keeps one URL per view", %{conn: conn, club: club} do
    assert conn |> get("/c/#{club.uuid}/member") |> response(404)
  end

  test "the owner ?tab console is gone — /owner?tab=x is the club edit page", %{
    conn: conn,
    club: club,
    head: head
  } do
    html =
      conn |> log_in(head) |> get(~p"/c/#{club.uuid}/owner?tab=rooms") |> html_response(200)

    assert html =~ ~s(id="club-profile-form")
    refute html =~ "subnav"
    refute html =~ "?tab="
  end

  # ---------------------------------------------------------------
  # Member registration through the session page
  # ---------------------------------------------------------------

  test "member registers via the form page and lands on the session page", %{
    conn: conn,
    club: club
  } do
    member = user_fixture(%{node_user_id: 44})
    membership_fixture(member, club)
    session = session_fixture(club, engine_event_id: 11)

    stub(fn conn, params ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/events/organisation/3"} ->
          ok(conn, [])

        {"GET", "/api/events/11"} ->
          ok(conn, %{"id" => 11, "name" => "Night", "status" => "scheduled"})

        {"GET", "/api/events/11/rounds"} ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        {"GET", "/api/events/11/participants"} ->
          ok(conn, [])

        {"GET", "/api/rounds/21/rooms"} ->
          ok(conn, [])

        {"POST", "/api/events/11/participants"} ->
          assert params["role"] == "speaker"
          ok(conn, %{"id" => 41, "role" => "speaker"})
      end
    end)

    # the session page carries the gold Register segment -> /r/:sess
    page =
      conn |> log_in(member) |> get(~p"/c/#{club.uuid}/s/#{session.uuid}") |> html_response(200)

    assert page =~ "Register"
    assert page =~ "/r/#{session.uuid}"

    # THE registration URL, signed-in: prefilled, role pills, no name field
    html =
      conn
      |> log_in(member)
      |> get(~p"/r/#{session.uuid}")
      |> html_response(200)

    assert html =~ ~s(id="register-form")
    assert html =~ "Registering as"
    assert html =~ "Speaker"
    assert html =~ "Judge"
    assert html =~ ~s(name="as")
    refute html =~ ~s(name="name")

    conn =
      conn
      |> log_in(member)
      |> post(~p"/r/#{session.uuid}", %{as: "speak"})

    assert redirected_to(conn) == "/c/#{club.uuid}/s/#{session.uuid}"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "registered"
  end

  test "registered member cancels from the session page; register bounces once closed", %{
    conn: conn,
    club: club
  } do
    member = user_fixture(%{node_user_id: 44})
    membership_fixture(member, club)
    session = closed_session_fixture(club, engine_event_id: 11)
    test_pid = self()

    stub(fn conn, _params ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/events/organisation/3"} ->
          ok(conn, [])

        {"GET", "/api/events/11"} ->
          ok(conn, %{"id" => 11, "name" => "Night", "status" => "scheduled"})

        {"GET", "/api/events/11/rounds"} ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        {"GET", "/api/events/11/participants"} ->
          ok(conn, [%{"id" => 41, "user_id" => 44, "role" => "speaker", "display_name" => "Me"}])

        {"GET", "/api/rounds/21/rooms"} ->
          ok(conn, [])

        {"DELETE", "/api/events/11/participants/41"} ->
          send(test_pid, :removed)
          Req.Test.json(conn, %{"status" => "success", "message" => "Participant archived."})
      end
    end)

    closed_page =
      conn
      |> log_in(member)
      |> get(~p"/r/#{session.uuid}")
      |> html_response(200)

    assert closed_page =~ "closed"

    cancelled =
      conn
      |> log_in(member)
      |> post(~p"/c/#{club.uuid}/s/#{session.uuid}/signups/41/remove")

    assert redirected_to(cancelled) == "/c/#{club.uuid}/s/#{session.uuid}"
    assert Phoenix.Flash.get(cancelled.assigns.flash, :info) =~ "registration cancelled"
    assert_received :removed
  end

  # ---------------------------------------------------------------
  # The interim owner session surface
  # ---------------------------------------------------------------

  defp signup_stage_signups do
    for id <- 1..8 do
      %{"id" => id, "role" => "speaker", "display_name" => "Speaker #{id}", "user_id" => 400 + id}
    end ++ [%{"id" => 99, "role" => "adjudicator", "display_name" => "Judge", "user_id" => 499}]
  end

  defp stub_signup_stage(signups, extra \\ fn _conn, _params -> nil end) do
    stub(fn conn, params ->
      case extra.(conn, params) do
        nil ->
          case {conn.method, conn.request_path} do
            {"GET", "/api/events/organisation/3"} ->
              ok(conn, [])

            {"GET", "/api/events/11"} ->
              ok(conn, %{"id" => 11, "name" => "Night", "status" => "scheduled"})

            {"GET", "/api/events/11/rounds"} ->
              ok(conn, [%{"id" => 21, "sequence" => 1}])

            {"GET", "/api/events/11/participants"} ->
              ok(conn, signups)

            {"GET", "/api/rounds/21/rooms"} ->
              ok(conn, [])

            {"GET", "/api/events/11/teams/auto-generate"} ->
              ok(conn, %{
                "total_free_speakers" => 8,
                "proposed_teams" =>
                  for n <- 0..3 do
                    %{"name" => "T#{n + 1}", "participant_ids" => [2 * n + 1, 2 * n + 2]}
                  end
              })
          end

        response ->
          response
      end
    end)
  end

  test "owner session surface at sign-up: registration + tonight + rooms sections, stage chrome",
       %{conn: conn, club: club, head: head} do
    member = user_fixture(%{node_user_id: 444, username: "benched"})
    membership_fixture(member, club)
    session = session_fixture(club, engine_event_id: 11)
    stub_signup_stage(signup_stage_signups())

    html =
      conn
      |> log_in(head)
      |> get(~p"/c/#{club.uuid}/owner/s/#{session.uuid}")
      |> html_response(200)

    # stage words in the crumb, chrome actions for :signup only
    assert html =~ "sign-ups open"
    assert html =~ "Close sign-ups"
    assert html =~ "/c/#{club.uuid}/owner/sessions/#{session.uuid}/close-signups"
    assert html =~ "Cancel session"
    refute html =~ "Make rooms"
    refute html =~ "Compose rooms"
    refute html =~ "Reopen sign-ups"
    refute html =~ "Delete rooms"

    # registration: the shared URL + guest links; tonight: signups +
    # the on-behalf form; rooms: the waiting note — all ONE page now
    assert html =~ ~s(id="shared-registration-url")
    assert html =~ ~s(id="guest-links")
    assert html =~ ~s(id="session-signups")
    assert html =~ "/c/#{club.uuid}/owner/sessions/#{session.uuid}/signups/1/remove"
    assert html =~ ~s(id="add-signup-form")
    assert html =~ "benched"
    assert html =~ "8 speakers · 1 judge"
    assert html =~ "Rooms are composed after sign-ups close."

    # the owner surface is owner-tree only
    assert conn
           |> log_in(member)
           |> get(~p"/c/#{club.uuid}/owner/s/#{session.uuid}")
           |> response(403)
  end

  test "owner surface at :closed: Make/Compose/Reopen; lifecycle twins redirect back",
       %{conn: conn, club: club, head: head} do
    session = closed_session_fixture(club, engine_event_id: 11)
    stub_signup_stage(signup_stage_signups())

    html =
      conn
      |> log_in(head)
      |> get(~p"/c/#{club.uuid}/owner/s/#{session.uuid}")
      |> html_response(200)

    assert html =~ "Make rooms"
    assert html =~ "Compose rooms"
    assert html =~ "/c/#{club.uuid}/owner/sessions/#{session.uuid}/compose"
    assert html =~ "Reopen sign-ups"
    assert html =~ "sign-ups closed"
    refute html =~ "Close sign-ups"

    reopened =
      conn
      |> log_in(head)
      |> post(~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/reopen-signups")

    assert redirected_to(reopened) == "/c/#{club.uuid}/owner/s/#{session.uuid}"
    assert Phoenix.Flash.get(reopened.assigns.flash, :info) =~ "sign-ups reopened"

    closed =
      conn
      |> log_in(head)
      |> post(~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/close-signups")

    assert redirected_to(closed) == "/c/#{club.uuid}/owner/s/#{session.uuid}"

    bounced =
      conn
      |> log_in(head)
      |> post(~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/close-signups")

    assert Phoenix.Flash.get(bounced.assigns.flash, :error) =~ "session is closed"
  end

  test "owner signs a member up on their behalf and removes a signup",
       %{conn: conn, club: club, head: head} do
    member = user_fixture(%{node_user_id: 444, username: "benched"})
    membership_fixture(member, club)
    session = session_fixture(club, engine_event_id: 11)
    test_pid = self()

    stub_signup_stage(signup_stage_signups(), fn conn, params ->
      case {conn.method, conn.request_path} do
        {"POST", "/api/events/11/participants"} ->
          send(test_pid, {:added, params})
          ok(conn, %{"id" => 50, "role" => params["role"]})

        {"DELETE", "/api/events/11/participants/3"} ->
          send(test_pid, :removed)
          Req.Test.json(conn, %{"status" => "success", "message" => "Participant archived."})

        _other ->
          nil
      end
    end)

    added =
      conn
      |> log_in(head)
      |> post(~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/signups", %{
        username: "benched",
        as: "judge"
      })

    assert redirected_to(added) == "/c/#{club.uuid}/owner/s/#{session.uuid}"
    assert Phoenix.Flash.get(added.assigns.flash, :info) =~ "benched"
    assert_received {:added, %{"user_id" => 444, "role" => "adjudicator"}}

    removed =
      conn
      |> log_in(head)
      |> post(~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/signups/3/remove")

    assert redirected_to(removed) == "/c/#{club.uuid}/owner/s/#{session.uuid}"
    assert Phoenix.Flash.get(removed.assigns.flash, :info) =~ "signup removed"
    assert_received :removed
  end

  # ---------------------------------------------------------------
  # Compose (dnd) — unchanged behavior, new addresses
  # ---------------------------------------------------------------

  test "compose page is the dnd table; the form posts the composition", %{
    conn: conn,
    club: club,
    head: head
  } do
    session = closed_session_fixture(club, engine_event_id: 11)
    test_pid = self()

    stub_signup_stage(signup_stage_signups(), fn conn, params ->
      case {conn.method, conn.request_path} do
        {"POST", "/api/rounds/21/rooms"} ->
          send(test_pid, {:room, params})
          ok(conn, %{"id" => 71})

        _other ->
          nil
      end
    end)

    html =
      conn
      |> log_in(head)
      |> get(~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/compose")
      |> html_response(200)

    # the dnd table: a tray of draggable chips over droppable slots
    # that mirror hidden inputs — NO dropdowns anywhere
    assert html =~ ~s(id="compose-rooms-form")
    assert html =~ "data-dnd"
    assert html =~ "data-tray"
    assert html =~ ~s(draggable="true")
    assert html =~ ~s(data-kind="spk")
    assert html =~ ~s(data-kind="judge")
    assert html =~ "Speaker 8"
    assert html =~ ~s(name="rooms[1][og][1]")
    assert html =~ ~s(name="rooms[1][co][2]")
    assert html =~ ~s(name="rooms[1][judge]")
    refute html =~ "<select"

    # the submit segment lives in the chrome; 8 speakers allow a
    # second room via the "+ room" link (plain REST reload)
    assert html =~ ~s(form="compose-rooms-form")
    assert html =~ "Make these rooms"
    assert html =~ "+ room"
    assert html =~ "compose?rooms=2"
    refute html =~ ~s(name="rooms[2][og][1]")

    two_rooms =
      conn
      |> log_in(head)
      |> get(~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/compose?rooms=2")
      |> html_response(200)

    assert two_rooms =~ ~s(name="rooms[2][og][1]")
    refute two_rooms =~ "+ room"

    # the dnd slots post rooms[i][side][slot] (+ judge); empty slots
    # post "" — an iron team is a single filled slot
    posted =
      conn
      |> log_in(head)
      |> post(~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/rooms", %{
        "rooms" => %{
          "1" => %{
            "judge" => "99",
            "og" => %{"1" => "7", "2" => "8"},
            "oo" => %{"1" => "3", "2" => "4"},
            "cg" => %{"1" => "5", "2" => "6"},
            "co" => %{"1" => "1", "2" => ""}
          }
        }
      })

    assert redirected_to(posted) == "/c/#{club.uuid}/owner/s/#{session.uuid}"
    assert Phoenix.Flash.get(posted.assigns.flash, :info) =~ "1 room(s) created"
    assert_received {:room, room_params}

    assert [
             %{"participant_ids" => [7, 8], "position" => 1},
             %{"participant_ids" => [3, 4], "position" => 2},
             %{"participant_ids" => [5, 6], "position" => 3},
             %{"participant_ids" => [1], "position" => 4}
           ] = room_params["teams"]

    # an impossible composition bounces back with the reason
    bounced =
      conn
      |> log_in(head)
      |> post(~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/rooms", %{
        "rooms" => %{
          "1" => %{
            "judge" => "99",
            "og" => %{"1" => "1", "2" => "1"},
            "oo" => %{"1" => "3", "2" => "4"},
            "cg" => %{"1" => "5", "2" => "6"},
            "co" => %{"1" => "7", "2" => "8"}
          }
        }
      })

    assert redirected_to(bounced) == "/c/#{club.uuid}/owner/s/#{session.uuid}"
    assert Phoenix.Flash.get(bounced.assigns.flash, :error) =~ "placed more than once"

    # compose is owner-tree only — a member gets 403
    member = user_fixture(%{node_user_id: 55})
    membership_fixture(member, club)

    denied =
      conn |> log_in(member) |> get(~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/compose")

    assert response(denied, 403)
  end

  test "compose requires :closed — while :signup it bounces to the owner surface",
       %{conn: conn, club: club, head: head} do
    session = session_fixture(club, engine_event_id: 11)
    stub_signup_stage(signup_stage_signups())

    bounced =
      conn
      |> log_in(head)
      |> get(~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/compose")

    assert redirected_to(bounced) == "/c/#{club.uuid}/owner/s/#{session.uuid}"
    assert Phoenix.Flash.get(bounced.assigns.flash, :error) =~ "close sign-ups first"
  end

  # ---------------------------------------------------------------
  # Running stage on the owner surface + ballots
  # ---------------------------------------------------------------

  # a running session: judging room 71 chaired by engine user
  # `chair_user_id`, four teams, speakers 301..308
  defp running_room(chair_user_id) do
    %{
      "id" => 71,
      "status" => "judging",
      "Motion" => %{"motion_text" => "THW fill ballots"},
      "RoomAdjudicators" => [
        %{
          "id" => 1,
          "role" => "chair",
          "EventParticipant" => %{"id" => 90, "user_id" => chair_user_id}
        }
      ],
      "RoomTeams" =>
        for position <- 1..4 do
          %{
            "id" => 100 + position,
            "position" => position,
            "Team" => %{"name" => "Team #{position}"},
            "RoomSpeakers" =>
              for n <- [1, 2] do
                %{
                  "id" => 200 + position * 2 - 2 + n,
                  "EventParticipant" => %{
                    "id" => 300 + position * 2 - 2 + n,
                    "display_name" => "Speaker #{position}.#{n}"
                  }
                }
              end
          }
        end
    }
  end

  defp stub_running_session(room, test_pid \\ nil) do
    stub(fn conn, params ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/events/organisation/3"} ->
          ok(conn, [])

        {"GET", "/api/events/11"} ->
          ok(conn, %{"id" => 11, "name" => "Night", "status" => "scheduled"})

        {"GET", "/api/events/11/rounds"} ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        {"GET", "/api/events/11/participants"} ->
          ok(conn, [])

        {"GET", "/api/rounds/21/rooms"} ->
          ok(conn, [room])

        {"POST", "/api/rooms/71/scores"} ->
          if test_pid, do: send(test_pid, {:scores, params})
          Req.Test.json(conn, %{"status" => "success", "message" => "ok"})

        {"PATCH", "/api/rooms/71/confirm"} ->
          if test_pid, do: send(test_pid, :confirmed)
          Req.Test.json(conn, %{"status" => "success", "message" => "ok"})
      end
    end)
  end

  defp ballot_params(og_scores) do
    %{
      "ballot" => %{
        "og" => %{
          "PM" => %{"speaker" => "301", "score" => Enum.at(og_scores, 0)},
          "DPM" => %{"speaker" => "302", "score" => Enum.at(og_scores, 1)}
        },
        "oo" => %{
          "LO" => %{"speaker" => "303", "score" => "76"},
          "DLO" => %{"speaker" => "304", "score" => "75"}
        },
        "cg" => %{
          "MG" => %{"speaker" => "305", "score" => "74"},
          "GW" => %{"speaker" => "306", "score" => "75"}
        },
        "co" => %{
          "MO" => %{"speaker" => "307", "score" => "72"},
          "OW" => %{"speaker" => "308", "score" => "75"}
        }
      }
    }
  end

  test "the room judge sees Fill ballot on the session page and submits there", %{
    conn: conn,
    club: club
  } do
    judge = user_fixture(%{node_user_id: 44})
    membership_fixture(judge, club)
    session = session_fixture(club, engine_event_id: 11)
    stub_running_session(running_room(44), self())

    page = conn |> log_in(judge) |> get(~p"/c/#{club.uuid}/s/#{session.uuid}")
    home = html_response(page, 200)
    assert home =~ "Fill ballot"
    assert home =~ "/c/#{club.uuid}/s/#{session.uuid}/rooms/71/ballot"

    html =
      conn
      |> log_in(judge)
      |> get(~p"/c/#{club.uuid}/s/#{session.uuid}/rooms/71/ballot")
      |> html_response(200)

    assert html =~ ~s(class="ballot")
    assert html =~ "THW fill ballots"
    assert html =~ ~s(form="ballot-71")

    # og total 151 == oo total 151 -> amber re-render naming the total
    tied =
      conn
      |> log_in(judge)
      |> post(
        ~p"/c/#{club.uuid}/s/#{session.uuid}/rooms/71/ballot",
        ballot_params(["76", "75"])
      )

    assert html_response(tied, 422) =~ "share the total 151"
    refute_received {:scores, _params}

    done =
      conn
      |> log_in(judge)
      |> post(
        ~p"/c/#{club.uuid}/s/#{session.uuid}/rooms/71/ballot",
        ballot_params(["78", "76"])
      )

    assert redirected_to(done) == "/c/#{club.uuid}/s/#{session.uuid}"
    assert_received {:scores, params}
    assert [%{"room_team_id" => 101, "rank" => 1} | _rest] = params["teamRankings"]
    assert_received :confirmed
  end

  test "one room URL: public sees draw + motion, the chair gets the form and sets it", %{
    conn: conn,
    club: club
  } do
    judge = user_fixture(%{node_user_id: 44})
    membership_fixture(judge, club)
    session = session_fixture(club, engine_event_id: 11)
    test_pid = self()

    bare_room = Map.put(running_room(44), "Motion", nil)

    stub(fn conn, params ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/events/organisation/3"} ->
          ok(conn, [])

        {"GET", "/api/events/11"} ->
          ok(conn, %{"id" => 11, "name" => "Night", "status" => "scheduled"})

        {"GET", "/api/events/11/rounds"} ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        {"GET", "/api/events/11/participants"} ->
          ok(conn, [])

        {"GET", "/api/rounds/21/rooms"} ->
          ok(conn, [bare_room])

        {"POST", "/api/rooms/71/motion"} ->
          send(test_pid, {:motion, params["motion_text"]})
          ok(conn, %{"motion" => %{"motion_text" => params["motion_text"]}})
      end
    end)

    # anonymous: the draw and the honest "not set yet" — no form
    public_html =
      conn |> get(~p"/c/#{club.uuid}/s/#{session.uuid}/rooms/71") |> html_response(200)

    assert public_html =~ ~s(id="room-71-draw")
    assert public_html =~ "Not set yet"
    refute public_html =~ ~s(id="room-motion-71")

    # the chair: same URL, the motion form appears and posts
    chair_html =
      conn
      |> log_in(judge)
      |> get(~p"/c/#{club.uuid}/s/#{session.uuid}/rooms/71")
      |> html_response(200)

    assert chair_html =~ ~s(id="room-motion-71")

    set =
      conn
      |> log_in(judge)
      |> post(~p"/c/#{club.uuid}/s/#{session.uuid}/rooms/71/motion", %{
        motion_text: "THW debate"
      })

    assert redirected_to(set) == "/c/#{club.uuid}/s/#{session.uuid}/rooms/71"
    assert_received {:motion, "THW debate"}

    # a plain member is neither chair nor head — no motion for them
    outsider = user_fixture(%{node_user_id: 55})
    membership_fixture(outsider, club)

    denied =
      conn
      |> log_in(outsider)
      |> post(~p"/c/#{club.uuid}/s/#{session.uuid}/rooms/71/motion", %{
        motion_text: "THW hijack"
      })

    assert response(denied, 403)
  end

  test "a member who is not the room judge gets no ballot page", %{conn: conn, club: club} do
    speaker = user_fixture(%{node_user_id: 55})
    membership_fixture(speaker, club)
    session = session_fixture(club, engine_event_id: 11)
    stub_running_session(running_room(44))

    home = conn |> log_in(speaker) |> get(~p"/c/#{club.uuid}/s/#{session.uuid}")
    refute html_response(home, 200) =~ "Fill ballot"

    denied =
      conn |> log_in(speaker) |> get(~p"/c/#{club.uuid}/s/#{session.uuid}/rooms/71/ballot")

    assert response(denied, 403)

    # anonymous hits the auth wall
    anon = get(conn, ~p"/c/#{club.uuid}/s/#{session.uuid}/rooms/71/ballot")
    assert redirected_to(anon) == "/signin"
  end

  test "the owner surface serves the same ballot per open room; rooms status is words", %{
    conn: conn,
    club: club,
    head: head
  } do
    member = user_fixture(%{node_user_id: 55})
    membership_fixture(member, club)
    session = session_fixture(club, engine_event_id: 11)
    stub_running_session(running_room(44))

    show =
      conn
      |> log_in(head)
      |> get(~p"/c/#{club.uuid}/owner/s/#{session.uuid}")
      |> html_response(200)

    assert show =~ ~s(id="session-rooms")
    assert show =~ "/c/#{club.uuid}/s/#{session.uuid}/rooms/71/ballot"
    assert show =~ "waiting for the ballot"
    assert show =~ "Finish session"
    refute show =~ "tag-"

    html =
      conn
      |> log_in(head)
      |> get(~p"/c/#{club.uuid}/s/#{session.uuid}/rooms/71/ballot")
      |> html_response(200)

    assert html =~ ~s(class="ballot")
    assert html =~ ~s(action="/c/#{club.uuid}/s/#{session.uuid}/rooms/71/ballot")

    # the owner tree stays owner-only for members…
    denied = conn |> log_in(member) |> get(~p"/c/#{club.uuid}/s/#{session.uuid}/rooms/71/ballot")
    assert response(denied, 403)

    # …but the ladder lets a platform admin (no membership) through
    admin =
      user_fixture(%{node_user_id: 56})
      |> Ecto.Changeset.change(is_admin: true)
      |> Cab.Repo.update!()

    allowed = conn |> log_in(admin) |> get(~p"/c/#{club.uuid}/s/#{session.uuid}/rooms/71/ballot")
    assert html_response(allowed, 200) =~ ~s(class="ballot")
  end

  test "running stage: delete rooms while pending, edit ballot once in",
       %{conn: conn, club: club, head: head} do
    session = session_fixture(club, engine_event_id: 11)
    test_pid = self()

    pending_room = %{running_room(44) | "status" => "pending"}

    stub(fn conn, _params ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/events/organisation/3"} ->
          ok(conn, [])

        {"GET", "/api/events/11"} ->
          ok(conn, %{"id" => 11, "name" => "Night", "status" => "scheduled"})

        {"GET", "/api/events/11/rounds"} ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        {"GET", "/api/events/11/participants"} ->
          ok(conn, [])

        {"GET", "/api/rounds/21/rooms"} ->
          ok(conn, [pending_room])

        {"DELETE", "/api/rooms/71"} ->
          send(test_pid, :room_deleted)
          Req.Test.json(conn, %{"status" => "success", "message" => "Room archived."})
      end
    end)

    html =
      conn
      |> log_in(head)
      |> get(~p"/c/#{club.uuid}/owner/s/#{session.uuid}")
      |> html_response(200)

    assert html =~ "Delete rooms"
    assert html =~ "/c/#{club.uuid}/owner/sessions/#{session.uuid}/rooms/delete"
    refute html =~ "edit ballot"

    deleted =
      conn
      |> log_in(head)
      |> post(~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/rooms/delete")

    assert redirected_to(deleted) == "/c/#{club.uuid}/owner/s/#{session.uuid}"
    assert Phoenix.Flash.get(deleted.assigns.flash, :info) =~ "1 room(s) deleted"
    assert_received :room_deleted

    # confirmed room: no delete segment, an edit ballot link instead
    # (lock/unlock stays internal — the page never says it)
    confirmed_room =
      %{running_room(44) | "status" => "confirmed"}
      |> update_in(["RoomTeams"], fn teams ->
        Enum.map(teams, fn room_team ->
          update_in(room_team, ["RoomSpeakers"], fn speakers ->
            Enum.map(speakers, &Map.put(&1, "Scores", [%{"value" => 78}]))
          end)
        end)
      end)

    stub(fn conn, _params ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/events/organisation/3"} ->
          ok(conn, [])

        {"GET", "/api/events/11"} ->
          ok(conn, %{"id" => 11, "name" => "Night", "status" => "scheduled"})

        {"GET", "/api/events/11/rounds"} ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        {"GET", "/api/events/11/participants"} ->
          ok(conn, [])

        {"GET", "/api/rounds/21/rooms"} ->
          ok(conn, [confirmed_room])

        {"PATCH", "/api/rooms/71/" <> step} ->
          send(test_pid, {:step, step})
          Req.Test.json(conn, %{"status" => "success", "message" => "ok"})
      end
    end)

    html =
      conn
      |> log_in(head)
      |> get(~p"/c/#{club.uuid}/owner/s/#{session.uuid}")
      |> html_response(200)

    refute html =~ "Delete rooms"
    assert html =~ "edit ballot"
    assert html =~ "/c/#{club.uuid}/s/#{session.uuid}/rooms/71/ballot"
    assert html =~ "ballot in"
    refute html =~ "unlock"
    refute html =~ "unconfirm"

    # the link opens the ballot form PREFILLED with the stored scores
    ballot_html =
      conn
      |> log_in(head)
      |> get(~p"/c/#{club.uuid}/s/#{session.uuid}/rooms/71/ballot")
      |> html_response(200)

    assert ballot_html =~ ~s(class="ballot")
    assert ballot_html =~ ~s(value="78")
  end

  test "session cancel lands on the archive; finish lands on the session page",
       %{conn: conn, club: club, head: head} do
    session = session_fixture(club, engine_event_id: 11)
    test_pid = self()

    stub(fn conn, _params ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/events/organisation/3"} ->
          ok(conn, [])

        {"GET", "/api/events/11"} ->
          ok(conn, %{"id" => 11, "name" => "Night", "status" => "scheduled"})

        {"GET", "/api/events/11/rounds"} ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        {"GET", "/api/events/11/participants"} ->
          ok(conn, [])

        {"GET", "/api/rounds/21/rooms"} ->
          ok(conn, [])

        {"PUT", "/api/rounds/21"} ->
          Req.Test.json(conn, %{"status" => "success", "data" => %{}})

        {"PUT", "/api/events/11"} ->
          send(test_pid, :event_completed)
          Req.Test.json(conn, %{"status" => "success", "data" => %{}})

        {"DELETE", "/api/events/11"} ->
          send(test_pid, :event_deleted)
          Req.Test.json(conn, %{"status" => "success", "message" => "Event archived."})
      end
    end)

    finished =
      conn
      |> log_in(head)
      |> post(~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/finish")

    assert redirected_to(finished) == "/c/#{club.uuid}/s/#{session.uuid}"
    assert_received :event_completed

    cancelled =
      conn
      |> log_in(head)
      |> post(~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/cancel")

    assert redirected_to(cancelled) == "/c/#{club.uuid}/owner"
    assert_received :event_deleted
    assert Cab.Sessions.list_for_club(club) == []
  end

  test "acting on another club's session through this club's URL is 404", %{
    conn: conn,
    club: club
  } do
    member = user_fixture()
    membership_fixture(member, club)
    other_club = club_fixture(user_fixture())
    other_session = session_fixture(other_club)

    conn =
      conn
      |> log_in(member)
      |> post(~p"/c/#{club.uuid}/s/#{other_session.uuid}/signups/41/remove")

    assert response(conn, 404)
  end
end
