defmodule CabWeb.EightPagesTest do
  @moduledoc """
  M7 acceptance: the canonical eight. P2/P3 live in cabinet_home_test,
  P4/P5 and most of P8 in html_trees_test, the guest path through P6
  in guest_links_test — here: P1, the P6 stage variants, P7 and the
  P8 default-tab logic.
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

  defp stub_stage(signups, rooms \\ [], event_status \\ "scheduled") do
    stub(fn conn, _params ->
      case conn.request_path do
        "/api/events/organisation/3" ->
          ok(conn, [%{"id" => 11, "name" => "Walk night", "status" => event_status}])

        "/api/events/11" ->
          ok(conn, %{"id" => 11, "name" => "Walk night", "status" => event_status})

        "/api/events/11/rounds" ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        "/api/events/11/participants" ->
          ok(conn, signups)

        "/api/rounds/21/rooms" ->
          ok(conn, rooms)
      end
    end)
  end

  defp room(status, chair_user_id) do
    %{
      "id" => 71,
      "status" => status,
      "Motion" => %{"motion_text" => "THW show the draw"},
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
            "rank" => if(status in ["confirmed", "completed"], do: position),
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

  # ---------------------------------------------------------------
  # P1 /signin
  # ---------------------------------------------------------------

  describe "P1 /signin" do
    test "renders the split page with the provider buttons", %{conn: conn} do
      html = conn |> get(~p"/signin") |> html_response(200)

      # the split page: brand side + the no-passwords card
      assert html =~ ~s(class="auth")
      assert html =~ "cab.uadebate"
      assert html =~ "We don't use passwords"

      # GitHub live, Google disabled ("soon"), guest note present
      assert html =~ ~s(id="signin-github")
      assert html =~ ~s(href="/auth/github")
      assert html =~ "Continue with GitHub"
      assert html =~ ~s(id="signin-google")
      assert html =~ "Continue with Google — soon"
      assert html =~ "no account needed"
    end

    test "a signed-in user is sent home", %{conn: conn} do
      user = user_fixture()
      assert conn |> log_in(user) |> get(~p"/signin") |> redirected_to() == "/"
    end

    test "the owner tree's anonymous auth wall lands here", %{conn: conn} do
      club = club_fixture(user_fixture())
      assert conn |> get(~p"/c/#{club.uuid}/owner") |> redirected_to() == "/signin"
    end
  end

  # ---------------------------------------------------------------
  # P6 /c/:club/s/:session — stage variants
  # ---------------------------------------------------------------

  describe "P6 stage variants" do
    setup %{conn: conn} do
      head = user_fixture(%{node_user_id: 19})
      club = club_fixture(head, %{engine_organisation_id: 3})
      session = session_fixture(club, engine_event_id: 11)
      %{conn: conn, head: head, club: club, session: session}
    end

    test "signup: who's registered, public", %{conn: conn, club: club, session: session} do
      stub_stage([
        %{"id" => 41, "user_id" => 144, "role" => "speaker", "display_name" => "Anna K"}
      ])

      html = conn |> get(~p"/c/#{club.uuid}/s/#{session.uuid}") |> html_response(200)

      assert html =~ ~s(class="stage ok")
      assert html =~ "sign-up open"
      assert html =~ ~s(id="session-signups")
      assert html =~ "Anna K"
      refute html =~ ~s(id="session-draw")
    end

    test "running: the draw with side-colored cells, my row tinted, judge sees you",
         %{conn: conn, club: club, session: session} do
      viewer = user_fixture(%{node_user_id: 144})

      stub_stage(
        [
          %{"id" => 301, "user_id" => 144, "role" => "speaker", "display_name" => "Me"},
          %{"id" => 90, "user_id" => 199, "role" => "adjudicator", "display_name" => "Petro"}
        ],
        [room("judging", 199)]
      )

      html =
        conn
        |> log_in(viewer)
        |> get(~p"/c/#{club.uuid}/s/#{session.uuid}")
        |> html_response(200)

      assert html =~ ~s(class="stage warn")
      assert html =~ ~s(id="session-draw")
      for side <- ~w(s-og s-oo s-cg s-co), do: assert(html =~ side)
      # the viewer speaks in R71 (participant 301) -> the row is tinted
      assert html =~ ~s(class="me")
      # the chair resolves to their display name for non-judges
      assert html =~ "Petro"

      # the judge's own view: <b>you</b> + the gold Fill ballot segment
      judge = user_fixture(%{node_user_id: 199})

      judge_html =
        conn
        |> log_in(judge)
        |> get(~p"/c/#{club.uuid}/s/#{session.uuid}")
        |> html_response(200)

      assert judge_html =~ ">you</b>"
      assert judge_html =~ "Fill ballot"
      assert judge_html =~ "/c/#{club.uuid}/s/#{session.uuid}/rooms/71/ballot"
    end

    test "done: results, ranks, winner", %{conn: conn, club: club, session: session} do
      stub_stage([], [room("confirmed", 199)], "completed")

      html = conn |> get(~p"/c/#{club.uuid}/s/#{session.uuid}") |> html_response(200)

      assert html =~ ~s(class="stage off")
      assert html =~ "Winner: <b>Team 1</b>"
      assert html =~ "THW show the draw"
      assert html =~ "won"
      assert html =~ "2nd"
      assert html =~ "4th"
    end

    test "a foreign session uuid under this club is 404", %{conn: conn, club: club} do
      other = club_fixture(user_fixture(%{node_user_id: 20}), %{engine_organisation_id: 4})
      foreign = session_fixture(other, engine_event_id: 12)
      assert conn |> get(~p"/c/#{club.uuid}/s/#{foreign.uuid}") |> response(404)
    end
  end

  # ---------------------------------------------------------------
  # P7 /c/:club/standings
  # ---------------------------------------------------------------

  describe "P7 standings" do
    test "member stats + session winners timeline, public", %{conn: conn} do
      head = user_fixture(%{node_user_id: 19})
      club = club_fixture(head, %{engine_organisation_id: 3})
      session = session_fixture(club, engine_event_id: 11)

      stub(fn conn, _params ->
        case conn.request_path do
          "/api/events/organisation/3" ->
            ok(conn, [%{"id" => 11, "name" => "Walk night", "status" => "completed"}])

          "/api/events/11/participants" ->
            ok(conn, [
              %{"id" => 301, "user_id" => 144, "role" => "speaker", "display_name" => "Anna K"},
              %{"id" => 302, "user_id" => 45, "role" => "speaker", "display_name" => "Bo S"},
              %{"id" => 303, "user_id" => 46, "role" => "speaker", "display_name" => "Cy D"},
              %{"id" => 304, "user_id" => 47, "role" => "speaker", "display_name" => "Dee E"},
              %{"id" => 90, "user_id" => 199, "role" => "adjudicator", "display_name" => "Petro"}
            ])

          "/api/events/11/rounds" ->
            ok(conn, [%{"id" => 21, "sequence" => 1}])

          "/api/rounds/21/rooms" ->
            ok(conn, [
              %{
                "id" => 71,
                "status" => "confirmed",
                "RoomTeams" =>
                  for position <- 1..4 do
                    %{
                      "id" => 100 + position,
                      "position" => position,
                      "rank" => position,
                      "Team" => %{"name" => "T#{position}"},
                      "RoomSpeakers" => [
                        %{"id" => 200 + position, "EventParticipant" => %{"id" => 300 + position}}
                      ]
                    }
                  end
              }
            ])
        end
      end)

      html = conn |> get(~p"/c/#{club.uuid}/standings") |> html_response(200)

      # member stats: played, wins, win rate — the winner tops the table
      assert html =~ ~s(id="standings-members")
      assert html =~ "Anna K"
      assert html =~ "100%"
      assert html =~ "0%"

      # winners timeline rows link to P6
      assert html =~ ~s(id="session-winners")
      assert html =~ "Walk night"
      assert html =~ "T1"
      assert html =~ ~s(href="/c/#{club.uuid}/s/#{session.uuid}")
    end

    test "degrades to empty tables when the engine is unreachable", %{conn: conn} do
      club = club_fixture(user_fixture(%{node_user_id: 19}))
      session_fixture(club, engine_event_id: 11)

      stub(fn conn, _params -> Plug.Conn.send_resp(conn, 500, "boom") end)

      html = conn |> get(~p"/c/#{club.uuid}/standings") |> html_response(200)
      assert html =~ "No results yet."
      assert html =~ "No completed sessions yet."
    end
  end

  # ---------------------------------------------------------------
  # P8 default tab logic
  # ---------------------------------------------------------------

  describe "P8 default tab" do
    setup %{conn: conn} do
      head = user_fixture(%{node_user_id: 19})
      club = club_fixture(head, %{engine_organisation_id: 3})
      %{conn: conn, head: head, club: club}
    end

    test "pending requests pull attention first", %{conn: conn, head: head, club: club} do
      {:ok, _} = Cab.Clubs.request_join(user_fixture(%{username: "nina"}), club)
      session_fixture(club, engine_event_id: 11)
      stub_stage([])

      html = conn |> log_in(head) |> get(~p"/c/#{club.uuid}/owner") |> html_response(200)
      assert html =~ ~s(id="join-requests")
      assert html =~ "nina"
      # the requests tab carries the counter badge
      assert html =~ ~s(class="n">1</span>)
    end

    test "closed stage defaults to Rooms with the compose banner",
         %{conn: conn, head: head, club: club} do
      session = closed_session_fixture(club, engine_event_id: 11)

      stub_stage([
        %{"id" => 1, "user_id" => 41, "role" => "speaker", "display_name" => "S1"},
        %{"id" => 90, "user_id" => 199, "role" => "adjudicator", "display_name" => "J1"}
      ])

      html = conn |> log_in(head) |> get(~p"/c/#{club.uuid}/owner") |> html_response(200)
      assert html =~ "No rooms yet."
      assert html =~ "Compose rooms →"
      assert html =~ "/c/#{club.uuid}/owner/sessions/#{session.uuid}/compose"
      assert html =~ "1 speakers + 1 judge checked in"
    end

    test "an unknown tab falls back to the smart default", %{conn: conn, head: head, club: club} do
      html =
        conn
        |> log_in(head)
        |> get(~p"/c/#{club.uuid}/owner?tab=nonsense")
        |> html_response(200)

      # no session, nothing pending -> Tonight (the open-session form)
      assert html =~ ~s(id="open-session-form")
    end
  end
end
