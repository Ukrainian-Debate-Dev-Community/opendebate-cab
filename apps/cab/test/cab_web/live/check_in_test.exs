defmodule CabWeb.CheckInTest do
  @moduledoc """
  Check-in: the head marks who is here on the spar's people table - one
  person, the picked ones or everyone - in the engine's own check-in;
  the draw then counts those checked in and marks the rest.
  """
  # the owner page is a LiveView in its own process: the engine stub
  # is shared, so this module runs synchronously
  use CabWeb.ConnCase, async: false

  import Cab.Fixtures
  import Phoenix.LiveViewTest

  alias Cab.Sessions

  setup %{conn: conn} do
    Req.Test.set_req_test_to_shared()
    on_exit(fn -> Req.Test.set_req_test_to_private() end)

    head = user_fixture(%{node_user_id: 9})
    club = club_fixture(head, %{engine_organisation_id: 3})
    member = user_fixture(%{node_user_id: 44})
    membership_fixture(member, club)
    session = session_fixture(club, engine_event_id: 11)

    signups =
      for id <- 1..18,
          do: %{
            "id" => id,
            "user_id" => nil,
            "display_name" => "Person #{id}",
            "checked_in" => false
          }

    {:ok, engine} = Agent.start_link(fn -> signups end)
    stub_engine(engine, self())

    %{
      conn: conn,
      head: head,
      member: member,
      club: club,
      session: %{session | club: club},
      engine: engine
    }
  end

  defp ok(conn, data), do: Req.Test.json(conn, %{"status" => "success", "data" => data})

  defp stub_engine(engine, test_pid) do
    Req.Test.stub(Core.Engine, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      params = if body == "", do: %{}, else: Jason.decode!(body)

      case {conn.method, conn.request_path} do
        {"GET", "/api/events/11"} ->
          ok(conn, %{"id" => 11, "name" => "Thursday", "status" => "scheduled"})

        {"GET", "/api/events/11/rounds"} ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        {"GET", "/api/events/11/participants"} ->
          ok(conn, Agent.get(engine, & &1))

        {"GET", "/api/rounds/21/rooms"} ->
          ok(conn, [])

        {"PATCH", "/api/events/11/check-ins"} ->
          send(test_pid, {:check_ins, params})
          mark(engine, params["participant_ids"], params["status"])
          ok(conn, nil)

        {"PATCH", "/api/events/11/participants/" <> rest} ->
          [id, "check-in"] = String.split(rest, "/")
          send(test_pid, {:check_in, String.to_integer(id), params["checked_in"]})
          mark(engine, [String.to_integer(id)], params["checked_in"])
          ok(conn, %{})
      end
    end)
  end

  defp mark(engine, ids, here?) do
    Agent.update(engine, fn signups ->
      for p <- signups, do: if(p["id"] in ids, do: %{p | "checked_in" => here?}, else: p)
    end)
  end

  defp head_page(conn, head, club, session, stage \\ "registration") do
    conn
    |> init_test_session(%{user_id: head.id})
    |> live(~p"/c/#{club.uuid}/owner/s/#{session.uuid}?#{[stage: stage]}")
  end

  test "the head checks people in one by one, the picked ones, then everyone",
       %{conn: conn, head: head, club: club, session: session} do
    {:ok, view, html} = head_page(conn, head, club, session)
    assert html =~ "Check-in"
    assert html =~ "0 of 18 checked in"

    view |> element(~s(button[phx-click="check_in"][phx-value-id="1"])) |> render_click()
    assert_received {:check_in, 1, true}
    assert render(view) =~ "1 of 18 checked in"

    # and back: a toggle
    view |> element(~s(button[phx-click="check_in"][phx-value-id="1"])) |> render_click()
    assert_received {:check_in, 1, false}

    view |> element(~s(input[phx-click="toggle"][phx-value-id="2"])) |> render_click()
    view |> element(~s(input[phx-click="toggle"][phx-value-id="3"])) |> render_click()
    view |> element(~s(button[phx-click="check_in_selected"])) |> render_click()
    assert_received {:check_ins, %{"status" => true, "participant_ids" => ids}}
    assert Enum.sort(ids) == [2, 3]

    view |> element(~s(button[phx-click="check_in_all"])) |> render_click()
    assert_received {:check_ins, %{"status" => true, "participant_ids" => rest}}
    assert length(rest) == 16
    html = render(view)
    assert html =~ "18 of 18 checked in"
    refute html =~ ~s(phx-click="check_in_all")
  end

  test "the draw counts those checked in and marks the rest",
       %{conn: conn, head: head, club: club, session: session, engine: engine} do
    # 18 registered: two BP rooms; nine checked in: one
    {:ok, state} = Sessions.state(session)
    assert Sessions.rooms_for(session, state.signups) == 2

    mark(engine, Enum.to_list(1..9), true)
    {:ok, state} = Sessions.state(session)
    assert Sessions.rooms_for(session, state.signups) == 1
    assert length(Sessions.present(state.signups)) == 9

    {:ok, _view, html} = head_page(conn, head, club, session, "rooms")
    assert html =~ "1 room(s), count automatic"
    # the ones not checked in stay placeable, marked absent
    assert html =~ ~s(class="chip absent")
  end

  test "only the head checks in, and not once the spar is finished",
       %{member: member, head: head, session: session} do
    assert {:error, :forbidden} = Sessions.check_in(member, session, [1], true)

    done = %{session | finished_at: DateTime.utc_now(:second)}
    assert {:error, :conflict, _message} = Sessions.check_in(head, done, [1], true)
    refute_received {:check_in, _, _}
  end
end
