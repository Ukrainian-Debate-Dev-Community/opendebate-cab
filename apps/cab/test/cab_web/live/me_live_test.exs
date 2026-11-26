defmodule CabWeb.MeLiveTest do
  @moduledoc """
  My page is the participant's hub: where they sit now in a running
  session - the draw, their side and role, the motion and its prep -
  and, as the room's chair, the motion published right there.
  """
  # the engine stub answers the live process too
  use CabWeb.ConnCase, async: false

  import Cab.Fixtures
  import Phoenix.LiveViewTest

  setup do
    Req.Test.set_req_test_to_shared()
    on_exit(fn -> Req.Test.set_req_test_to_private() end)
    :ok
  end

  defp ok(conn, data), do: Req.Test.json(conn, %{"status" => "success", "data" => data})

  defp speaker(id, participant, name, user_id \\ nil),
    do: %{
      "id" => id,
      "EventParticipant" => %{"id" => participant, "display_name" => name, "user_id" => user_id}
    }

  # an Australs room: Anna (node user 55) speaks second for Opp; the
  # chair is node user 66
  defp room(motion, status \\ "pending") do
    %{
      "id" => 71,
      "status" => status,
      "Motion" => motion,
      "prep_until" => motion && "2026-10-09T18:15:00Z",
      "RoomAdjudicators" => [
        %{
          "role" => "chair",
          "EventParticipant" => %{"id" => 90, "display_name" => "Judy", "user_id" => 66}
        }
      ],
      "RoomTeams" => [
        %{
          "id" => 101,
          "position" => 1,
          "Team" => %{"id" => 1001},
          "RoomSpeakers" => [
            speaker(1, 11, "Gov One"),
            speaker(2, 12, "Gov Two"),
            speaker(3, 13, "Gov Three")
          ]
        },
        %{
          "id" => 102,
          "position" => 2,
          "Team" => %{"id" => 1002},
          # the engine lists slots in no set order; the ids give it
          "RoomSpeakers" => [
            speaker(6, 23, "Opp Three"),
            speaker(4, 21, "Opp One"),
            speaker(5, 22, "Anna")
          ]
        }
      ]
    }
  end

  defp stub_engine(test_pid, motion \\ nil) do
    {:ok, agent} = Agent.start_link(fn -> motion end)

    Req.Test.stub(Core.Engine, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/users/schedule"} ->
          ok(conn, %{"as_adjudicator" => [%{"id" => 11}], "as_player" => [%{"id" => 11}]})

        {"GET", "/api/users/history"} ->
          ok(conn, %{"as_adjudicator" => [], "as_player" => []})

        {"GET", "/api/users/" <> _stats} ->
          ok(conn, nil)

        {"GET", "/api/events/11"} ->
          ok(conn, %{"id" => 11, "name" => "Thursday", "status" => "in_progress"})

        {"GET", "/api/events/11/rounds"} ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        {"GET", "/api/events/11/participants"} ->
          # the rooms read names speakers without their accounts: the
          # sign-ups say who is who
          ok(conn, [
            %{"id" => 90, "display_name" => "Judy", "user_id" => 66},
            %{"id" => 22, "display_name" => "Anna", "user_id" => 55}
          ])

        {"GET", "/api/rounds/21/rooms"} ->
          ok(conn, [room(Agent.get(agent, & &1))])

        {"POST", "/api/rooms/71/motion"} ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          params = Jason.decode!(body)
          Agent.update(agent, fn _ -> params end)
          send(test_pid, {:motion, params})
          ok(conn, %{"id" => 5})

        {"PATCH", "/api/rooms/71/prep"} ->
          send(test_pid, :prep)
          ok(conn, %{"id" => 71})

        {"POST", "/api/rooms/71/scores"} ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          send(test_pid, {:scores, Jason.decode!(body)})
          Req.Test.json(conn, %{"status" => "success", "message" => "ok"})

        {"PATCH", "/api/rooms/71/confirm"} ->
          send(test_pid, :confirmed)
          Req.Test.json(conn, %{"status" => "success", "message" => "ok"})
      end
    end)
  end

  # the ballot is in: Anna's team may send feedback on Judy
  defp stub_feedback_engine(test_pid) do
    {:ok, sent} = Agent.start_link(fn -> [] end)

    Req.Test.stub(Core.Engine, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/users/schedule"} ->
          ok(conn, %{"as_adjudicator" => [], "as_player" => [%{"id" => 11}]})

        {"GET", "/api/users/history"} ->
          ok(conn, %{"as_adjudicator" => [], "as_player" => []})

        {"GET", "/api/users/" <> _stats} ->
          ok(conn, nil)

        {"GET", "/api/events/11"} ->
          ok(conn, %{"id" => 11, "name" => "Thursday", "status" => "in_progress"})

        {"GET", "/api/events/11/rounds"} ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        {"GET", "/api/events/11/participants"} ->
          ok(conn, [
            %{"id" => 90, "display_name" => "Judy", "user_id" => 66},
            %{"id" => 22, "display_name" => "Anna", "user_id" => 55}
          ])

        {"GET", "/api/rounds/21/rooms"} ->
          ok(conn, [room(%{"motion_text" => "THW ban homework"}, "completed")])

        {"GET", "/api/events/11/feedback-questions"} ->
          ok(conn, [%{"key" => "accuracy"}, %{"key" => "reasoning"}])

        {"GET", "/api/events/11/feedback"} ->
          ok(conn, Agent.get(sent, & &1))

        {"POST", "/api/rooms/71/feedback"} ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          params = Jason.decode!(body)
          send(test_pid, {:feedback, params})

          record = %{
            "id" => 1,
            "room_id" => 71,
            "adjudicator_id" => params["adjudicator_id"],
            "issuer_team_id" => params["issuer_team_id"],
            "comment" => params["comment"],
            "answers" => params["answers"]
          }

          Agent.update(sent, &[record | &1])
          ok(conn, record)
      end
    end)
  end

  defp running_session(club),
    do:
      session_fixture(club,
        engine_event_id: 11,
        format: "aus",
        name: "Thursday",
        started_at: ~U[2026-10-09 18:00:00Z]
      )

  test "a speaker sees their room, side and role, the motion once it is out", %{conn: conn} do
    head = user_fixture(%{node_user_id: 9})
    club = club_fixture(head, %{engine_organisation_id: 3})
    running_session(club)
    anna = user_fixture(%{node_user_id: 55})
    stub_engine(self(), %{"motion_text" => "THW ban homework"})

    {:ok, _view, html} = conn |> init_test_session(%{user_id: anna.id}) |> live(~p"/me")

    assert html =~ "Now: R"
    assert html =~ "You speak for Opp: DLO."
    assert html =~ "your team"
    assert html =~ "Judy"
    assert html =~ "THW ban homework"
    assert html =~ ~s(phx-hook="PrepClock")
    # only the chair gets the form
    refute html =~ ~s(phx-submit="publish_motion")
  end

  test "the chair publishes the motion on My page; prep starts", %{conn: conn} do
    head = user_fixture(%{node_user_id: 9})
    club = club_fixture(head, %{engine_organisation_id: 3})
    running_session(club)
    judy = user_fixture(%{node_user_id: 66})
    stub_engine(self())

    {:ok, view, html} = conn |> init_test_session(%{user_id: judy.id}) |> live(~p"/me")
    assert html =~ "You adjudicate this room."
    assert html =~ "Publish motion"

    html =
      view
      |> form("#now-motion-71", %{motion_text: "THW ban homework", keyword: "school"})
      |> render_submit()

    assert_received {:motion, %{"motion_text" => "THW ban homework", "keyword" => "school"}}
    assert_received :prep
    assert html =~ "Motion published."
    assert html =~ "Update motion"
  end

  test "the chair fills the ballot on My page; a tie comes back with the scores kept", %{
    conn: conn
  } do
    head = user_fixture(%{node_user_id: 9})
    club = club_fixture(head, %{engine_organisation_id: 3})
    running_session(club)
    judy = user_fixture(%{node_user_id: 66})
    stub_engine(self(), %{"motion_text" => "THW ban homework"})

    {:ok, view, html} = conn |> init_test_session(%{user_id: judy.id}) |> live(~p"/me")
    assert html =~ ~s(id="now-ballot-71")
    assert html =~ "Enter all 6 scores"

    ballot = fn gov, opp ->
      %{
        "gov" => %{
          "PM" => %{"speaker" => "11", "score" => gov},
          "DPM" => %{"speaker" => "12", "score" => gov},
          "GA" => %{"speaker" => "13", "score" => gov}
        },
        "opp" => %{
          "LO" => %{"speaker" => "21", "score" => opp},
          "DLO" => %{"speaker" => "22", "score" => opp},
          "OA" => %{"speaker" => "23", "score" => opp}
        }
      }
    end

    # tied totals: refused, the typed scores stay
    html = view |> form("#now-ballot-71", %{ballot: ballot.("75", "75")}) |> render_submit()
    assert html =~ "Teams can&#39;t tie"
    assert html =~ ~s(value="75")
    refute_received {:scores, _}

    view |> form("#now-ballot-71", %{ballot: ballot.("74", "76")}) |> render_submit()

    assert_received {:scores, %{"teamRankings" => rankings, "speakerScores" => scores}}
    assert [%{"rank" => 1, "room_team_id" => 102}, %{"rank" => 2}] = rankings
    assert length(scores) == 6
    assert_received :confirmed
  end

  test "a member registers on My page, answering the club's question, then cancels", %{conn: conn} do
    head = user_fixture(%{node_user_id: 9})
    club = club_fixture(head, %{engine_organisation_id: 3})

    club =
      form_fields_fixture(club, [
        %{"label" => "University", "type" => "text", "required" => "yes", "scope" => "members"}
      ])

    uni = field_id(club, "University")
    anna = user_fixture(%{node_user_id: 55})
    membership_fixture(anna, club)
    session = session_fixture(club, engine_event_id: 12, name: "Friday")
    test_pid = self()
    {:ok, signed} = Agent.start_link(fn -> [] end)

    Req.Test.stub(Core.Engine, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/users/schedule"} ->
          event = if Agent.get(signed, & &1) == [], do: [], else: [%{"id" => 12}]
          ok(conn, %{"as_adjudicator" => [], "as_player" => event})

        {"GET", "/api/users/history"} ->
          ok(conn, %{"as_adjudicator" => [], "as_player" => []})

        {"GET", "/api/users/" <> _stats} ->
          ok(conn, nil)

        {"GET", "/api/events/12"} ->
          ok(conn, %{"id" => 12, "name" => "Friday", "status" => "scheduled"})

        {"GET", "/api/events/12/rounds"} ->
          ok(conn, [%{"id" => 22, "sequence" => 1}])

        {"GET", "/api/events/12/participants"} ->
          ok(conn, Agent.get(signed, & &1))

        {"GET", "/api/rounds/22/rooms"} ->
          ok(conn, [])

        {"POST", "/api/events/12/participants"} ->
          participant = %{
            "id" => 41,
            "user_id" => 55,
            "display_name" => "Anna",
            "role" => "speaker"
          }

          Agent.update(signed, fn _ -> [participant] end)
          send(test_pid, :signed_up)
          ok(conn, participant)

        {"PUT", "/api/events/12/participants/41"} ->
          ok(conn, %{"id" => 41})

        {"DELETE", "/api/events/12/participants/41"} ->
          Agent.update(signed, fn _ -> [] end)
          send(test_pid, :cancelled)
          ok(conn, %{})
      end
    end)

    {:ok, view, html} = conn |> init_test_session(%{user_id: anna.id}) |> live(~p"/me")
    assert html =~ ~s(id="me-registration")
    assert html =~ "Friday"

    # the club asks its members a question: the form opens inline
    html = view |> element(~s(button[phx-click="open_register"])) |> render_click()
    assert html =~ ~s(id="me-register-form")
    assert html =~ "University"
    refute_received :signed_up

    # an answer left empty is refused there, nothing signed up
    html = view |> form("#me-register-form", %{answers: %{uni => ""}}) |> render_submit()
    assert html =~ ~s(id="me-register-form")
    refute_received :signed_up

    html = view |> form("#me-register-form", %{answers: %{uni => "KPI"}}) |> render_submit()
    assert_received :signed_up
    assert html =~ "You are registered."
    assert html =~ "you are registered"

    view |> element(~s(button[phx-click="cancel_registration"])) |> render_click()
    assert_received :cancelled
    assert render(view) =~ "Registration cancelled."
    assert Cab.Sessions.get_by_uuid(session.uuid)
  end

  test "a speaker sends feedback on My page once the ballot is in; a refused one keeps the text",
       %{conn: conn} do
    head = user_fixture(%{node_user_id: 9})
    club = club_fixture(head, %{engine_organisation_id: 3})
    running_session(club)
    anna = user_fixture(%{node_user_id: 55})
    stub_feedback_engine(self())

    {:ok, view, html} = conn |> init_test_session(%{user_id: anna.id}) |> live(~p"/me")
    assert html =~ ~s(id="now-feedback-71")
    assert html =~ "Feedback on Judy"

    fields = fn accuracy ->
      %{"accuracy" => accuracy, "reasoning" => "7", "discussion" => "Clear call."}
    end

    html = view |> form("#now-feedback-71", fields.("")) |> render_submit()
    assert html =~ "Enter a whole number from 1 to 10."
    assert html =~ "Clear call."
    refute_received {:feedback, _}

    html = view |> form("#now-feedback-71", fields.("8")) |> render_submit()

    assert_received {:feedback,
                     %{
                       "adjudicator_id" => 90,
                       "issuer_team_id" => 1002,
                       "comment" => "Clear call."
                     }}

    assert html =~ "Feedback sent."
    assert html =~ "Your team sent feedback:"
    refute html =~ ~s(id="now-feedback-71")
  end

  test "a guest chair works on their link's hub: the seat, then the motion", %{conn: conn} do
    head = user_fixture(%{node_user_id: 9})
    club = club_fixture(head, %{engine_organisation_id: 3})
    session = running_session(club)
    guest = user_fixture(%{node_user_id: nil, name: "Judy", username: "guest-judy"})
    link = link_fixture(guest, session, participant_id: 90)
    stub_engine(self())

    {:ok, view, html} =
      conn |> init_test_session(%{user_id: guest.id}) |> live(~p"/l/#{link.code}/hub")

    assert html =~ "Personal link"
    assert html =~ "You adjudicate this room."
    refute html =~ ~s(id="me-stats")

    html =
      view
      |> form("#now-motion-71", %{motion_text: "THW trust guests"})
      |> render_submit()

    assert_received {:motion, %{"motion_text" => "THW trust guests"}}
    assert html =~ "Motion published."
  end

  test "a guest's link is not an account: My page sends them to sign in", %{conn: conn} do
    guest = user_fixture(%{node_user_id: 77})
    head = user_fixture(%{node_user_id: 9})
    club = club_fixture(head, %{engine_organisation_id: 3})
    session = running_session(club)
    link_fixture(guest, session, participant_id: 41)

    assert {:error, {:redirect, %{to: "/signin"}}} =
             conn |> init_test_session(%{user_id: guest.id}) |> live(~p"/me")
  end
end
