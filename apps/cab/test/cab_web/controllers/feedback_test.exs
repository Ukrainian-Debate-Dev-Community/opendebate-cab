defmodule CabWeb.FeedbackTest do
  @moduledoc """
  Club-night feedback: one per team on its room's adjudicator, kept in
  the engine. Who may send it, and who sees what, when.
  """

  use CabWeb.ConnCase, async: true

  import Cab.Fixtures

  alias Cab.Feedback
  alias Cab.Sessions

  # the engine as feedback sees it: one room R1 (id 71), the chair is
  # participant 90; OG (team 1001) is Anna 301 + Bohdan 302, OO (team
  # 1002) is Daryna 303 + guest Greta 304, CG and CO fill the room
  setup %{conn: conn} do
    head = user_fixture(%{node_user_id: 9})
    club = club_fixture(head, %{engine_organisation_id: 3})
    anna = user_fixture(%{node_user_id: 501, username: "anna"})
    bohdan = user_fixture(%{node_user_id: 502, username: "bohdan"})
    judge = user_fixture(%{node_user_id: 77, username: "petro"})
    outsider = user_fixture(%{node_user_id: 555})
    greta = user_fixture(%{node_user_id: nil, username: "guest-greta", name: "Greta"})

    session =
      session_fixture(club,
        engine_event_id: 11,
        engine_round_id: 21,
        name: "Feedback night",
        started_at: DateTime.utc_now(:second),
        rooms_count: 1
      )

    link_fixture(greta, session, participant_id: 304)

    {:ok, engine} =
      Agent.start_link(fn ->
        %{status: "completed", event: "scheduled", questions: [], feedback: []}
      end)

    stub_engine(engine)

    %{
      conn: conn,
      head: head,
      club: club,
      session: %{session | club: club},
      anna: anna,
      bohdan: bohdan,
      judge: judge,
      outsider: outsider,
      greta: greta,
      engine: engine
    }
  end

  defp signups do
    [
      %{"id" => 90, "user_id" => 77, "role" => "adjudicator", "display_name" => "Petro"},
      %{"id" => 301, "user_id" => 501, "role" => "speaker", "display_name" => "Anna"},
      %{"id" => 302, "user_id" => 502, "role" => "speaker", "display_name" => "Bohdan"},
      %{"id" => 303, "user_id" => 503, "role" => "speaker", "display_name" => "Daryna"},
      %{"id" => 304, "user_id" => nil, "role" => "speaker", "display_name" => "Greta"}
    ]
  end

  defp room(status) do
    teams = [{1001, [301, 302]}, {1002, [303, 304]}, {1003, [305, 306]}, {1004, [307, 308]}]

    %{
      "id" => 71,
      "status" => status,
      "Motion" => %{"motion_text" => "THW give feedback"},
      "RoomAdjudicators" => [
        %{"id" => 1, "role" => "chair", "EventParticipant" => %{"id" => 90, "user_id" => 77}}
      ],
      "RoomTeams" =>
        for {{team_id, pids}, position} <- Enum.with_index(teams, 1) do
          %{
            "id" => 100 + position,
            "position" => position,
            "rank" => position,
            "Team" => %{"id" => team_id, "name" => "Team #{position}"},
            "RoomSpeakers" =>
              Enum.map(pids, &%{"id" => &1 + 1000, "EventParticipant" => %{"id" => &1}})
          }
        end
    }
  end

  defp stub_engine(engine) do
    test_pid = self()

    Req.Test.stub(Core.Engine, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      params = if body == "", do: %{}, else: Jason.decode!(body)
      ok = fn data -> Req.Test.json(conn, %{"status" => "success", "data" => data}) end

      case {conn.method, conn.request_path} do
        {"GET", "/api/events/organisation/3"} ->
          ok.([])

        {"GET", "/api/events/11"} ->
          ok.(%{
            "id" => 11,
            "name" => "Feedback night",
            "status" => Agent.get(engine, & &1.event)
          })

        {"GET", "/api/events/11/rounds"} ->
          ok.([%{"id" => 21, "sequence" => 1}])

        {"GET", "/api/events/11/participants"} ->
          ok.(signups())

        {"GET", "/api/rounds/21/rooms"} ->
          ok.([room(Agent.get(engine, & &1.status))])

        {"GET", "/api/events/11/feedback-questions"} ->
          ok.(Agent.get(engine, & &1.questions))

        {"POST", "/api/events/11/feedback-questions"} ->
          Agent.update(engine, &%{&1 | questions: &1.questions ++ [params]})
          ok.(params)

        {"POST", "/api/rooms/71/feedback"} ->
          send(test_pid, {:feedback_sent, params, actor(conn)})
          taken = Agent.get(engine, & &1.feedback)

          if Enum.any?(taken, &(&1["issuer_team_id"] == params["issuer_team_id"])) do
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(
              409,
              Jason.encode!(%{
                "status" => "fail",
                "message" =>
                  "Feedback has already been submitted for this adjudicator by this issuer."
              })
            )
          else
            record = engine_record(length(taken) + 1, params)
            Agent.update(engine, &%{&1 | feedback: &1.feedback ++ [record]})
            ok.(record)
          end

        {"GET", "/api/events/11/feedback"} ->
          ok.(Agent.get(engine, & &1.feedback))

        {"GET", "/api/events/11/stats/adjudicators"} ->
          send(test_pid, {:stats_query, conn.query_string})
          ok.([%{"id" => 90, "name" => "Petro", "rooms_adjudicated" => 1, "avg_feedback" => 6.5}])
      end
    end)
  end

  defp engine_record(id, params) do
    answers = Map.new(params["answers"], &{&1["key"], &1["value"]})
    team = params["issuer_team_id"]

    %{
      "id" => id,
      "room_id" => 71,
      "adjudicator_id" => params["adjudicator_id"],
      "issuer_team_id" => team,
      "comment" => params["comment"],
      "score" => (answers["accuracy"] + answers["reasoning"]) / 2,
      "answers" => for({k, v} <- answers, do: %{"key" => k, "value" => v}),
      "Adjudicator" => %{"id" => 90, "display_name" => "Petro"},
      "IssuerTeam" => %{"id" => team, "name" => "Team #{team - 1000}"}
    }
  end

  defp actor(conn) do
    ["Bearer " <> token] = Plug.Conn.get_req_header(conn, "authorization")
    {:ok, claims} = Joken.verify(token, Joken.Signer.create("HS256", "test-engine-secret"))
    claims["id"]
  end

  defp form(accuracy, reasoning, discussion),
    do: %{"accuracy" => accuracy, "reasoning" => reasoning, "discussion" => discussion}

  defp log_in(conn, user) do
    conn
    |> init_test_session(%{user_id: user.id})
    |> Plug.Conn.put_private(:plug_skip_csrf_protection, true)
  end

  # the head finished: the engine's event is completed, cab's row has finished_at
  defp finish(session, engine) do
    Agent.update(engine, &%{&1 | event: "completed"})

    session
    |> Ecto.Changeset.change(finished_at: DateTime.utc_now(:second))
    |> Cab.Repo.update!()
    |> Map.put(:club, session.club)
  end

  describe "the form" do
    test "is added to the event once, with both scoring questions", %{
      session: session,
      engine: engine
    } do
      assert :ok = Feedback.ensure_form(session)

      assert ["accuracy", "reasoning"] =
               Agent.get(engine, &Enum.map(&1.questions, fn q -> q["key"] end))

      assert [
               %{
                 "type" => "integer",
                 "min_value" => 1,
                 "max_value" => 10,
                 "counts_in_score" => true
               }
               | _
             ] =
               Agent.get(engine, & &1.questions)

      # present already: nothing is added twice
      assert :ok = Feedback.ensure_form(session)
      assert length(Agent.get(engine, & &1.questions)) == 2
    end
  end

  describe "sending" do
    test "a member sends as themselves for their team; the score is the engine's",
         %{session: session, anna: anna} do
      assert :ok = Feedback.submit(anna, session, 71, form("8", "7", "Clear call."))

      assert_received {:feedback_sent, params, 501}

      assert %{
               "adjudicator_id" => 90,
               "issuer_team_id" => 1001,
               "comment" => "Clear call.",
               "answers" => [
                 %{"key" => "accuracy", "value" => 8},
                 %{"key" => "reasoning", "value" => 7}
               ]
             } = params
    end

    test "a guest's team feedback goes to the engine as the club head",
         %{session: session, greta: greta} do
      assert :ok = Feedback.submit(greta, session, 71, form("9", "9", "Very fair."))
      assert_received {:feedback_sent, %{"issuer_team_id" => 1002}, 9}
    end

    test "the first one of a team stays; a teammate is told",
         %{session: session, anna: anna, bohdan: bohdan} do
      assert :ok = Feedback.submit(anna, session, 71, form("8", "7", "Clear call."))

      assert {:error, :conflict, "Your team already sent feedback."} =
               Feedback.submit(bohdan, session, 71, form("3", "3", "Disagree."))
    end

    test "only once the ballot is in, and never after the session is finished",
         %{session: session, anna: anna, engine: engine} do
      Agent.update(engine, &%{&1 | status: "judging"})

      assert {:error, :conflict, "Feedback opens once the room's ballot is in."} =
               Feedback.submit(anna, session, 71, form("8", "7", "Too early."))

      Agent.update(engine, &%{&1 | status: "confirmed"})

      assert {:error, :conflict, "The session is finished, so feedback is closed."} =
               Feedback.submit(anna, finish(session, engine), 71, form("8", "7", "Too late."))

      refute_received {:feedback_sent, _, _}
    end

    test "all three answers are required; scores are whole numbers from 1 to 10",
         %{session: session, anna: anna} do
      assert {:error, errors} = Feedback.submit(anna, session, 71, form("0", "7.5", "  "))
      assert Map.keys(errors) |> Enum.sort() == ["accuracy", "discussion", "reasoning"]
      refute_received {:feedback_sent, _, _}
    end

    test "someone not on a team in the room cannot send", %{session: session, outsider: outsider} do
      assert {:error, :forbidden} = Feedback.submit(outsider, session, 71, form("8", "7", "Hi."))
    end
  end

  describe "who sees what" do
    setup %{session: session, anna: anna} do
      :ok = Feedback.submit(anna, session, 71, form("8", "7", "Clear call."))
      :ok
    end

    test "the team sees its own right away; the adjudicator nothing until the finish",
         %{session: session, bohdan: bohdan, judge: judge, engine: engine} do
      {:ok, state} = Sessions.state(session)
      [room] = state.rooms

      assert %{accuracy: 8, reasoning: 7, discussion: "Clear call."} =
               Feedback.own_for_room(session, state, room, bohdan)

      assert Feedback.on_adjudicator(session, state, judge) == []

      finished = finish(session, engine)
      assert [entry] = Feedback.on_adjudicator(finished, state, judge)
      assert %{accuracy: 8, reasoning: 7, score: 7.5} = entry
      refute Map.has_key?(entry, :team)
      refute Map.has_key?(entry, :team_id)
    end

    test "the head sees progress per room", %{session: session} do
      {:ok, state} = Sessions.state(session)
      assert %{71 => {1, 4}} = Feedback.progress(state, Feedback.all(session))
    end

    test "the average counts a base of 5 as one vote", %{session: session, judge: judge} do
      {:ok, state} = Sessions.state(session)
      assert 6.5 == Feedback.my_average(session, state, judge)
      assert_received {:stats_query, "base=5"}
    end
  end

  describe "pages" do
    test "the form is for a team member; the chrome sends it; anyone else is turned away",
         %{conn: conn, club: club, session: session, anna: anna, outsider: outsider} do
      path = ~p"/c/#{club.uuid}/s/#{session.uuid}/rooms/71/feedback"
      html = conn |> log_in(anna) |> get(path) |> html_response(200)

      assert html =~ ~s(name="accuracy")
      assert html =~ ~s(name="reasoning")
      assert html =~ ~s(name="discussion")
      assert html =~ ~s(form="feedback-71")
      # the chrome is the form's only button
      refute html =~ ~s(class="btn-go")
      refute html =~ ~s(class="btn-quiet")

      assert conn |> log_in(outsider) |> get(path) |> response(403)
      assert conn |> get(path) |> redirected_to() == "/signin"

      sent = conn |> log_in(anna) |> post(path, form("8", "7", "Clear call."))
      assert redirected_to(sent) == path
      assert Phoenix.Flash.get(sent.assigns.flash, :info) =~ "Feedback sent."

      again = conn |> log_in(anna) |> get(path) |> html_response(200)
      assert again =~ "Your team already sent feedback."
      assert again =~ "Clear call."
      refute again =~ ~s(form="feedback-71")
    end

    test "missing answers re-render the form with what was typed",
         %{conn: conn, club: club, session: session, anna: anna} do
      path = ~p"/c/#{club.uuid}/s/#{session.uuid}/rooms/71/feedback"
      html = conn |> log_in(anna) |> post(path, form("8", "", "Kept text")) |> html_response(422)
      assert html =~ "Enter a whole number from 1 to 10."
      assert html =~ "Kept text"
    end

    test "the session page offers Give feedback to a team member who owes it",
         %{conn: conn, club: club, session: session, anna: anna} do
      html =
        conn |> log_in(anna) |> get(~p"/c/#{club.uuid}/s/#{session.uuid}") |> html_response(200)

      assert html =~ "Give feedback"
      assert html =~ "/c/#{club.uuid}/s/#{session.uuid}/rooms/71/feedback"

      :ok = Feedback.submit(anna, session, 71, form("8", "7", "Done."))

      html =
        conn |> log_in(anna) |> get(~p"/c/#{club.uuid}/s/#{session.uuid}") |> html_response(200)

      refute html =~ "Give feedback"
    end

    test "the finished session page shows the adjudicator their feedback without teams",
         %{conn: conn, club: club, session: session, anna: anna, judge: judge, engine: engine} do
      :ok = Feedback.submit(anna, session, 71, form("8", "7", "Clear call."))
      page = ~p"/c/#{club.uuid}/s/#{session.uuid}"

      before = conn |> log_in(judge) |> get(page) |> html_response(200)
      refute before =~ "Feedback on your adjudication"

      finish(session, engine)
      html = conn |> log_in(judge) |> get(page) |> html_response(200)
      assert html =~ "Feedback on your adjudication"

      # the results above name the teams; the feedback table never does
      table =
        html
        |> LazyHTML.from_document()
        |> LazyHTML.query("#feedback-on-me")
        |> LazyHTML.text()

      assert table =~ "Clear call."
      refute table =~ "Team"
    end

    test "the head's Rooms page shows progress and every feedback with its team",
         %{conn: conn, club: club, session: session, head: head, anna: anna} do
      :ok = Feedback.submit(anna, session, 71, form("8", "7", "Clear call."))

      html =
        conn
        |> log_in(head)
        |> get(~p"/c/#{club.uuid}/owner/s/#{session.uuid}")
        |> html_response(200)

      assert html =~ "1 of 4 teams"
      assert html =~ ~s(id="session-feedback")
      assert html =~ "Team 1"
      assert html =~ "Clear call."
    end
  end

  describe "API twins" do
    test "a member sends; the head reads everything with teams; others only their part",
         %{
           conn: conn,
           session: session,
           head: head,
           anna: anna,
           judge: judge,
           outsider: outsider,
           engine: engine
         } do
      sent =
        conn
        |> log_in(anna)
        |> post(~p"/api/cab/v1/rooms/71/feedback", %{
          session_uuid: session.uuid,
          accuracy: 8,
          reasoning: 7,
          discussion: "Clear call."
        })
        |> json_response(201)

      assert sent["status"] == "sent"

      again =
        conn
        |> log_in(anna)
        |> post(~p"/api/cab/v1/rooms/71/feedback", %{
          session_uuid: session.uuid,
          accuracy: 8,
          reasoning: 7,
          discussion: "Twice."
        })
        |> json_response(409)

      assert again["error"] =~ "already sent"

      path = ~p"/api/cab/v1/sessions/#{session.uuid}/feedback"
      as_head = conn |> log_in(head) |> get(path) |> json_response(200)
      assert [%{"team" => "Team 1", "accuracy" => 8, "room" => "R1"}] = as_head["feedback"]
      assert [%{"room" => "R1", "sent" => 1, "teams" => 4}] = as_head["progress"]

      as_team = conn |> log_in(anna) |> get(path) |> json_response(200)
      assert [%{"discussion" => "Clear call."}] = as_team["feedback"]

      as_judge = conn |> log_in(judge) |> get(path) |> json_response(200)
      assert as_judge["on_your_adjudication"] == []

      as_outsider = conn |> log_in(outsider) |> get(path) |> json_response(200)
      assert as_outsider["feedback"] == []

      finish(session, engine)
      as_judge = conn |> log_in(judge) |> get(path) |> json_response(200)
      assert [entry] = as_judge["on_your_adjudication"]
      refute Map.has_key?(entry, "team")
    end
  end

  test "opening a session puts the form on its new event", %{club: club, head: head} do
    test_pid = self()

    Req.Test.stub(Core.Engine, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      ok = fn data -> Req.Test.json(conn, %{"status" => "success", "data" => data}) end

      case {conn.method, conn.request_path} do
        {"POST", "/api/events/3"} ->
          ok.(%{"id" => 12, "name" => "New night"})

        {"POST", "/api/events/12/rounds"} ->
          ok.(%{"id" => 22})

        {"GET", "/api/events/12/feedback-questions"} ->
          ok.([])

        {"POST", "/api/events/12/feedback-questions"} ->
          send(test_pid, {:question, Jason.decode!(body)["key"]})
          ok.(%{})
      end
    end)

    assert {:ok, _session} = Sessions.open(head, club, "New night")
    assert_received {:question, "accuracy"}
    assert_received {:question, "reasoning"}
  end

  test "standings ask the engine for the average with the base vote", %{session: session} do
    {:ok, actor} = Cab.Clubs.club_actor(session.club)
    Cab.Standings.adjudicators(%{actor: actor, session: session})
    assert_received {:stats_query, "base=5"}
  end
end
