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

    session =
      session_fixture(club,
        engine_event_id: 11,
        name: "Night 1",
        finished_at: ~U[2026-10-08 20:00:00Z],
        winner_name: "Winners"
      )

    # the club page is cab's own records - no engine call at all
    stub(fn _conn, _params -> raise "the club page must not call the engine" end)

    html = conn |> get(~p"/c/#{club.uuid}") |> html_response(200)
    assert html =~ club.name

    # the about card carries the new profile columns
    assert html =~ "Thursdays 18:30"
    assert html =~ "BP club at the university"
    assert html =~ "@kyivdebate"

    # recent sessions: rows -> session page, progress as words
    assert html =~ ~s(id="club-sessions")
    assert html =~ "Night 1"
    assert html =~ "finished"
    refute html =~ "won by"
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
    Req.Test.stub(Core.Engine, fn conn ->
      Req.Test.json(conn, %{"status" => "success", "data" => %{}})
    end)

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

  test "join: the FORM asks the member fields; the owner reads the answers", %{
    conn: conn,
    club: club,
    head: head
  } do
    club =
      form_fields_fixture(club, [
        %{"label" => "University", "type" => "text", "required" => "yes", "scope" => "members"},
        %{
          "label" => "Who invited you",
          "type" => "text",
          "required" => "yes",
          "scope" => "guests"
        }
      ])

    uni = field_id(club, "University")
    user = user_fixture(%{username: "wannabe"})

    # the form page: the member field, never the guests-only one
    form = conn |> log_in(user) |> get(~p"/c/#{club.uuid}/join") |> html_response(200)
    assert form =~ ~s(id="join-request-form")
    assert form =~ ~s(name="answers[#{uni}]")
    assert form =~ "University"
    refute form =~ "Who invited you"
    refute form =~ ~s(name="message")

    # a missing answer re-renders with the error - no request created
    failed = conn |> log_in(user) |> post(~p"/c/#{club.uuid}/join", %{answers: %{uni => " "}})
    assert html_response(failed, 422) =~ "Fill this in."
    assert Cab.Clubs.list_join_requests(club) == []

    sent = conn |> log_in(user) |> post(~p"/c/#{club.uuid}/join", %{answers: %{uni => "KPI"}})

    assert redirected_to(sent) == "/c/#{club.uuid}"
    assert Phoenix.Flash.get(sent.assigns.flash, :info) =~ "club head will review"
    assert [request] = Cab.Clubs.list_join_requests(club)
    assert Core.Forms.answer_values(request.answers) == %{uni => "KPI"}

    # a second request goes back to the club page with the reason
    again = conn |> log_in(user) |> post(~p"/c/#{club.uuid}/join", %{answers: %{uni => "KPI"}})
    assert redirected_to(again) == "/c/#{club.uuid}"
    assert Phoenix.Flash.get(again.assigns.flash, :error) =~ "already"

    # the owner's members page shows the answers
    owner_html =
      conn |> log_in(head) |> get(~p"/c/#{club.uuid}/owner/members") |> html_response(200)

    assert owner_html =~ "wannabe"
    assert owner_html =~ "University"
    assert owner_html =~ "KPI"

    # once approved they stay with the member, still head-only
    {:ok, _} = Cab.Clubs.approve_join(Cab.Clubs.get_membership(request.id))

    owner_html =
      conn |> log_in(head) |> get(~p"/c/#{club.uuid}/owner/members") |> html_response(200)

    assert owner_html =~ "KPI"

    member_view = conn |> log_in(user) |> get(~p"/c/#{club.uuid}/members") |> html_response(200)
    assert member_view =~ "wannabe"
    refute member_view =~ "KPI"

    public_view = conn |> get(~p"/c/#{club.uuid}") |> html_response(200)
    refute public_view =~ "KPI"

    # anonymous visitors hit the auth wall -> /signin
    anon = get(conn, ~p"/c/#{club.uuid}/join")
    assert redirected_to(anon) == "/signin"
  end

  test "My page: a member edits their saved answers for a club", %{conn: conn, club: club} do
    club =
      form_fields_fixture(club, [
        %{"label" => "University", "type" => "text", "required" => "yes", "scope" => "members"}
      ])

    uni = field_id(club, "University")
    user = user_fixture()
    {:ok, request} = Cab.Clubs.request_join(user, club, %{"answers" => %{uni => "KPI"}})
    {:ok, _} = Cab.Clubs.approve_join(Cab.Clubs.get_membership(request.id))

    Req.Test.stub(Core.Engine, fn req ->
      data =
        if req.request_path in ["/api/users/schedule", "/api/users/history"],
          do: %{"as_adjudicator" => [], "as_player" => []},
          else: nil

      Req.Test.json(req, %{"status" => "success", "data" => data})
    end)

    me = conn |> log_in(user) |> get(~p"/me") |> html_response(200)
    assert me =~ ~s(href="/me/clubs/#{club.uuid}/answers")

    page = conn |> log_in(user) |> get(~p"/me/clubs/#{club.uuid}/answers") |> html_response(200)
    assert page =~ ~s(id="member-answers-form")
    assert page =~ ~s(value="KPI")
    assert page =~ "that session only"

    failed =
      conn |> log_in(user) |> post(~p"/me/clubs/#{club.uuid}/answers", %{answers: %{uni => ""}})

    assert html_response(failed, 422) =~ "Fill this in."

    saved =
      conn
      |> log_in(user)
      |> post(~p"/me/clubs/#{club.uuid}/answers", %{answers: %{uni => "KNU"}})

    assert redirected_to(saved) == "/me"
    membership = Cab.Clubs.membership_of(club, user)
    assert Core.Forms.answer_values(membership.answers) == %{uni => "KNU"}

    # someone else's club: nothing to edit
    other = club_fixture(user_fixture())
    assert conn |> log_in(user) |> get(~p"/me/clubs/#{other.uuid}/answers") |> response(404)
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

    done =
      session_fixture(club,
        engine_event_id: 11,
        name: "Done night",
        finished_at: ~U[2026-10-08 20:00:00Z],
        winner_name: "Winners"
      )

    stub(fn conn, params ->
      case {conn.method, conn.request_path} do
        {"POST", "/api/events/3"} ->
          ok(conn, %{"id" => 12, "name" => params["name"], "status" => "scheduled"})

        {"GET", "/api/events/12/feedback-questions"} ->
          Req.Test.json(conn, %{"status" => "success", "data" => []})

        {"POST", "/api/events/12/feedback-questions"} ->
          Req.Test.json(conn, %{"status" => "success", "data" => %{"id" => 1}})

        {"POST", "/api/events/12/rounds"} ->
          ok(conn, %{"id" => 22, "sequence" => 1})
      end
    end)

    # the club page IS the archive now - public, full list, no form
    member_html =
      conn |> log_in(member) |> get(~p"/c/#{club.uuid}") |> html_response(200)

    assert member_html =~ ~s(id="club-sessions")
    assert member_html =~ "Done night"
    assert member_html =~ ~s(href="/c/#{club.uuid}/s/#{done.uuid}")
    refute member_html =~ ~s(id="open-session-form")
    refute member_html =~ "Open new session"

    # owner path: the archive + open-session form live on /owner now
    owner_html =
      conn |> log_in(head) |> get(~p"/c/#{club.uuid}/owner") |> html_response(200)

    assert owner_html =~ ~s(id="club-sessions")
    assert owner_html =~ ~s(id="open-session-form")
    assert owner_html =~ ~s(form="open-session-form")
    assert owner_html =~ "Open new session"
    # a finished session opens its results, not the head's session page
    assert owner_html =~ ~s(href="/c/#{club.uuid}/s/#{done.uuid}")
    refute owner_html =~ ~s(href="/c/#{club.uuid}/owner/s/#{done.uuid}")

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

    assert [session] = Enum.reject(Cab.Sessions.list_for_club(club), & &1.finished_at)
    assert redirected_to(opened) == "/c/#{club.uuid}/owner/s/#{session.uuid}"
    assert session.engine_event_id == 12
    assert session.scheduled_at == ~U[2026-10-09 18:30:00Z]

    # the old member archive route is gone
    assert conn |> get("/c/#{club.uuid}/member/sessions") |> response(404)
  end

  # ---------------------------------------------------------------
  # Old routes: the M7 member page and the ?tab console are gone
  # ---------------------------------------------------------------

  test "the member tree is gone - v3.1 keeps one URL per view", %{conn: conn, club: club} do
    assert conn |> get("/c/#{club.uuid}/member") |> response(404)
  end

  test "the owner ?tab console is gone - /owner?tab=x is the club edit page", %{
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

  test "a member registers in the club page's section; answers stay with the session", %{
    conn: conn,
    club: club
  } do
    club =
      form_fields_fixture(club, [
        %{"label" => "University", "type" => "text", "required" => "yes", "scope" => "members"},
        %{"label" => "Who invited you", "type" => "text", "required" => "no", "scope" => "guests"}
      ])

    uni = field_id(club, "University")
    member = user_fixture(%{node_user_id: 44})
    {:ok, request} = Cab.Clubs.request_join(member, club, %{"answers" => %{uni => "KPI"}})
    {:ok, _} = Cab.Clubs.approve_join(Cab.Clubs.get_membership(request.id))
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

    # the session page's gold Register segment -> the club page section
    page =
      conn |> log_in(member) |> get(~p"/c/#{club.uuid}/s/#{session.uuid}") |> html_response(200)

    assert page =~ "Register"
    assert page =~ "/c/#{club.uuid}?session=#{session.uuid}#register"

    # the section, signed in as a member: the member fields prefilled
    # from the saved answers, no name, no guests-only field
    html = conn |> log_in(member) |> get(~p"/c/#{club.uuid}") |> html_response(200)

    assert html =~ ~s(id="register-form")
    assert html =~ ~s(name="answers[#{uni}]")
    assert html =~ ~s(value="KPI")
    assert html =~ "this session only"
    refute html =~ "Who invited you"
    refute html =~ ~s(name="name")
    # the section's Register is the gold action; Request to join is not shown to members
    refute html =~ ~s(class="item">Register<)
    assert html =~ ~s(href="/c/#{club.uuid}/members")

    head_html =
      conn
      |> log_in(Cab.Clubs.head_of(club))
      |> get(~p"/c/#{club.uuid}")
      |> html_response(200)

    assert head_html =~ ~s(href="/c/#{club.uuid}/owner/members")

    # a refused answer re-renders the section with the error
    failed =
      conn
      |> log_in(member)
      |> post(~p"/c/#{club.uuid}/register", %{
        "session" => session.uuid,
        "answers" => %{uni => ""}
      })

    assert html_response(failed, 422) =~ "Fill this in."

    registered =
      conn
      |> log_in(member)
      |> post(~p"/c/#{club.uuid}/register", %{
        "session" => session.uuid,
        "answers" => %{uni => "KNU"}
      })

    assert redirected_to(registered) == "/c/#{club.uuid}?session=#{session.uuid}#register"
    assert Phoenix.Flash.get(registered.assigns.flash, :info) =~ "registered"

    # this session's answer is KNU; the saved default stays KPI
    assert [registration] = Cab.Registrations.for_session(session)
    assert Core.Forms.answer_values(registration.answers) == %{uni => "KNU"}
    assert registration.engine_participant_id == 41
    saved = Cab.Clubs.membership_of(club, member)
    assert Core.Forms.answer_values(saved.answers) == %{uni => "KPI"}

    # the head's Responses lists the member with this session's answer
    responses =
      conn
      |> log_in(Cab.Clubs.head_of(club))
      |> get(~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/responses")
      |> html_response(200)

    assert responses =~ "KNU"
    refute responses =~ "KPI"
  end

  test "the section says where things stand: registered, running", %{conn: conn, club: club} do
    member = user_fixture(%{node_user_id: 44})
    membership_fixture(member, club)
    session = session_fixture(club, engine_event_id: 11)

    stub(fn conn, _params ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/events/11"} -> ok(conn, %{"id" => 11, "status" => "scheduled"})
        {"GET", "/api/events/11/rounds"} -> ok(conn, [%{"id" => 21, "sequence" => 1}])
        {"GET", "/api/events/11/participants"} -> ok(conn, [%{"id" => 41, "user_id" => 44}])
        _other -> ok(conn, [])
      end
    end)

    html = conn |> log_in(member) |> get(~p"/c/#{club.uuid}") |> html_response(200)
    # registered for the only open session: the section says so, no
    # buttons - cancelling and opening are the table's
    assert html =~ "You are registered for every session open for registration:"
    assert html =~ "Cancel or open them in Club Sessions below."
    refute html =~ "Register for another session"
    assert html =~ "/c/#{club.uuid}/s/#{session.uuid}/signups/41/remove?from=club"
    refute html =~ ~s(id="register-form")
    # the Club Sessions table: status in words, the viewer's action
    assert html =~ "registration open"
    assert html =~ "Cancel registration"

    Cab.Repo.update!(Ecto.Changeset.change(session, started_at: ~U[2026-10-22 18:00:00Z]))

    running = conn |> get(~p"/c/#{club.uuid}") |> html_response(200)
    assert running =~ "The session is running."
    # a running session's row opens it
    assert running =~ ~s(href="/c/#{club.uuid}/s/#{session.uuid}" class="btn-quiet btn-sm")
    refute running =~ ~s(id="guest-register-form")
  end

  test "a signed-in non-member is asked the guest fields without the e-mail", %{
    conn: conn,
    club: club
  } do
    club =
      form_fields_fixture(club, [
        %{"label" => "University", "type" => "text", "required" => "yes", "scope" => "members"},
        %{
          "label" => "Who invited you",
          "type" => "text",
          "required" => "yes",
          "scope" => "guests"
        }
      ])

    who = field_id(club, "Who invited you")
    outsider = user_fixture(%{node_user_id: 45})
    session = session_fixture(club, engine_event_id: 11)

    stub(fn conn, _params ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/events/11"} -> ok(conn, %{"id" => 11, "status" => "scheduled"})
        {"GET", "/api/events/11/rounds"} -> ok(conn, [%{"id" => 21, "sequence" => 1}])
        {"GET", "/api/events/11/participants"} -> ok(conn, [])
        {"GET", "/api/rounds/21/rooms"} -> ok(conn, [])
        {"POST", "/api/events/11/participants"} -> ok(conn, %{"id" => 42, "role" => "speaker"})
        _other -> ok(conn, [])
      end
    end)

    html = conn |> log_in(outsider) |> get(~p"/c/#{club.uuid}") |> html_response(200)
    assert html =~ ~s(id="register-form")
    assert html =~ ~s(name="answers[#{who}]")
    refute html =~ ~s(name="answers[email]")
    refute html =~ "University"

    registered =
      conn
      |> log_in(outsider)
      |> post(~p"/c/#{club.uuid}/register", %{
        "session" => session.uuid,
        "answers" => %{who => "Anna"}
      })

    assert redirected_to(registered) == "/c/#{club.uuid}?session=#{session.uuid}#register"
    assert [registration] = Cab.Registrations.for_session(session)
    assert registration.user_id == outsider.id
    assert Core.Forms.answer_values(registration.answers) == %{who => "Anna"}
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

        {"PUT", "/api/events/11/participants/" <> _renamed} ->
          Req.Test.json(conn, %{"status" => "success", "data" => %{}})

        {"DELETE", "/api/events/11/participants/41"} ->
          send(test_pid, :removed)
          Req.Test.json(conn, %{"status" => "success", "message" => "Participant archived."})
      end
    end)

    closed_page =
      conn
      |> log_in(member)
      |> get(~p"/c/#{club.uuid}")
      |> html_response(200)

    assert closed_page =~ "closed"

    cancelled =
      conn
      |> log_in(member)
      |> post(~p"/c/#{club.uuid}/s/#{session.uuid}/signups/41/remove")

    assert redirected_to(cancelled) == "/c/#{club.uuid}/s/#{session.uuid}"
    assert Phoenix.Flash.get(cancelled.assigns.flash, :info) =~ "Registration cancelled."
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

    # stage words in the crumb, chrome actions for :signup only:
    # the ONE gold action is Start session, submitting the allocator
    assert html =~ "registration open"
    assert html =~ "Start session"
    refute html =~ "Close sign-ups"
    refute html =~ "Cancel session"
    refute html =~ "Reopen sign-ups"
    refute html =~ "Delete rooms"

    # registration: the shared URL; one people table; one add form
    # (member or guest); rooms: the allocator - all ONE page now
    assert html =~ ~s(id="shared-registration-url")
    assert html =~ ~s(id="session-people")
    assert html =~ "/c/#{club.uuid}/owner/sessions/#{session.uuid}/signups/1/remove"
    assert html =~ ~s(id="add-person-form")
    # before anything is typed, every member not in the session yet
    # waits in the dropdown, one click away
    assert html =~ ~s(class="suggest idle")
    assert html =~ ~s(phx-click="add_member")
    assert html =~ "benched"

    # the EMBEDDED allocator: automatic room count, EMPTY slots -
    # nobody is ever placed automatically
    assert html =~ ~s(id="allocator-form" phx-submit="start")
    assert html =~ ~s(phx-hook="Allocator")
    assert html =~ "count automatic"

    # the owner surface is owner-tree only
    assert_error_sent 403, fn ->
      conn |> log_in(member) |> get(~p"/c/#{club.uuid}/owner/s/#{session.uuid}")
    end
  end

  test "owner surface at :closed: allocator + Start session + Reopen registration; lifecycle twins redirect back",
       %{conn: conn, club: club, head: head} do
    session = closed_session_fixture(club, engine_event_id: 11)
    stub_signup_stage(signup_stage_signups())

    html =
      conn
      |> log_in(head)
      |> get(~p"/c/#{club.uuid}/owner/s/#{session.uuid}")
      |> html_response(200)

    # the allocator is embedded here too; Start session submits it
    assert html =~ "Start session"
    assert html =~ ~s(id="allocator-form")
    assert html =~ ~s(phx-submit="make_rooms")
    assert html =~ "Reopen registration"
    assert html =~ "registration closed"
    refute html =~ "Close sign-ups"
    refute html =~ "Compose rooms"

    reopened =
      conn
      |> log_in(head)
      |> post(~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/reopen-signups")

    assert redirected_to(reopened) == "/c/#{club.uuid}/owner/s/#{session.uuid}"
    assert Phoenix.Flash.get(reopened.assigns.flash, :info) =~ "Registration reopened."

    closed =
      conn
      |> log_in(head)
      |> post(~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/close-signups")

    assert redirected_to(closed) == "/c/#{club.uuid}/owner/s/#{session.uuid}"

    bounced =
      conn
      |> log_in(head)
      |> post(~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/close-signups")

    assert Phoenix.Flash.get(bounced.assigns.flash, :error) =~ "only be closed while it is open"
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

        {"PUT", "/api/events/11/participants/" <> _renamed} ->
          Req.Test.json(conn, %{"status" => "success", "data" => %{}})

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
        q: "benched"
      })

    assert redirected_to(added) == "/c/#{club.uuid}/owner/s/#{session.uuid}"
    assert Phoenix.Flash.get(added.assigns.flash, :info) =~ "benched"
    assert_received {:added, %{"user_id" => 444, "role" => "speaker"}}

    removed =
      conn
      |> log_in(head)
      |> post(~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/signups/3/remove")

    assert redirected_to(removed) == "/c/#{club.uuid}/owner/s/#{session.uuid}"
    assert Phoenix.Flash.get(removed.assigns.flash, :info) =~ "Registration removed."
    assert_received :removed
  end

  # ---------------------------------------------------------------
  # The embedded allocator (dnd) - Start session consumes its state
  # ---------------------------------------------------------------

  test "the allocator is the dnd table; Start session posts the composition", %{
    conn: conn,
    club: club,
    head: head
  } do
    session = session_fixture(club, engine_event_id: 11)
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
      |> get(~p"/c/#{club.uuid}/owner/s/#{session.uuid}")
      |> html_response(200)

    # the allocator: a tray of draggable chips over keyed slots the
    # server fills from its draft - NO dropdowns anywhere, slots EMPTY
    assert html =~ ~s(phx-hook="Allocator")
    assert html =~ ~s(data-drop="tray")
    assert html =~ ~s(draggable="true")
    refute html =~ "data-kind"
    assert html =~ "Speaker 8"
    assert html =~ ~s(data-slot="1:og:1")
    assert html =~ ~s(data-slot="1:co:2")
    assert html =~ ~s(data-slot="1:judge")
    refute html =~ "<select"

    # the submit segment is the chrome's one gold action; the room
    # count is automatic - 8 speakers = 1 room, no "+ room" anywhere
    assert html =~ ~s(form="allocator-form")
    assert html =~ "Start session"
    refute html =~ "+ room"
    refute html =~ ~s(data-slot="2:og:1")

    # the count is ceiling-based - 13 speakers and a judge open 2 rooms
    fourteen = for i <- 1..14, do: %{"role" => "speaker", "id" => i}
    assert Cab.Sessions.room_count(fourteen) == 2
    assert Cab.Sessions.room_count([%{"role" => "speaker", "id" => 1}]) == 1

    # an impossible composition bounces back with the reason and the
    # window ROLLS BACK open - the session stays at :signup
    bounced =
      conn
      |> log_in(head)
      |> post(~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/start", %{
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
    assert Phoenix.Flash.get(bounced.assigns.flash, :error) =~ "placed in two seats"
    assert Cab.Sessions.get_for_club(club, session.uuid).signups_closed_at == nil

    # the dnd slots post rooms[i][side][slot] (+ judge); empty slots
    # post "" - an iron team is a single filled slot. Start closes
    # registration and makes exactly these rooms.
    posted =
      conn
      |> log_in(head)
      |> post(~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/start", %{
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
    assert Phoenix.Flash.get(posted.assigns.flash, :info) =~ "Session started with 1 room(s)."
    assert_received {:room, room_params}

    assert [
             %{"participant_ids" => [7, 8], "position" => 1},
             %{"participant_ids" => [3, 4], "position" => 2},
             %{"participant_ids" => [5, 6], "position" => 3},
             %{"participant_ids" => [1], "position" => 4}
           ] = room_params["teams"]

    assert Cab.Sessions.get_for_club(club, session.uuid).signups_closed_at != nil

    # starting is owner-tree only - a member gets 403
    member = user_fixture(%{node_user_id: 55})
    membership_fixture(member, club)

    denied =
      conn |> log_in(member) |> post(~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/start")

    assert response(denied, 403)
  end

  test "start without a dragged allocation errors - nothing is auto-placed",
       %{conn: conn, club: club, head: head} do
    session = session_fixture(club, engine_event_id: 11)
    stub_signup_stage(signup_stage_signups())

    bounced =
      conn
      |> log_in(head)
      |> post(~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/start")

    assert redirected_to(bounced) == "/c/#{club.uuid}/owner/s/#{session.uuid}"

    assert Phoenix.Flash.get(bounced.assigns.flash, :error) =~
             "Nobody is placed automatically"

    assert Cab.Sessions.get_for_club(club, session.uuid).signups_closed_at == nil
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
        {"GET", "/api/events/11/feedback"} ->
          ok(conn, [])

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

        {"POST", "/api/rooms/71/motion"} ->
          ok(conn, %{})

        {"PATCH", "/api/rooms/71/prep"} ->
          if test_pid, do: send(test_pid, {:prep, params["prep_ends_at"]})
          ok(conn, %{})
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
          send(test_pid, {:motion, params["motion_text"], params["infoslide"], params["keyword"]})
          ok(conn, %{"motion" => %{"motion_text" => params["motion_text"]}})

        {"PATCH", "/api/rooms/71/prep"} ->
          send(test_pid, {:prep, params["prep_ends_at"]})
          ok(conn, %{})
      end
    end)

    # anonymous: the draw and the honest "not set yet" - no form
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
    assert chair_html =~ "Infoslide"
    assert chair_html =~ "Keyword"
    assert chair_html =~ "Publish motion"
    assert chair_html =~ "starts 15 minutes of prep"
    # the chrome's Publish motion is the form's only button
    refute chair_html =~ ~s(class="btn-quiet")
    refute chair_html =~ ~s(class="btn-go")
    assert chair_html =~ ~s(form="room-motion-71")

    set =
      conn
      |> log_in(judge)
      |> post(~p"/c/#{club.uuid}/s/#{session.uuid}/rooms/71/motion", %{
        motion_text: "THW debate",
        infoslide: "Context slide",
        keyword: "economy"
      })

    assert redirected_to(set) == "/c/#{club.uuid}/s/#{session.uuid}/rooms/71"
    assert_received {:motion, "THW debate", "Context slide", "economy"}

    # publishing set prep to end 15 minutes from now, in the engine
    assert_received {:prep, ends_at}
    {:ok, ends_at, _} = DateTime.from_iso8601(ends_at)
    assert_in_delta DateTime.diff(ends_at, DateTime.utc_now()), 900, 5

    # a plain member is neither chair nor head - no motion for them
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

  test "the prep end: the same time keeps it, a new time moves it, empty means 15 minutes",
       %{conn: conn, club: club, head: head} do
    session = session_fixture(club, engine_event_id: 11)
    ends = DateTime.add(DateTime.utc_now(:second), 1800, :second)
    # the engine holds the room's prep end
    stub_running_session(
      Map.put(running_room(44), "prep_ends_at", DateTime.to_iso8601(ends)),
      self()
    )

    path = ~p"/c/#{club.uuid}/s/#{session.uuid}/rooms/71/motion"

    post_motion = fn prep ->
      conn |> log_in(head) |> post(path, %{motion_text: "THW x", prep_until: prep})
    end

    # the time shown, sent back unchanged (seconds dropped by the field): kept
    post_motion.(ends |> Map.put(:second, 0) |> DateTime.to_iso8601())
    refute_received {:prep, _}

    # a new time moves it
    later = DateTime.add(ends, 600, :second) |> Map.put(:second, 0)
    post_motion.(DateTime.to_iso8601(later))
    assert_received {:prep, moved}
    assert {:ok, ^later, _} = DateTime.from_iso8601(moved)

    # left empty (as for a motion from before the timer): 15 minutes from now
    post_motion.("")
    assert_received {:prep, fresh}
    {:ok, fresh, _} = DateTime.from_iso8601(fresh)
    assert_in_delta DateTime.diff(fresh, DateTime.utc_now()), 900, 5
  end

  test "once the ballot is in, the room shows each speaker's points, team points and place",
       %{conn: conn, club: club} do
    session = session_fixture(club, engine_event_id: 11)

    scored =
      running_room(44)
      |> Map.put("status", "confirmed")
      |> update_in(["RoomTeams"], fn teams ->
        Enum.map(teams, fn team ->
          speakers =
            Enum.map(team["RoomSpeakers"], fn rs ->
              Map.put(rs, "Scores", [%{"value" => "#{70 + team["position"]}.00"}])
            end)

          # CO is an iron: one speaker twice, the second speech unflagged
          speakers =
            if team["position"] == 4,
              do: Enum.map(speakers, &put_in(&1, ["EventParticipant", "id"], 307)),
              else: speakers

          Map.merge(team, %{"RoomSpeakers" => speakers, "rank" => 5 - team["position"]})
        end)
      end)

    stub_running_session(scored)

    html =
      conn
      |> get(~p"/c/#{club.uuid}/s/#{session.uuid}/rooms/71")
      |> html_response(200)

    assert html =~ ~s(<b class="pts">71</b>)
    assert html =~ ~s(<b class="pts">74</b>)
    # team points: two speeches of 74 for CO
    assert html =~ "148"
    assert html =~ "1st"
    assert html =~ "(iron)"
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

  test "a head opening an unfinished session's page lands on the Rooms page",
       %{conn: conn, club: club, head: head} do
    session = session_fixture(club, engine_event_id: 11)

    page = conn |> log_in(head) |> get(~p"/c/#{club.uuid}/s/#{session.uuid}")
    assert redirected_to(page) == "/c/#{club.uuid}/owner/s/#{session.uuid}"
  end

  test "no motion, no ballot: links stay hidden and the ballot page sends you to the room",
       %{conn: conn, club: club, head: head} do
    session = session_fixture(club, engine_event_id: 11)
    stub_running_session(Map.put(running_room(9), "Motion", nil))

    rooms =
      conn
      |> log_in(head)
      |> get(~p"/c/#{club.uuid}/owner/s/#{session.uuid}")
      |> html_response(200)

    refute rooms =~ "/rooms/71/ballot"
    refute rooms =~ "Fill ballot"
    assert rooms =~ "not published yet"

    ballot = conn |> log_in(head) |> get(~p"/c/#{club.uuid}/s/#{session.uuid}/rooms/71/ballot")
    assert redirected_to(ballot) == "/c/#{club.uuid}/s/#{session.uuid}/rooms/71"
    assert Phoenix.Flash.get(ballot.assigns.flash, :error) =~ "Publish the room's motion first"
  end

  test "a head who chairs a room gets Fill ballot on the Rooms page too",
       %{conn: conn, club: club, head: head} do
    session = session_fixture(club, engine_event_id: 11)
    stub_running_session(running_room(9))

    html =
      conn
      |> log_in(head)
      |> get(~p"/c/#{club.uuid}/owner/s/#{session.uuid}")
      |> html_response(200)

    assert html =~ "Fill ballot"
    assert html =~ "/c/#{club.uuid}/s/#{session.uuid}/rooms/71/ballot"
    # the whole room row opens the room page
    assert html =~ ~s(data-href="/c/#{club.uuid}/s/#{session.uuid}/rooms/71")

    # the motions table: each room's motion, infoslide and keyword
    assert html =~ ~s(id="session-motions")
    assert html =~ "THW fill ballots"
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
    # R# opens the room page
    assert show =~ ~s(href="/c/#{club.uuid}/s/#{session.uuid}/rooms/71")
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

    # the owner tree stays owner-only for members...
    denied = conn |> log_in(member) |> get(~p"/c/#{club.uuid}/s/#{session.uuid}/rooms/71/ballot")
    assert response(denied, 403)

    # ...but the ladder lets a platform admin (no membership) through
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

        {"GET", "/api/events/11/feedback"} ->
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
    assert html =~ "/c/#{club.uuid}/owner/sessions/#{session.uuid}/reopen-registration"
    refute html =~ "edit ballot"

    deleted =
      conn
      |> log_in(head)
      |> post(~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/rooms/delete")

    assert redirected_to(deleted) == "/c/#{club.uuid}/owner/s/#{session.uuid}"
    assert Phoenix.Flash.get(deleted.assigns.flash, :info) =~ "1 room(s) deleted"
    assert_received :room_deleted

    # confirmed room: no delete segment, an edit ballot link instead
    # (lock/unlock stays internal - the page never says it)
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

        {"GET", "/api/events/11/feedback"} ->
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
    assert html =~ "ballot confirmed"
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

  test "session cancel lands on the archive; finish lands on the session page; a finished session stays",
       %{conn: conn, club: club, head: head} do
    session = session_fixture(club, engine_event_id: 11)
    spare = session_fixture(club, engine_event_id: 12)
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

        {"GET", "/api/events/12"} ->
          ok(conn, %{"id" => 12, "name" => "Spare", "status" => "scheduled"})

        {"GET", "/api/events/12/rounds"} ->
          ok(conn, [%{"id" => 22, "sequence" => 1}])

        {"GET", "/api/events/12/participants"} ->
          ok(conn, [])

        {"GET", "/api/rounds/22/rooms"} ->
          ok(conn, [])

        {"DELETE", "/api/events/12"} ->
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

    refused =
      conn
      |> log_in(head)
      |> post(~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/cancel")

    assert redirected_to(refused) == "/c/#{club.uuid}/owner/s/#{session.uuid}"
    assert Phoenix.Flash.get(refused.assigns.flash, :error) =~ "cannot be cancelled"

    # the empty spare: the page offers Delete (quiet), the confirm
    # step asks, the delete goes through
    page =
      conn
      |> log_in(head)
      |> get(~p"/c/#{club.uuid}/owner/s/#{spare.uuid}")
      |> html_response(200)

    delete_path = "/c/#{club.uuid}/owner/sessions/#{spare.uuid}/delete"
    assert [tag] = Regex.run(~r/<a[^>]*href="#{delete_path}"[^>]*>/, page)
    assert tag =~ ~s(class="quiet")

    confirm = conn |> log_in(head) |> get(delete_path) |> html_response(200)
    assert confirm =~ "Delete Spare?"
    assert confirm =~ ~s(action="/c/#{club.uuid}/owner/sessions/#{spare.uuid}/cancel")
    assert confirm =~ ~s(class="btn-quiet")
    refute confirm =~ ~s(class="btn-go")

    cancelled =
      conn
      |> log_in(head)
      |> post(~p"/c/#{club.uuid}/owner/sessions/#{spare.uuid}/cancel")

    assert redirected_to(cancelled) == "/c/#{club.uuid}/owner"
    assert Phoenix.Flash.get(cancelled.assigns.flash, :info) == "Session deleted."
    assert_received :event_deleted
    assert Enum.map(Cab.Sessions.list_for_club(club), & &1.uuid) == [session.uuid]
  end

  test "a session somebody signed up for offers no delete and refuses it",
       %{conn: conn, club: club, head: head} do
    session = session_fixture(club, engine_event_id: 11, name: "Night")

    stub(fn conn, _params ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/events/11"} ->
          ok(conn, %{"id" => 11, "name" => "Night", "status" => "scheduled"})

        {"GET", "/api/events/11/rounds"} ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        {"GET", "/api/events/11/participants"} ->
          ok(conn, [%{"id" => 41, "role" => "speaker", "display_name" => "Ann"}])

        {"GET", "/api/rounds/21/rooms"} ->
          ok(conn, [])

        {"GET", "/api/events/organisation/3"} ->
          ok(conn, [])
      end
    end)

    page =
      conn
      |> log_in(head)
      |> get(~p"/c/#{club.uuid}/owner/s/#{session.uuid}")
      |> html_response(200)

    refute page =~ "/owner/sessions/#{session.uuid}/delete"

    back = "/c/#{club.uuid}/owner/s/#{session.uuid}"

    confirm =
      conn |> log_in(head) |> get(~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/delete")

    assert redirected_to(confirm) == back
    assert Phoenix.Flash.get(confirm.assigns.flash, :error) =~ "People signed up"

    refused =
      conn
      |> log_in(head)
      |> post(~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/cancel")

    assert redirected_to(refused) == back
    assert Phoenix.Flash.get(refused.assigns.flash, :error) =~ "People signed up"
    assert Cab.Sessions.get_by_uuid(session.uuid)
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
