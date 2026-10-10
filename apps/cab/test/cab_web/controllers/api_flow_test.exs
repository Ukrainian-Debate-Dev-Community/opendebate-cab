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
    done =
      session_fixture(club,
        engine_event_id: 11,
        name: "Night 1",
        finished_at: ~U[2026-10-08 20:00:00Z],
        winner_name: "Ann & Bo"
      )

    stub(fn _conn, _params -> raise "the club profile must not call the engine" end)

    data = conn |> get(~p"/api/v1/clubs/#{club.uuid}") |> json_response(200)
    assert data["uuid"] == club.uuid
    assert data["name"] == "BP Club"
    assert data["city"] == "Kyiv"

    assert [%{"session_uuid" => uuid, "name" => "Night 1", "winner" => "Ann & Bo"}] =
             data["history"]

    assert uuid == done.uuid
  end

  test "join request lifecycle over the API", %{conn: conn, club: club, head: head} do
    user = user_fixture()

    # anonymous cannot ask
    assert conn |> post(~p"/api/v1/clubs/#{club.uuid}/join-requests") |> json_response(401)

    # the two answers are REQUIRED — a bare request is rejected
    missing =
      conn
      |> log_in(user)
      |> post(~p"/api/v1/clubs/#{club.uuid}/join-requests")
      |> json_response(422)

    assert missing["details"]["message"]
    assert missing["details"]["contact"]

    created =
      conn
      |> log_in(user)
      |> post(~p"/api/v1/clubs/#{club.uuid}/join-requests", %{
        message: "I debated at school",
        contact: "@tg"
      })
      |> json_response(201)

    assert created["status"] == "pending"
    assert created["message"] == "I debated at school"
    assert created["contact"] == "@tg"

    # duplicates rejected
    assert conn
           |> log_in(user)
           |> post(~p"/api/v1/clubs/#{club.uuid}/join-requests", %{
             message: "again",
             contact: "@tg"
           })
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

    {:ok, membership} =
      Cab.Clubs.request_join(user, club, %{"message" => "hi", "contact" => "@tg"})

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

        {"GET", "/api/events/11/feedback-questions"} ->
          Req.Test.json(conn, %{"status" => "success", "data" => []})

        {"POST", "/api/events/11/feedback-questions"} ->
          Req.Test.json(conn, %{"status" => "success", "data" => %{"id" => 1}})

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

    # the engine's own ids stay out of the API
    refute Map.has_key?(created, "engine_event_id")
    session_uuid = created["uuid"]

    state =
      conn |> log_in(member) |> get(~p"/api/v1/sessions/#{session_uuid}") |> json_response(200)

    assert state["stage"] == "signup"
    assert state["club_uuid"] == club.uuid

    signup =
      conn
      |> log_in(member)
      |> post(~p"/api/v1/sessions/#{session_uuid}/signups", %{})
      |> json_response(201)

    assert is_integer(signup["participant_id"])
    refute Map.has_key?(signup, "role")

    # member cannot make rooms or finish
    assert conn
           |> log_in(member)
           |> post(~p"/api/v1/sessions/#{session_uuid}/rooms", %{"rooms" => []})
           |> json_response(403)

    # nothing is ever allocated automatically: no spec, no rooms
    assert conn
           |> log_in(head)
           |> post(~p"/api/v1/sessions/#{session_uuid}/rooms")
           |> json_response(422)
           |> get_in(["details", "rooms"]) =~ "nothing is allocated automatically"

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
      "Motion" => %{"motion_text" => "THW test", "created_at" => "2026-10-09T18:00:00Z"},
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

        {"GET", "/api/events/11"} ->
          ok(conn, %{"id" => 11, "name" => "API night", "status" => "scheduled"})

        {"GET", "/api/events/11/participants"} ->
          ok(conn, [])

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

    assert motion["motion"]["text"] == "THW test APIs"

    # the session read: names and results for everyone, ids only for
    # those who act on them (here the room's chair)
    public =
      conn
      |> log_in(speaker)
      |> get(~p"/api/v1/sessions/#{session.uuid}")
      |> json_response(200)

    [room] = public["rooms"]
    refute Map.has_key?(room, "id")
    refute public |> Map.has_key?("event")
    refute Enum.any?(public["signups"], &Map.has_key?(&1, "id"))
    assert [%{"side" => "OG", "speakers" => [first | _]} | _] = room["teams"]
    refute Map.has_key?(first, "id")
    refute inspect(public) =~ "user_id"

    chaired =
      conn
      |> log_in(judge)
      |> get(~p"/api/v1/sessions/#{session.uuid}")
      |> json_response(200)

    [room] = chaired["rooms"]
    assert room["id"] == 71
    assert [%{"speakers" => [%{"id" => 301} | _]} | _] = room["teams"]

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
             scores: scores.([{1, 151}, {2, 157}, {3, 149}, {4, 147}])
           })
           |> json_response(403)

    # tied team totals -> 422 naming the total
    tied =
      conn
      |> log_in(judge)
      |> post(~p"/api/v1/rooms/71/ballot", %{
        session_uuid: session.uuid,
        scores: scores.([{1, 151}, {2, 151}, {3, 149}, {4, 147}])
      })
      |> json_response(422)

    assert tied["details"]["scores"] =~ "151"

    ballot =
      conn
      |> log_in(judge)
      |> post(~p"/api/v1/rooms/71/ballot", %{
        session_uuid: session.uuid,
        scores: scores.([{1, 151}, {2, 157}, {3, 149}, {4, 147}])
      })
      |> json_response(200)

    assert ballot["status"] == "confirmed"
  end

  test "finish completes the session", %{conn: conn, club: club, head: head} do
    session = session_fixture(club, engine_event_id: 11)

    stub(fn conn, _params ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/events/11"} ->
          ok(conn, %{"id" => 11, "name" => "Night", "status" => "scheduled"})

        {"GET", "/api/events/11/participants"} ->
          ok(conn, [])

        {"GET", "/api/rounds/21/rooms"} ->
          ok(conn, [%{"id" => 71, "status" => "confirmed", "RoomTeams" => []}])

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

  test "close-signups / reopen-signups flip the stage; the 409 gates hold",
       %{conn: conn, club: club, head: head} do
    member = user_fixture(%{node_user_id: 44})
    membership_fixture(member, club)
    session = session_fixture(club, engine_event_id: 11)

    stub(fn conn, _params ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/events/11"} -> ok(conn, %{"id" => 11, "status" => "scheduled"})
        {"GET", "/api/events/11/rounds"} -> ok(conn, [%{"id" => 21, "sequence" => 1}])
        {"GET", "/api/events/11/participants"} -> ok(conn, [])
        {"GET", "/api/rounds/21/rooms"} -> ok(conn, [])
      end
    end)

    # head-only
    assert conn
           |> log_in(member)
           |> post(~p"/api/v1/sessions/#{session.uuid}/close-signups")
           |> json_response(403)

    # rooms before close -> 409 (the graph gate)
    assert conn
           |> log_in(head)
           |> post(~p"/api/v1/sessions/#{session.uuid}/rooms", %{
             "rooms" => [%{"adjudicator_participant_id" => 99, "teams" => [[1], [2], [3], [4]]}]
           })
           |> json_response(409)
           |> Map.fetch!("error") =~ "after registration closes"

    # reopen before close -> 409
    assert conn
           |> log_in(head)
           |> post(~p"/api/v1/sessions/#{session.uuid}/reopen-signups")
           |> json_response(409)

    assert conn
           |> log_in(head)
           |> post(~p"/api/v1/sessions/#{session.uuid}/close-signups")
           |> json_response(200) == %{"uuid" => session.uuid, "stage" => "closed"}

    # signup after close -> 409; closing twice -> 409
    assert conn
           |> log_in(member)
           |> post(~p"/api/v1/sessions/#{session.uuid}/signups", %{as: "speak"})
           |> json_response(409)
           |> Map.fetch!("error") =~ "Registration is not open"

    assert conn
           |> log_in(head)
           |> post(~p"/api/v1/sessions/#{session.uuid}/close-signups")
           |> json_response(409)

    assert conn
           |> log_in(head)
           |> post(~p"/api/v1/sessions/#{session.uuid}/reopen-signups")
           |> json_response(200) == %{"uuid" => session.uuid, "stage" => "signup"}

    assert conn
           |> log_in(head)
           |> get(~p"/api/v1/sessions/#{session.uuid}")
           |> json_response(200)
           |> Map.fetch!("stage") == "signup"
  end

  test "signups on behalf and signup removal", %{conn: conn, club: club, head: head} do
    member = user_fixture(%{node_user_id: 44})
    membership_fixture(member, club)
    target = user_fixture(%{node_user_id: 66})
    membership_fixture(target, club)
    session = session_fixture(club, engine_event_id: 11)

    stub(fn conn, params ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/events/11"} ->
          ok(conn, %{"id" => 11, "status" => "scheduled"})

        {"GET", "/api/events/11/rounds"} ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        {"GET", "/api/rounds/21/rooms"} ->
          ok(conn, [])

        {"POST", "/api/events/11/participants"} ->
          ok(conn, %{"id" => 43, "role" => params["role"]})

        {"GET", "/api/events/11/participants"} ->
          ok(conn, [
            %{"id" => 41, "user_id" => 44, "role" => "speaker"},
            %{"id" => 43, "user_id" => 66, "role" => "speaker"}
          ])

        {"PUT", "/api/events/11/participants/" <> _renamed} ->
          Req.Test.json(conn, %{"status" => "success", "data" => %{}})

        {"DELETE", "/api/events/11/participants/" <> _pid} ->
          Req.Test.json(conn, %{"status" => "success", "message" => "Participant archived."})
      end
    end)

    # username is a head-only switch
    assert conn
           |> log_in(member)
           |> post(~p"/api/v1/sessions/#{session.uuid}/signups", %{
             as: "speak",
             username: target.username
           })
           |> json_response(403)

    added =
      conn
      |> log_in(head)
      |> post(~p"/api/v1/sessions/#{session.uuid}/signups", %{
        as: "speak",
        username: target.username
      })
      |> json_response(201)

    assert added["participant_id"] == 43
    assert added["username"] == target.username

    # a member cannot remove someone else's signup, only their own
    assert conn
           |> log_in(member)
           |> delete(~p"/api/v1/sessions/#{session.uuid}/signups/43")
           |> json_response(403)

    assert conn
           |> log_in(member)
           |> delete(~p"/api/v1/sessions/#{session.uuid}/signups/41")
           |> json_response(200) == %{"participant_id" => 41, "status" => "removed"}

    # the head removes anyone
    assert conn
           |> log_in(head)
           |> delete(~p"/api/v1/sessions/#{session.uuid}/signups/43")
           |> json_response(200) == %{"participant_id" => 43, "status" => "removed"}
  end

  test "explicit composition and rooms rebuild are head-only",
       %{conn: conn, club: club, head: head} do
    member = user_fixture(%{node_user_id: 44})
    membership_fixture(member, club)
    session = closed_session_fixture(club, engine_event_id: 11)

    composition = %{
      "rooms" => [
        %{
          "adjudicator_participant_id" => 99,
          "teams" => [[1, 2], [3, 4], [5, 6], [7, 8]]
        }
      ]
    }

    for {method, path, body} <- [
          {:post, ~p"/api/v1/sessions/#{session.uuid}/rooms", composition},
          {:delete, ~p"/api/v1/sessions/#{session.uuid}/rooms", nil},
          {:delete, ~p"/api/v1/sessions/#{session.uuid}", nil}
        ] do
      conn = log_in(conn, member)

      response =
        case {method, body} do
          {:post, body} -> post(conn, path, body)
          {:delete, nil} -> delete(conn, path)
          {:patch, body} -> patch(conn, path, body)
        end

      assert json_response(response, 403)["error"] == "forbidden"
    end

    # composition runs against the :closed state (no rooms yet)
    stub(fn conn, _params ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/events/11"} ->
          ok(conn, %{"id" => 11, "status" => "scheduled"})

        {"GET", "/api/events/11/rounds"} ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        {"GET", "/api/events/11/participants"} ->
          ok(
            conn,
            for id <- 1..8 do
              %{"id" => id, "role" => "speaker", "display_name" => "S#{id}"}
            end ++ [%{"id" => 99, "role" => "adjudicator", "display_name" => "J"}]
          )

        {"GET", "/api/rounds/21/rooms"} ->
          ok(conn, [])

        {"POST", "/api/rounds/21/rooms"} ->
          ok(conn, %{"id" => 71})
      end
    end)

    created =
      conn
      |> log_in(head)
      |> post(~p"/api/v1/sessions/#{session.uuid}/rooms", composition)
      |> json_response(201)

    assert created["rooms_created"] == 1

    # a bad composition is a 422 with the reason under details.rooms
    bad =
      put_in(composition["rooms"], [%{"adjudicator_participant_id" => 1, "teams" => [[1, 2]]}])

    assert conn
           |> log_in(head)
           |> post(~p"/api/v1/sessions/#{session.uuid}/rooms", bad)
           |> json_response(422)
           |> get_in(["details", "rooms"]) =~ "teams of one or two speakers"

    # rebuild: the room (and its temporary teams) go away
    stub(fn conn, _params ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/events/11/rounds"} ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        {"GET", "/api/rounds/21/rooms"} ->
          ok(conn, [%{"id" => 71, "status" => "pending"}])

        {"DELETE", "/api/rooms/71"} ->
          Req.Test.json(conn, %{"status" => "success", "message" => "Room archived."})
      end
    end)

    assert conn
           |> log_in(head)
           |> delete(~p"/api/v1/sessions/#{session.uuid}/rooms")
           |> json_response(200) == %{"rooms_deleted" => 1}
  end

  test "session cancel removes the gateway row", %{conn: conn, club: club, head: head} do
    session = session_fixture(club, engine_event_id: 11)

    stub(fn conn, _params ->
      case {conn.method, conn.request_path} do
        {"DELETE", "/api/events/11"} ->
          Req.Test.json(conn, %{"status" => "success", "message" => "Event archived."})
      end
    end)

    cancelled =
      conn
      |> log_in(head)
      |> delete(~p"/api/v1/sessions/#{session.uuid}")
      |> json_response(200)

    assert cancelled == %{"uuid" => session.uuid, "status" => "cancelled"}

    # the row is gone — the uuid no longer resolves
    assert conn
           |> log_in(head)
           |> get(~p"/api/v1/sessions/#{session.uuid}")
           |> json_response(404)
  end

  test "club management: PATCH profile and member removal", %{conn: conn, club: club, head: head} do
    member = user_fixture(%{node_user_id: 44})
    membership_fixture(member, club)

    # member gets 403 on both
    assert conn
           |> log_in(member)
           |> patch(~p"/api/v1/clubs/#{club.uuid}", %{name: "Nope"})
           |> json_response(403)

    assert conn
           |> log_in(member)
           |> delete(~p"/api/v1/clubs/#{club.uuid}/members/#{member.id}")
           |> json_response(403)

    updated =
      conn
      |> log_in(head)
      |> patch(~p"/api/v1/clubs/#{club.uuid}", %{
        name: "Renamed Club",
        city: "Lviv",
        meeting_info: "Thursdays 18:30",
        description: "BP club",
        contacts: "@tg"
      })
      |> json_response(200)

    assert updated["name"] == "Renamed Club"
    assert updated["city"] == "Lviv"
    assert updated["meeting_info"] == "Thursdays 18:30"
    assert updated["description"] == "BP club"
    assert updated["contacts"] == "@tg"

    # the roster carries user_id so removal is addressable
    members =
      conn |> log_in(head) |> get(~p"/api/v1/clubs/#{club.uuid}/members") |> json_response(200)

    assert Enum.any?(members["members"], &(&1["user_id"] == member.id))

    assert conn
           |> log_in(head)
           |> delete(~p"/api/v1/clubs/#{club.uuid}/members/#{member.id}")
           |> json_response(200) == %{"user_id" => member.id, "status" => "removed"}

    # the head's own row is protected
    protected =
      conn
      |> log_in(head)
      |> delete(~p"/api/v1/clubs/#{club.uuid}/members/#{head.id}")
      |> json_response(422)

    assert protected["error"] =~ "head cannot be removed"
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
