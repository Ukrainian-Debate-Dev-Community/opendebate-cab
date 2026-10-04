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

  test "public session detail page: name/date, stage, rooms, motions, ranks, winner",
       %{conn: conn, club: club} do
    session =
      session_fixture(club, engine_event_id: 11, scheduled_at: ~U[2026-10-09 18:30:00Z])

    room = %{
      "id" => 71,
      "status" => "confirmed",
      "Motion" => %{"motion_text" => "THW publish results"},
      "RoomTeams" =>
        for {position, rank} <- [{1, 2}, {2, 1}, {3, 3}, {4, 4}] do
          %{
            "id" => 100 + position,
            "position" => position,
            "rank" => rank,
            "Team" => %{"name" => "Team #{position}"},
            "RoomSpeakers" =>
              for n <- [1, 2] do
                %{
                  "id" => 200 + position * 2 + n,
                  "EventParticipant" => %{
                    "id" => 300 + position * 2 + n,
                    "display_name" => "Speaker #{position}.#{n}"
                  }
                }
              end
          }
        end
    }

    stub(fn conn, _params ->
      case conn.request_path do
        "/api/events/organisation/3" ->
          ok(conn, [%{"id" => 11, "name" => "Walk night", "status" => "completed"}])

        "/api/events/11" ->
          ok(conn, %{"id" => 11, "name" => "Walk night", "status" => "completed"})

        "/api/events/11/rounds" ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        "/api/events/11/participants" ->
          ok(conn, [])

        "/api/rounds/21/rooms" ->
          ok(conn, [room])
      end
    end)

    # public — no login
    html = conn |> get(~p"/c/#{club.uuid}/s/#{session.uuid}") |> html_response(200)

    assert html =~ "Walk night"
    assert html =~ "9 Oct 2026 · 18:30"
    assert html =~ ~s(class="stage off")
    assert html =~ "THW publish results"
    assert html =~ "Team 2"
    assert html =~ "Speaker 2.1 &amp; Speaker 2.2"
    assert html =~ "Winner: <b>Team 2</b>"
    assert html =~ "2nd"
    assert html =~ "4th"

    # the public club history row links here
    club_html = conn |> get(~p"/c/#{club.uuid}") |> html_response(200)
    assert club_html =~ "/c/#{club.uuid}/s/#{session.uuid}"

    # a foreign session uuid under this club is a 404
    other_club = club_fixture(user_fixture(%{node_user_id: 10}), %{engine_organisation_id: 4})
    foreign = session_fixture(other_club, engine_event_id: 12)
    assert conn |> get(~p"/c/#{club.uuid}/s/#{foreign.uuid}") |> response(404)
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

  test "browser join request posts the HTML twin and lands back with a flash",
       %{conn: conn, club: club} do
    user = user_fixture()

    stub(fn conn, _params ->
      case conn.request_path do
        "/api/events/organisation/3" -> ok(conn, [])
      end
    end)

    # the public page's gold segment points at the in-tree twin
    html = conn |> log_in(user) |> get(~p"/c/#{club.uuid}") |> html_response(200)
    assert html =~ ~s(href="/c/#{club.uuid}/join")
    refute html =~ "/api/v1/clubs"

    sent = conn |> log_in(user) |> post(~p"/c/#{club.uuid}/join")
    assert redirected_to(sent) == "/c/#{club.uuid}"
    assert Phoenix.Flash.get(sent.assigns.flash, :info) =~ "club head will approve"
    assert [request] = Cab.Clubs.list_join_requests(club)
    assert request.user_id == user.id

    # a duplicate is still a redirect + flash, never JSON
    dup = conn |> log_in(user) |> post(~p"/c/#{club.uuid}/join")
    assert redirected_to(dup) == "/c/#{club.uuid}"
    assert Phoenix.Flash.get(dup.assigns.flash, :error) =~ "already a member or pending"

    # anonymous visitors have no join action
    anon =
      conn
      |> Plug.Conn.put_private(:plug_skip_csrf_protection, true)
      |> post(~p"/c/#{club.uuid}/join")

    assert response(anon, 403)
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

    conn =
      conn
      |> log_in(head)
      |> post(~p"/c/#{club.uuid}/owner/sessions", %{
        name: "Tuesday",
        date: "2026-10-09",
        time: "18:30"
      })

    assert redirected_to(conn) == "/c/#{club.uuid}/owner"
    assert [session] = Cab.Sessions.list_for_club(club)
    assert session.engine_event_id == 11
    assert session.scheduled_at == ~U[2026-10-09 18:30:00Z]
    assert session.signups_closed_at == nil
  end

  defp stub_empty_signup_stage do
    stub(fn conn, _params ->
      case conn.request_path do
        "/api/events/11" -> ok(conn, %{"id" => 11, "status" => "scheduled"})
        "/api/events/11/rounds" -> ok(conn, [%{"id" => 21, "sequence" => 1}])
        "/api/events/11/participants" -> ok(conn, [])
        "/api/rounds/21/rooms" -> ok(conn, [])
      end
    end)
  end

  test "member registers via the form page", %{conn: conn, club: club} do
    member = user_fixture(%{node_user_id: 44})
    membership_fixture(member, club)
    session = session_fixture(club, engine_event_id: 11)

    stub(fn conn, params ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/events/11"} ->
          ok(conn, %{"id" => 11, "status" => "scheduled"})

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

    # the registration form: role pills, one POST
    html =
      conn
      |> log_in(member)
      |> get(~p"/c/#{club.uuid}/member/sessions/#{session.uuid}/register")
      |> html_response(200)

    assert html =~ ~s(id="register-form")
    assert html =~ "Speaker"
    assert html =~ "Judge"
    assert html =~ ~s(name="as")

    conn =
      conn
      |> log_in(member)
      |> post(~p"/c/#{club.uuid}/member/sessions/#{session.uuid}/signups", %{as: "speak"})

    assert redirected_to(conn) == "/c/#{club.uuid}/member"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "registered"
  end

  test "member page: ONE gold Register segment while :signup — the twin segs are gone",
       %{conn: conn, club: club} do
    member = user_fixture(%{node_user_id: 44})
    membership_fixture(member, club)
    session = session_fixture(club, engine_event_id: 11)
    stub_empty_signup_stage()

    html = conn |> log_in(member) |> get(~p"/c/#{club.uuid}/member") |> html_response(200)

    # the single registration entry, a gold chrome segment
    assert html =~ "Register"
    assert html =~ "/c/#{club.uuid}/member/sessions/#{session.uuid}/register"
    assert html =~ ~s(class="stage ok")
    assert html =~ "sign-up open"

    # the M4 twin segs are GONE
    refute html =~ "I speak tonight"
    refute html =~ "I judge"
    refute html =~ "signups?as="

    # member templates never reference owner segments
    refute html =~ "Make rooms"
    refute html =~ "Open session"
    refute html =~ "Finish session"
    refute html =~ "/owner"
  end

  test "registered member sees their role + Cancel my registration",
       %{conn: conn, club: club} do
    member = user_fixture(%{node_user_id: 44})
    membership_fixture(member, club)
    session = session_fixture(club, engine_event_id: 11)
    test_pid = self()

    stub(fn conn, _params ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/events/11"} ->
          ok(conn, %{"id" => 11, "status" => "scheduled"})

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

    html = conn |> log_in(member) |> get(~p"/c/#{club.uuid}/member") |> html_response(200)

    assert html =~ "You are registered to speak tonight."
    assert html =~ "Cancel my registration"
    assert html =~ "/c/#{club.uuid}/member/sessions/#{session.uuid}/signups/41/remove"
    refute html =~ "/member/sessions/#{session.uuid}/register"

    cancelled =
      conn
      |> log_in(member)
      |> post(~p"/c/#{club.uuid}/member/sessions/#{session.uuid}/signups/41/remove")

    assert redirected_to(cancelled) == "/c/#{club.uuid}/member"
    assert Phoenix.Flash.get(cancelled.assigns.flash, :info) =~ "registration cancelled"
    assert_received :removed
  end

  test "member page while :closed: registration closed notice, no Register segment",
       %{conn: conn, club: club} do
    member = user_fixture(%{node_user_id: 44})
    membership_fixture(member, club)
    session = closed_session_fixture(club, engine_event_id: 11)
    stub_empty_signup_stage()

    html = conn |> log_in(member) |> get(~p"/c/#{club.uuid}/member") |> html_response(200)

    assert html =~ "Registration is closed for this session."
    assert html =~ "sign-ups closed"
    refute html =~ "/member/sessions/#{session.uuid}/register"

    # the register page itself bounces back
    bounced =
      conn
      |> log_in(member)
      |> get(~p"/c/#{club.uuid}/member/sessions/#{session.uuid}/register")

    assert redirected_to(bounced) == "/c/#{club.uuid}/member"
    assert Phoenix.Flash.get(bounced.assigns.flash, :error) =~ "closed"
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
        {"GET", "/api/events/11"} ->
          ok(conn, %{"id" => 11, "status" => "scheduled"})

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
          "MG" => %{"speaker" => "305", "score" => "74.5"},
          "GW" => %{"speaker" => "306", "score" => "75"}
        },
        "co" => %{
          "MO" => %{"speaker" => "307", "score" => "72.5"},
          "OW" => %{"speaker" => "308", "score" => "75"}
        }
      }
    }
  end

  test "the room judge sees Fill ballot and gets the ballot page in the member tree",
       %{conn: conn, club: club} do
    judge = user_fixture(%{node_user_id: 44})
    membership_fixture(judge, club)
    session_fixture(club, engine_event_id: 11)
    stub_running_session(running_room(44))

    home = conn |> log_in(judge) |> get(~p"/c/#{club.uuid}/member") |> html_response(200)
    assert home =~ "Fill ballot"
    assert home =~ "/c/#{club.uuid}/member/rooms/71/ballot"

    html =
      conn
      |> log_in(judge)
      |> get(~p"/c/#{club.uuid}/member/rooms/71/ballot")
      |> html_response(200)

    # the kit's scored ballot, prefilled from the room
    assert html =~ ~s(class="ballot")
    assert html =~ "THW fill ballots"
    assert html =~ ~s(name="ballot[og][PM][speaker]")
    assert html =~ "Speaker 1.1"
    assert html =~ "Team 4"
    # submit is the chrome's gold segment driving the ballot form
    assert html =~ "Submit ballot"
    assert html =~ ~s(form="ballot-71")
    assert html =~ ~s(class="go")
    assert html =~ ~s(action="/c/#{club.uuid}/member/rooms/71/ballot")
  end

  test "a member who is not the room judge gets no ballot page", %{conn: conn, club: club} do
    speaker = user_fixture(%{node_user_id: 55})
    membership_fixture(speaker, club)
    session_fixture(club, engine_event_id: 11)
    stub_running_session(running_room(44))

    home = conn |> log_in(speaker) |> get(~p"/c/#{club.uuid}/member") |> html_response(200)
    refute home =~ "Fill ballot"

    conn = conn |> log_in(speaker) |> get(~p"/c/#{club.uuid}/member/rooms/71/ballot")
    assert response(conn, 403)
  end

  test "the owner tree serves the same ballot per open room", %{
    conn: conn,
    club: club,
    head: head
  } do
    member = user_fixture(%{node_user_id: 55})
    membership_fixture(member, club)
    session_fixture(club, engine_event_id: 11)
    stub_running_session(running_room(44))

    show = conn |> log_in(head) |> get(~p"/c/#{club.uuid}/owner") |> html_response(200)
    assert show =~ "/c/#{club.uuid}/owner/rooms/71/ballot"
    refute show =~ "Record winner"

    html =
      conn |> log_in(head) |> get(~p"/c/#{club.uuid}/owner/rooms/71/ballot") |> html_response(200)

    assert html =~ ~s(class="ballot")
    assert html =~ ~s(action="/c/#{club.uuid}/owner/rooms/71/ballot")

    # the owner tree stays owner-only
    conn = conn |> log_in(member) |> get(~p"/c/#{club.uuid}/owner/rooms/71/ballot")
    assert response(conn, 403)
  end

  test "ballot POST redirects with a flash; a tie re-renders amber", %{conn: conn, club: club} do
    judge = user_fixture(%{node_user_id: 44})
    membership_fixture(judge, club)
    session_fixture(club, engine_event_id: 11)
    stub_running_session(running_room(44), self())

    # og total 151 == oo total 151 -> amber re-render naming the total
    tied =
      conn
      |> log_in(judge)
      |> post(~p"/c/#{club.uuid}/member/rooms/71/ballot", ballot_params(["76", "75"]))

    assert html_response(tied, 422) =~ "share the total 151"
    assert html_response(tied, 422) =~ ~s(class="bsum tied")
    refute_received {:scores, _params}

    done =
      conn
      |> log_in(judge)
      |> post(~p"/c/#{club.uuid}/member/rooms/71/ballot", ballot_params(["78", "75.5"]))

    assert redirected_to(done) == "/c/#{club.uuid}/member"
    assert Phoenix.Flash.get(done.assigns.flash, :info) =~ "ballot submitted"
    assert_received {:scores, params}
    assert [%{"room_team_id" => 101, "rank" => 1} | _rest] = params["teamRankings"]
    assert_received :confirmed
  end

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
            {"GET", "/api/events/11"} ->
              ok(conn, %{"id" => 11, "status" => "scheduled"})

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

  test "owner page at sign-up: gold Close sign-ups + quiet Cancel, signup controls, settings",
       %{conn: conn, club: club, head: head} do
    member = user_fixture(%{node_user_id: 444, username: "benched"})
    membership_fixture(member, club)
    session = session_fixture(club, engine_event_id: 11)
    stub_signup_stage(signup_stage_signups())

    html = conn |> log_in(head) |> get(~p"/c/#{club.uuid}/owner") |> html_response(200)

    # chrome: gold Close sign-ups + quiet cancel; composition waits
    # for the :closed stage
    assert html =~ "Close sign-ups"
    assert html =~ "/c/#{club.uuid}/owner/sessions/#{session.uuid}/close-signups"
    assert html =~ "Cancel session"
    assert html =~ "/c/#{club.uuid}/owner/sessions/#{session.uuid}/cancel"
    refute html =~ "Make rooms"
    refute html =~ "Compose rooms"
    refute html =~ "Reopen sign-ups"
    refute html =~ "Delete rooms"

    # tonight: a remove link per signup + the on-behalf form listing
    # only members who are not signed up yet
    assert html =~ "/c/#{club.uuid}/owner/sessions/#{session.uuid}/signups/1/remove"
    assert html =~ ~s(id="add-signup-form")
    assert html =~ "benched"

    # club settings form + roster remove links (not on the head's row)
    assert html =~ ~s(id="club-settings-form")
    assert html =~ "/c/#{club.uuid}/owner/members/#{member.id}/remove"
    refute html =~ "/c/#{club.uuid}/owner/members/#{head.id}/remove"
  end

  test "owner page at :closed: Make rooms + Compose rooms + Reopen sign-ups",
       %{conn: conn, club: club, head: head} do
    session = closed_session_fixture(club, engine_event_id: 11)
    stub_signup_stage(signup_stage_signups())

    html = conn |> log_in(head) |> get(~p"/c/#{club.uuid}/owner") |> html_response(200)

    assert html =~ "Make rooms"
    assert html =~ "Compose rooms"
    assert html =~ "/c/#{club.uuid}/owner/sessions/#{session.uuid}/compose"
    assert html =~ "Reopen sign-ups"
    assert html =~ "/c/#{club.uuid}/owner/sessions/#{session.uuid}/reopen-signups"
    assert html =~ "sign-ups closed"
    refute html =~ "Close sign-ups"

    # the lifecycle twins: close while :signup only, reopen flips back
    reopened =
      conn
      |> log_in(head)
      |> post(~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/reopen-signups")

    assert redirected_to(reopened) == "/c/#{club.uuid}/owner"
    assert Phoenix.Flash.get(reopened.assigns.flash, :info) =~ "sign-ups reopened"

    closed =
      conn
      |> log_in(head)
      |> post(~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/close-signups")

    assert redirected_to(closed) == "/c/#{club.uuid}/owner"
    assert Phoenix.Flash.get(closed.assigns.flash, :info) =~ "sign-ups closed"

    # closing an already-closed session bounces with the conflict
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

    assert redirected_to(added) == "/c/#{club.uuid}/owner"
    assert Phoenix.Flash.get(added.assigns.flash, :info) =~ "benched"
    assert_received {:added, %{"user_id" => 444, "role" => "adjudicator"}}

    removed =
      conn
      |> log_in(head)
      |> post(~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/signups/3/remove")

    assert redirected_to(removed) == "/c/#{club.uuid}/owner"
    assert Phoenix.Flash.get(removed.assigns.flash, :info) =~ "signup removed"
    assert_received :removed
  end

  test "compose page is the dnd table: tray + slots + hidden inputs; the form posts the composition",
       %{conn: conn, club: club, head: head} do
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

    assert redirected_to(posted) == "/c/#{club.uuid}/owner"
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

    assert redirected_to(bounced) == "/c/#{club.uuid}/owner"
    assert Phoenix.Flash.get(bounced.assigns.flash, :error) =~ "placed more than once"

    # compose is owner-tree only — a member gets 403
    member = user_fixture(%{node_user_id: 55})
    membership_fixture(member, club)

    denied =
      conn |> log_in(member) |> get(~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/compose")

    assert response(denied, 403)
  end

  test "compose page requires :closed — while :signup it bounces to the owner page",
       %{conn: conn, club: club, head: head} do
    session = session_fixture(club, engine_event_id: 11)
    stub_signup_stage(signup_stage_signups())

    bounced =
      conn
      |> log_in(head)
      |> get(~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/compose")

    assert redirected_to(bounced) == "/c/#{club.uuid}/owner"
    assert Phoenix.Flash.get(bounced.assigns.flash, :error) =~ "close sign-ups first"
  end

  test "running stage: delete rooms while pending, reopen once confirmed",
       %{conn: conn, club: club, head: head} do
    session = session_fixture(club, engine_event_id: 11)
    test_pid = self()

    pending_room = %{running_room(44) | "status" => "pending"}

    stub(fn conn, _params ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/events/11"} ->
          ok(conn, %{"id" => 11, "status" => "scheduled"})

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

    html = conn |> log_in(head) |> get(~p"/c/#{club.uuid}/owner") |> html_response(200)
    assert html =~ "Delete rooms"
    assert html =~ "/c/#{club.uuid}/owner/sessions/#{session.uuid}/rooms/delete"
    refute html =~ "reopen"

    deleted =
      conn
      |> log_in(head)
      |> post(~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/rooms/delete")

    assert redirected_to(deleted) == "/c/#{club.uuid}/owner"
    assert Phoenix.Flash.get(deleted.assigns.flash, :info) =~ "1 room(s) deleted"
    assert_received :room_deleted

    # confirmed room: no delete segment, a reopen link instead
    confirmed_room = %{running_room(44) | "status" => "confirmed"}

    stub(fn conn, _params ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/events/11"} ->
          ok(conn, %{"id" => 11, "status" => "scheduled"})

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

    html = conn |> log_in(head) |> get(~p"/c/#{club.uuid}/owner") |> html_response(200)
    refute html =~ "Delete rooms"
    assert html =~ "/c/#{club.uuid}/owner/rooms/71/reopen"

    reopened = conn |> log_in(head) |> post(~p"/c/#{club.uuid}/owner/rooms/71/reopen")
    assert redirected_to(reopened) == "/c/#{club.uuid}/owner"
    assert Phoenix.Flash.get(reopened.assigns.flash, :info) =~ "reopened"
    assert_received {:step, "unconfirm"}
    assert_received {:step, "reopen"}
  end

  test "club settings save, member removal and session cancel redirect with flashes",
       %{conn: conn, club: club, head: head} do
    member = user_fixture(%{node_user_id: 55})
    membership_fixture(member, club)
    session = session_fixture(club, engine_event_id: 11)
    test_pid = self()

    stub(fn conn, _params ->
      case {conn.method, conn.request_path} do
        {"DELETE", "/api/events/11"} ->
          send(test_pid, :event_deleted)
          Req.Test.json(conn, %{"status" => "success", "message" => "Event archived."})
      end
    end)

    saved =
      conn
      |> log_in(head)
      |> post(~p"/c/#{club.uuid}/owner/club", %{name: "Renamed", city: "Lviv"})

    assert redirected_to(saved) == "/c/#{club.uuid}/owner"
    assert Phoenix.Flash.get(saved.assigns.flash, :info) =~ "settings saved"
    assert Cab.Clubs.get_by_uuid(club.uuid).name == "Renamed"

    removed =
      conn |> log_in(head) |> post(~p"/c/#{club.uuid}/owner/members/#{member.id}/remove")

    assert redirected_to(removed) == "/c/#{club.uuid}/owner"
    assert Phoenix.Flash.get(removed.assigns.flash, :info) =~ "member removed"
    assert Cab.Clubs.role_for(club, member) == :public

    # the head's own row bounces back with the reason
    protected =
      conn |> log_in(head) |> post(~p"/c/#{club.uuid}/owner/members/#{head.id}/remove")

    assert Phoenix.Flash.get(protected.assigns.flash, :error) =~ "head cannot be removed"

    cancelled =
      conn
      |> log_in(head)
      |> post(~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/cancel")

    assert redirected_to(cancelled) == "/c/#{club.uuid}/owner"
    assert Phoenix.Flash.get(cancelled.assigns.flash, :info) =~ "session cancelled"
    assert_received :event_deleted
    assert Cab.Sessions.list_for_club(club) == []

    # every one of these is owner-tree only
    for path <- [
          ~p"/c/#{club.uuid}/owner/club",
          ~p"/c/#{club.uuid}/owner/members/#{member.id}/remove"
        ] do
      assert conn |> log_in(member) |> post(path) |> response(403)
    end
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
