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
