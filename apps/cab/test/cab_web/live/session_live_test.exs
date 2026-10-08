defmodule CabWeb.SessionLiveTest do
  # live pages run in their own process: the engine stub is shared,
  # so this module runs synchronously
  use CabWeb.ConnCase, async: false

  import Cab.Fixtures
  import Phoenix.LiveViewTest

  setup do
    Req.Test.set_req_test_to_shared()
    on_exit(fn -> Req.Test.set_req_test_to_private() end)
    :ok
  end

  defp ok(conn, data), do: Req.Test.json(conn, %{"status" => "success", "data" => data})

  # the engine answers from an Agent, so a test can change the world
  # and broadcast — exactly what a real write does
  defp stub_engine(signups, rooms \\ []) do
    {:ok, agent} = Agent.start_link(fn -> %{signups: signups, rooms: rooms} end)

    Req.Test.stub(Core.Engine, fn conn ->
      case conn.request_path do
        "/api/events/11" ->
          ok(conn, %{"id" => 11, "name" => "Live night", "status" => "scheduled"})

        "/api/events/11/rounds" ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        "/api/events/11/participants" ->
          ok(conn, Agent.get(agent, & &1.signups))

        "/api/rounds/21/rooms" ->
          ok(conn, Agent.get(agent, & &1.rooms))
      end
    end)

    agent
  end

  test "the session page updates live when someone registers", %{conn: conn} do
    head = user_fixture(%{node_user_id: 9})
    club = club_fixture(head, %{engine_organisation_id: 3})
    session = session_fixture(club, engine_event_id: 11)

    agent = stub_engine([%{"id" => 41, "role" => "speaker", "display_name" => "Anna"}])

    {:ok, view, html} = live(conn, ~p"/c/#{club.uuid}/s/#{session.uuid}")
    assert html =~ "Anna"
    refute html =~ "Bohdan"

    # a registration elsewhere changes the engine and announces it
    Agent.update(agent, fn world ->
      %{
        world
        | signups:
            world.signups ++ [%{"id" => 42, "role" => "speaker", "display_name" => "Bohdan"}]
      }
    end)

    Cab.Sessions.broadcast(session)

    assert render(view) =~ "Bohdan"
  end

  test "the room page shows the motion the moment it is published", %{conn: conn} do
    head = user_fixture(%{node_user_id: 9})
    club = club_fixture(head, %{engine_organisation_id: 3})
    session = session_fixture(club, engine_event_id: 11)

    room = %{"id" => 71, "status" => "pending", "Motion" => nil, "RoomTeams" => []}
    agent = stub_engine([], [room])

    {:ok, view, html} = live(conn, ~p"/c/#{club.uuid}/s/#{session.uuid}/rooms/71")
    assert html =~ "Not set yet"

    Agent.update(agent, fn world ->
      %{world | rooms: [%{room | "Motion" => %{"motion_text" => "THW go live"}}]}
    end)

    Cab.Sessions.broadcast(session)

    html = render(view)
    assert html =~ "THW go live"
    refute html =~ "Not set yet"
  end

  test "a confirmed ballot is the head's to edit, not the chair's", %{conn: conn} do
    head = user_fixture(%{node_user_id: 9})
    club = club_fixture(head, %{engine_organisation_id: 3})
    session = session_fixture(club, engine_event_id: 11)
    chair = user_fixture(%{node_user_id: 44})

    room = %{
      "id" => 71,
      "status" => "confirmed",
      "Motion" => %{"motion_text" => "THW done"},
      "RoomTeams" => [],
      "RoomAdjudicators" => [
        %{"role" => "chair", "EventParticipant" => %{"id" => 90, "user_id" => 44}}
      ]
    }

    stub_engine([], [room])
    path = ~p"/c/#{club.uuid}/s/#{session.uuid}/rooms/71"

    {:ok, _view, head_html} = live(init_test_session(conn, %{user_id: head.id}), path)
    assert head_html =~ "Edit ballot"

    {:ok, _view, chair_html} = live(init_test_session(conn, %{user_id: chair.id}), path)
    refute chair_html =~ "Edit ballot"
    refute chair_html =~ "Fill ballot"
  end
end
