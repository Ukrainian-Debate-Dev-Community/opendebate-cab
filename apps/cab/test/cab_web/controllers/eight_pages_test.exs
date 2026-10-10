defmodule CabWeb.EightPagesTest do
  @moduledoc """
  The core pages: P1 /signin, the session page's stage variants and
  the club standings (rule-0 passthrough). The shell, /account,
  /admin and the global standings live in shell_pages_test; the
  owner surfaces in html_trees_test.
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
      assert html =~ ~s(<div class="brand-top">cab</div>)
      assert html =~ "We don&#39;t use passwords"

      # GitHub and Google both live, guest note present
      assert html =~ ~s(id="signin-github")
      assert html =~ ~s(href="/auth/github")
      assert html =~ "Continue with GitHub"
      assert html =~ ~s(id="signin-google")
      assert html =~ ~s(href="/auth/google")
      assert html =~ "Continue with Google"
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

      # the stage is written out as words in the crumb — no pill
      assert html =~ "registration open"
      refute html =~ "class=\"stage"
      assert html =~ ~s(id="session-signups")
      assert html =~ "Anna K"
      refute html =~ ~s(id="session-rooms")
    end

    test "running: rooms with side-colored cells and status words, my row tinted, judge sees you",
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

      assert html =~ "running"
      assert html =~ ~s(id="session-rooms")
      # the room row carries its status in words
      assert html =~ "motion set"
      assert html =~ "waiting for the ballot"
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

      assert html =~ "finished"
      assert html =~ "Winner: <b>Team 1</b>"
      assert html =~ "THW show the draw"
      assert html =~ "won"
      assert html =~ "2nd"
      assert html =~ "4th"
    end

    test "a foreign session uuid under this club is 404", %{conn: conn, club: club} do
      other = club_fixture(user_fixture(%{node_user_id: 20}), %{engine_organisation_id: 4})
      foreign = session_fixture(other, engine_event_id: 12)
      assert_error_sent 404, fn -> get(conn, ~p"/c/#{club.uuid}/s/#{foreign.uuid}") end
    end
  end

  # ---------------------------------------------------------------
  # /c/:club/standings — the SAME four tabs, rule-0 passthrough
  # ---------------------------------------------------------------

  defp stub_calculated do
    stub(fn conn, _params ->
      case conn.request_path do
        "/api/events/organisation/3" ->
          ok(conn, [%{"id" => 11, "name" => "Walk night", "status" => "completed"}])

        "/api/events/11" ->
          ok(conn, %{"id" => 11, "name" => "Walk night", "status" => "completed"})

        "/api/events/11/standings/calculated/teams" ->
          ok(conn, [%{"id" => 1, "name" => "Anna & Bohdan", "total_points" => 3}])

        "/api/events/11/standings/calculated/speakers" ->
          ok(conn, [%{"id" => 7, "name" => "Anna Kovalenko", "total_points" => 101.53}])

        "/api/events/11/stats/adjudicators" ->
          ok(conn, [
            %{"id" => 90, "name" => "Petro", "rooms_adjudicated" => 2, "avg_feedback" => 8.5}
          ])

        # the scope card's archive selector peeks at winners
        "/api/events/11/rounds" ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        "/api/rounds/21/rooms" ->
          ok(conn, [])
      end
    end)
  end

  describe "club standings" do
    setup %{conn: conn} do
      head = user_fixture(%{node_user_id: 19})
      club = club_fixture(head, %{engine_organisation_id: 3})

      session =
        session_fixture(club,
          engine_event_id: 11,
          name: "Walk night",
          finished_at: ~U[2026-10-01 20:00:00Z]
        )

      %{conn: conn, club: club, session: session}
    end

    test "teams/speakers tabs show the engine calculated standings verbatim — no cab math",
         %{conn: conn, club: club} do
      stub_calculated()

      html = conn |> get(~p"/c/#{club.uuid}/standings/speakers") |> html_response(200)

      # three tabs at club scope — Clubs is global-only
      assert html =~ ~s(id="standings-tabs")

      for tab <- ~w(teams speakers adjudicators) do
        assert html =~ ~s(href="/c/#{club.uuid}/standings/#{tab}")
      end

      refute html =~ ~s(href="/c/#{club.uuid}/standings/clubs")

      # engine output verbatim: name + total_points, session named
      assert html =~ ~s(id="standings-speakers")
      assert html =~ "Anna Kovalenko"
      assert html =~ "101.53"
      assert html =~ "Walk night"

      # NO wins/winrate/played strings anywhere on standings pages
      refute html =~ "wins"
      refute html =~ "Wins"
      refute html =~ "winrate"
      refute html =~ "Win rate"
      refute html =~ "win_rate"
      refute html =~ "played"
      refute html =~ "Played"

      teams = conn |> get(~p"/c/#{club.uuid}/standings/teams") |> html_response(200)
      assert teams =~ "Anna &amp; Bohdan"
      assert teams =~ ~r/>\s*3\s*</

      # the bare /standings URL lands on the teams tab
      bare = conn |> get(~p"/c/#{club.uuid}/standings") |> html_response(200)
      assert bare =~ ~s(id="standings-teams")
    end

    test "judges tab is the engine's judge stats verbatim; clubs tab is global-only",
         %{conn: conn, club: club} do
      stub_calculated()

      judges = conn |> get(~p"/c/#{club.uuid}/standings/adjudicators") |> html_response(200)
      assert judges =~ ~s(id="standings-adjudicators")
      assert judges =~ "Petro"
      assert judges =~ "Rooms adjudicated"
      assert judges =~ "Avg feedback"
      assert judges =~ "8.5"

      assert conn |> get(~p"/c/#{club.uuid}/standings/clubs") |> response(404)
    end

    test "?session walks the archive; earlier sessions are linked",
         %{conn: conn, club: club, session: first_session} do
      # a second, newer finished session — the default scope lands on it
      _newer =
        session_fixture(club,
          engine_event_id: 10,
          name: "Newer night",
          finished_at: ~U[2026-10-08 20:00:00Z]
        )

      stub(fn conn, _params ->
        case conn.request_path do
          "/api/events/organisation/3" ->
            ok(conn, [
              %{"id" => 11, "name" => "Walk night", "status" => "completed"},
              %{"id" => 10, "name" => "Newer night", "status" => "completed"}
            ])

          "/api/events/11" ->
            ok(conn, %{"id" => 11, "name" => "Walk night", "status" => "completed"})

          "/api/events/10" ->
            ok(conn, %{"id" => 10, "name" => "Newer night", "status" => "completed"})

          "/api/events/10/standings/calculated/speakers" ->
            ok(conn, [%{"id" => 8, "name" => "Newer Winner", "total_points" => 99.0}])

          "/api/events/11/standings/calculated/speakers" ->
            ok(conn, [%{"id" => 7, "name" => "Anna Kovalenko", "total_points" => 101.53}])

          "/api/events/" <> _rounds ->
            ok(conn, [%{"id" => 21, "sequence" => 1}])

          "/api/rounds/21/rooms" ->
            ok(conn, [])
        end
      end)

      # default: the latest finished, with the earlier one linked below
      html = conn |> get(~p"/c/#{club.uuid}/standings/speakers") |> html_response(200)
      assert html =~ "Newer Winner"
      assert html =~ "(latest finished)"
      assert html =~ "earlier:"
      assert html =~ "?session=#{first_session.uuid}"

      # the selector shows exactly that session's engine rows
      old_html =
        conn
        |> get(~p"/c/#{club.uuid}/standings/speakers?session=#{first_session.uuid}")
        |> html_response(200)

      assert old_html =~ "Anna Kovalenko"
      assert old_html =~ "Walk night"
      refute old_html =~ "Newer Winner"
    end

    test "no finished session shows the empty notice; engine trouble degrades to empty rows",
         %{conn: conn, club: club} do
      fresh = club_fixture(user_fixture(%{node_user_id: 29}), %{engine_organisation_id: 5})
      _open = session_fixture(fresh, engine_event_id: 50)

      html = conn |> get(~p"/c/#{fresh.uuid}/standings/teams") |> html_response(200)
      assert html =~ "No finished session yet."

      stub(fn conn, _params -> Plug.Conn.send_resp(conn, 500, "boom") end)

      html = conn |> get(~p"/c/#{club.uuid}/standings/teams") |> html_response(200)
      assert html =~ "No results for this session yet."
    end

    test "an unknown tab is 404", %{conn: conn, club: club} do
      assert conn |> get("/c/#{club.uuid}/standings/wins") |> response(404)
    end
  end
end
