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
  defp room(motion) do
    %{
      "id" => 71,
      "status" => "pending",
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
          "RoomSpeakers" => [
            speaker(1, 11, "Gov One"),
            speaker(2, 12, "Gov Two"),
            speaker(3, 13, "Gov Three")
          ]
        },
        %{
          "id" => 102,
          "position" => 2,
          "RoomSpeakers" => [
            speaker(4, 21, "Opp One"),
            speaker(5, 22, "Anna", 55),
            speaker(6, 23, "Opp Three")
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
          ok(conn, [%{"id" => 90, "display_name" => "Judy", "user_id" => 66}])

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
