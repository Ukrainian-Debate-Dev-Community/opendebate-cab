defmodule CabWeb.ApiFlowTest do
  use CabWeb.ConnCase, async: true

  import Cab.Fixtures

  defp log_in(conn, user), do: init_test_session(conn, %{user_id: user.id})

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
    club = club_fixture(head, %{engine_organisation_id: 3, name: "BP Club", city: "Kyiv"})
    %{conn: conn, head: head, club: club}
  end

  test "GET /api/v1/clubs/:uuid returns profile + history with winner",
       %{conn: conn, club: club} do
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
              "RoomTeams" => [%{"id" => 1, "rank" => 1, "Team" => %{"name" => "Ann & Bo"}}]
            }
          ])
      end
    end)

    data = conn |> get(~p"/api/v1/clubs/#{club.uuid}") |> json_response(200)
    assert data["uuid"] == club.uuid
    assert data["name"] == "BP Club"
    assert data["city"] == "Kyiv"
    assert [%{"id" => 11, "winner" => "Ann & Bo"}] = data["history"]
  end

  test "join request lifecycle over the API", %{conn: conn, club: club, head: head} do
    user = user_fixture()

    # anonymous cannot ask
    assert conn |> post(~p"/api/v1/clubs/#{club.uuid}/join-requests") |> json_response(401)

    created =
      conn
      |> log_in(user)
      |> post(~p"/api/v1/clubs/#{club.uuid}/join-requests")
      |> json_response(201)

    assert created["status"] == "pending"

    # duplicates rejected
    assert conn
           |> log_in(user)
           |> post(~p"/api/v1/clubs/#{club.uuid}/join-requests")
           |> json_response(422)

    # only the head may decide
    assert conn
           |> log_in(user)
           |> patch(~p"/api/v1/join-requests/#{created["id"]}", %{action: "approve"})
           |> json_response(403)

    approved =
      conn
      |> log_in(head)
      |> patch(~p"/api/v1/join-requests/#{created["id"]}", %{action: "approve"})
      |> json_response(200)

    assert approved["status"] == "approved"

    # bad action
    assert conn
           |> log_in(head)
           |> patch(~p"/api/v1/join-requests/#{created["id"]}", %{action: "boop"})
           |> json_response(422)
  end

  test "decline deletes the request", %{conn: conn, club: club, head: head} do
    user = user_fixture()
    {:ok, membership} = Cab.Clubs.request_join(user, club)

    declined =
      conn
      |> log_in(head)
      |> patch(~p"/api/v1/join-requests/#{membership.id}", %{action: "decline"})
      |> json_response(200)

    assert declined["status"] == "declined"
    assert Cab.Clubs.get_membership(membership.id) == nil
  end

  test "session lifecycle over the API", %{conn: conn, club: club, head: head} do
    member = user_fixture(%{node_user_id: 44})
    membership_fixture(member, club)

    stub(fn conn, params ->
      case {conn.method, conn.request_path} do
        {"POST", "/api/events/3"} ->
          ok(conn, %{"id" => 11, "name" => params["name"], "status" => "scheduled"})

        {"POST", "/api/events/11/rounds"} ->
          ok(conn, %{"id" => 21, "sequence" => 1})

        {"GET", "/api/events/11"} ->
          ok(conn, %{"id" => 11, "status" => "scheduled"})

        {"GET", "/api/events/11/rounds"} ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        {"GET", "/api/events/11/participants"} ->
          ok(conn, [])

        {"GET", "/api/rounds/21/rooms"} ->
          ok(conn, [])

        {"POST", "/api/events/11/participants"} ->
          ok(conn, %{"id" => 41, "role" => params["role"]})
      end
    end)

    created =
      conn
      |> log_in(head)
      |> post(~p"/api/v1/clubs/#{club.uuid}/sessions", %{name: "Tuesday"})
      |> json_response(201)

    assert created["engine_event_id"] == 11
    session_uuid = created["uuid"]

    state =
      conn |> log_in(member) |> get(~p"/api/v1/sessions/#{session_uuid}") |> json_response(200)

    assert state["stage"] == "signup"
    assert state["club_uuid"] == club.uuid

    signup =
      conn
      |> log_in(member)
      |> post(~p"/api/v1/sessions/#{session_uuid}/signups", %{as: "speak"})
      |> json_response(201)

    assert signup["role"] == "speaker"

    # bad kind
    assert conn
           |> log_in(member)
           |> post(~p"/api/v1/sessions/#{session_uuid}/signups", %{as: "watch"})
           |> json_response(422)

    # member cannot make rooms or finish
    assert conn
           |> log_in(member)
           |> post(~p"/api/v1/sessions/#{session_uuid}/rooms")
           |> json_response(403)

    assert conn
           |> log_in(member)
           |> post(~p"/api/v1/sessions/#{session_uuid}/finish")
           |> json_response(403)
  end

  test "motion and ballot act on rooms scoped by session_uuid",
       %{conn: conn, club: club} do
    judge = user_fixture(%{node_user_id: 77})
    membership_fixture(judge, club)
    speaker = user_fixture(%{node_user_id: 55})
    membership_fixture(speaker, club)
    session = session_fixture(club, engine_event_id: 11)

    room = %{
      "id" => 71,
      "status" => "judging",
      "RoomAdjudicators" => [
        %{"id" => 1, "role" => "chair", "EventParticipant" => %{"id" => 90, "user_id" => 77}}
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
                  "EventParticipant" => %{"id" => 300 + position * 2 - 2 + n}
                }
              end
          }
        end
    }

    stub(fn conn, params ->
      case {conn.method, conn.request_path} do
        {"POST", "/api/rooms/71/motion"} ->
          assert params["motion_text"] == "THW test APIs"
          ok(conn, %{"motion" => %{"id" => 31, "motion_text" => "THW test APIs"}})

        {"GET", "/api/events/11/rounds"} ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        {"GET", "/api/rounds/21/rooms"} ->
          ok(conn, [room])

        {"POST", "/api/rooms/71/scores"} ->
          Req.Test.json(conn, %{"status" => "success", "message" => "ok"})

        {"PATCH", "/api/rooms/71/confirm"} ->
          Req.Test.json(conn, %{"status" => "success", "message" => "ok"})
      end
    end)

    motion =
      conn
      |> log_in(judge)
      |> post(~p"/api/v1/rooms/71/motion", %{
        session_uuid: session.uuid,
        motion_text: "THW test APIs"
      })
      |> json_response(200)

    assert motion["motion"]["motion_text"] == "THW test APIs"

    scores = fn totals ->
      Enum.flat_map(totals, fn {position, total} ->
        [
          %{
            position: position,
            speaker_participant_id: 300 + position * 2 - 1,
            iron: false,
            score: total - 75.0
          },
          %{
            position: position,
            speaker_participant_id: 300 + position * 2,
            iron: false,
            score: 75.0
          }
        ]
      end)
    end

    # a plain member (not the room's judge, not the head) -> 403
    assert conn
           |> log_in(speaker)
           |> post(~p"/api/v1/rooms/71/ballot", %{
             session_uuid: session.uuid,
             scores: scores.([{1, 151.5}, {2, 157.5}, {3, 149.5}, {4, 147.5}])
           })
           |> json_response(403)

    # tied team totals -> 422 naming the total
    tied =
      conn
      |> log_in(judge)
      |> post(~p"/api/v1/rooms/71/ballot", %{
        session_uuid: session.uuid,
        scores: scores.([{1, 151.0}, {2, 151.0}, {3, 149.5}, {4, 147.5}])
      })
      |> json_response(422)

    assert tied["details"]["scores"] =~ "151"

    ballot =
      conn
      |> log_in(judge)
      |> post(~p"/api/v1/rooms/71/ballot", %{
        session_uuid: session.uuid,
        scores: scores.([{1, 151.5}, {2, 157.5}, {3, 149.5}, {4, 147.5}])
      })
      |> json_response(200)

    assert ballot["status"] == "confirmed"
  end

  test "finish completes the session", %{conn: conn, club: club, head: head} do
    session = session_fixture(club, engine_event_id: 11)

    stub(fn conn, _params ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/events/11/rounds"} ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        {"PUT", "/api/rounds/21"} ->
          ok(conn, %{"id" => 21, "status" => "completed"})

        {"PUT", "/api/events/11"} ->
          ok(conn, %{"id" => 11, "status" => "completed"})
      end
    end)

    finished =
      conn
      |> log_in(head)
      |> post(~p"/api/v1/sessions/#{session.uuid}/finish")
      |> json_response(200)

    assert finished["status"] == "completed"
  end

  test "engine errors surface as 422 with the message", %{conn: conn, club: club, head: head} do
    stub(fn conn, _params ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(403, ~s({"status":"fail","message":"engine says no"}))
    end)

    error =
      conn
      |> log_in(head)
      |> post(~p"/api/v1/clubs/#{club.uuid}/sessions", %{})
      |> json_response(422)

    assert error["error"] == "engine says no"
  end
end
