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

  test "the live allocator: drops update the server draft, Start turns it into rooms",
       %{conn: conn} do
    head = user_fixture(%{node_user_id: 9})
    club = club_fixture(head, %{engine_organisation_id: 3})
    session = session_fixture(club, engine_event_id: 11, engine_round_id: 21)
    test_pid = self()

    signups =
      [%{"id" => 99, "role" => "adjudicator", "display_name" => "Judge J"}] ++
        for(i <- 1..8, do: %{"id" => i, "role" => "speaker", "display_name" => "S#{i}"})

    Req.Test.stub(Core.Engine, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/events/11"} ->
          ok(conn, %{"id" => 11, "name" => "Live night", "status" => "scheduled"})

        {"GET", "/api/events/11/rounds"} ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        {"GET", "/api/events/11/participants"} ->
          ok(conn, signups)

        {"GET", "/api/rounds/21/rooms"} ->
          ok(conn, [])

        {"POST", "/api/rounds/21/rooms"} ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          send(test_pid, {:room, Jason.decode!(body)})
          ok(conn, %{"id" => 71})
      end
    end)

    {:ok, view, html} =
      live(
        init_test_session(conn, %{user_id: head.id}),
        ~p"/c/#{club.uuid}/owner/s/#{session.uuid}"
      )

    assert html =~ ~s(phx-hook="Allocator")

    # each drop is one event; the server keeps the draft
    slots = ~w(1:og:1 1:og:2 1:oo:1 1:oo:2 1:cg:1 1:cg:2 1:co:1 1:co:2)

    for {slot, id} <- Enum.zip(slots, 1..8) do
      render_hook(view, "place", %{"id" => id, "slot" => slot})
    end

    render_hook(view, "place", %{"id" => 99, "slot" => "1:judge"})

    draft = Cab.Sessions.get_by_uuid(session.uuid).draft_allocation
    assert map_size(draft) == 9
    assert draft["1:judge"] == 99

    # a judge dropped on a speaker slot is refused with words
    assert render_hook(view, "place", %{"id" => 99, "slot" => "1:og:1"}) =~
             "judges cannot take a speaker slot"

    # Start session: the draft becomes exactly this room
    html = view |> element("#allocator-form") |> render_submit()
    assert html =~ "session started — 1 room(s)"
    assert_received {:room, %{"teams" => teams}}
    assert Enum.map(teams, & &1["participant_ids"]) == [[1, 2], [3, 4], [5, 6], [7, 8]]
    assert Cab.Sessions.get_by_uuid(session.uuid).draft_allocation == %{}
  end
end
