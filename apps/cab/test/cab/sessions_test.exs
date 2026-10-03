defmodule Cab.SessionsTest do
  use Cab.DataCase, async: true

  import Cab.Fixtures

  alias Cab.Sessions

  defp stub(fun) do
    Req.Test.stub(Core.Engine, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      params = if body == "", do: %{}, else: Jason.decode!(body)
      fun.(conn, params)
    end)
  end

  defp ok(conn, data), do: Req.Test.json(conn, %{"status" => "success", "data" => data})

  defp claims(conn) do
    ["Bearer " <> token] = Plug.Conn.get_req_header(conn, "authorization")
    signer = Joken.Signer.create("HS256", "test-engine-secret")
    {:ok, claims} = Joken.verify(token, signer)
    claims
  end

  setup do
    head = user_fixture(%{node_user_id: 9})
    club = club_fixture(head, %{engine_organisation_id: 3})
    %{head: head, club: club}
  end

  test "open/3 creates event + one round + the gateway row", %{head: head, club: club} do
    stub(fn conn, params ->
      case {conn.method, conn.request_path} do
        {"POST", "/api/events/3"} ->
          assert params["name"] == "Tuesday night"
          ok(conn, %{"id" => 11, "name" => "Tuesday night", "status" => "scheduled"})

        {"POST", "/api/events/11/rounds"} ->
          assert params == %{"name" => "Club round", "sequence" => 1}
          ok(conn, %{"id" => 21, "sequence" => 1})
      end
    end)

    assert {:ok, session} = Sessions.open(head, club, "Tuesday night")
    assert session.engine_event_id == 11
    assert session.opened_by_user_id == head.id
    assert Sessions.get_for_club(club, session.uuid).id == session.id
  end

  test "signup registers self as speaker or adjudicator", %{club: club} do
    user = user_fixture(%{node_user_id: 44, name: "Ann B"})
    session = session_fixture(club, engine_event_id: 11)

    stub(fn conn, params ->
      assert conn.request_path == "/api/events/11/participants"

      assert params == %{
               "display_name" => "Ann B",
               "role" => "adjudicator",
               "user_id" => 44
             }

      ok(conn, %{"id" => 41, "role" => "adjudicator"})
    end)

    assert {:ok, %{"id" => 41}} = Sessions.signup(user, session, "judge")
  end

  test "state/1 derives the stage from engine data", %{club: club} do
    session = session_fixture(club, engine_event_id: 11)

    for {event_status, rooms, expected} <- [
          {"scheduled", [], :signup},
          {"scheduled", [%{"id" => 71, "status" => "pending"}], :running},
          {"completed", [%{"id" => 71, "status" => "confirmed"}], :done}
        ] do
      stub(fn conn, _params ->
        case conn.request_path do
          "/api/events/11" -> ok(conn, %{"id" => 11, "status" => event_status})
          "/api/events/11/rounds" -> ok(conn, [%{"id" => 21, "sequence" => 1}])
          "/api/events/11/participants" -> ok(conn, [%{"id" => 41, "role" => "speaker"}])
          "/api/rounds/21/rooms" -> ok(conn, rooms)
        end
      end)

      assert {:ok, state} = Sessions.state(session)
      assert state.stage == expected
      assert state.signups == [%{"id" => 41, "role" => "speaker"}]
    end
  end

  test "make_rooms pairs attendance into teams and rooms with judge chairs",
       %{head: head, club: club} do
    session = session_fixture(club, engine_event_id: 11)

    speakers =
      for id <- 1..8 do
        %{"id" => id, "role" => "speaker", "display_name" => "Speaker #{id}"}
      end

    judges = [%{"id" => 99, "role" => "adjudicator", "display_name" => "Judge"}]

    proposals =
      for n <- 0..3 do
        %{
          "name" => "Random Team #{n + 1}",
          "participant_ids" => [2 * n + 1, 2 * n + 2],
          "participants" => [
            %{"display_name" => "Speaker #{2 * n + 1}"},
            %{"display_name" => "Speaker #{2 * n + 2}"}
          ]
        }
      end

    test_pid = self()

    stub(fn conn, params ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/events/11/rounds"} ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        {"GET", "/api/events/11/participants"} ->
          ok(conn, speakers ++ judges)

        {"GET", "/api/events/11/teams/auto-generate"} ->
          ok(conn, %{"total_free_speakers" => 8, "proposed_teams" => proposals})

        {"POST", "/api/events/11/teams"} ->
          send(test_pid, {:team, params["name"], params["participant_ids"]})
          ok(conn, %{"id" => 50 + hd(params["participant_ids"])})

        {"POST", "/api/rounds/21/rooms"} ->
          send(test_pid, {:room, params})
          ok(conn, %{"id" => 71})
      end
    end)

    assert {:ok, 1} = Sessions.make_rooms(head, session)

    assert_received {:team, "Speaker & Speaker", [1, 2]}
    assert_received {:room, room_params}
    assert room_params["format_id"] == 1
    assert [%{"participant_id" => 99, "role" => "chair"}] = room_params["adjudicators"]

    assert [
             %{"team_id" => 51, "position" => 1},
             %{"team_id" => 53, "position" => 2},
             %{"team_id" => 55, "position" => 3},
             %{"team_id" => 57, "position" => 4}
           ] = room_params["teams"]
  end

  test "make_rooms refuses partial rooms and missing judges", %{head: head, club: club} do
    session = session_fixture(club, engine_event_id: 11)

    stub(fn conn, _params ->
      case conn.request_path do
        "/api/events/11/rounds" -> ok(conn, [%{"id" => 21, "sequence" => 1}])
        "/api/events/11/participants" -> ok(conn, [%{"id" => 1, "role" => "speaker"}])
      end
    end)

    assert {:error, "need speakers in multiples of 8" <> _} = Sessions.make_rooms(head, session)

    stub(fn conn, _params ->
      case conn.request_path do
        "/api/events/11/rounds" ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        "/api/events/11/participants" ->
          ok(conn, for(id <- 1..8, do: %{"id" => id, "role" => "speaker"}))
      end
    end)

    assert {:error, "need at least 1 judge(s)" <> _} = Sessions.make_rooms(head, session)
  end

  test "pick_winner submits the ordered synthetic ballot and confirms",
       %{club: club} do
    judge = user_fixture(%{node_user_id: 77})
    session = session_fixture(club, engine_event_id: 11)

    room = %{
      "id" => 71,
      "status" => "judging",
      "RoomTeams" =>
        for position <- 1..4 do
          %{
            "id" => 100 + position,
            "position" => position,
            "RoomSpeakers" => [
              %{"id" => 200 + position * 2 - 1},
              %{"id" => 200 + position * 2}
            ]
          }
        end
    }

    test_pid = self()

    stub(fn conn, params ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/events/11/rounds"} ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        {"GET", "/api/rounds/21/rooms"} ->
          ok(conn, [room])

        {"POST", "/api/rooms/71/scores"} ->
          # the ballot goes in as the judge (engine chair guard applies)
          assert %{"id" => 77} = claims(conn)
          send(test_pid, {:scores, params})
          Req.Test.json(conn, %{"status" => "success", "message" => "ok"})

        {"PATCH", "/api/rooms/71/confirm"} ->
          # confirm is owner-only in the engine -> runs as the club head
          assert %{"id" => 9} = claims(conn)
          send(test_pid, :confirmed)
          Req.Test.json(conn, %{"status" => "success", "message" => "ok"})
      end
    end)

    # team at position 3 wins
    assert :ok = Sessions.pick_winner(judge, session, 71, 103)

    assert_received {:scores, params}

    # winner first, then table order — a strict 1..4 permutation
    assert params["teamRankings"] == [
             %{"room_team_id" => 103, "rank" => 1},
             %{"room_team_id" => 101, "rank" => 2},
             %{"room_team_id" => 102, "rank" => 3},
             %{"room_team_id" => 104, "rank" => 4}
           ]

    # winner's speakers 76, everyone else 75
    scores = Map.new(params["speakerScores"], &{&1["room_speaker_id"], &1["score"]})
    assert scores[205] == 76 and scores[206] == 76
    assert Enum.count(scores, fn {_id, score} -> score == 75 end) == 6

    assert_received :confirmed
  end

  test "pick_winner rejects a team not in the room", %{club: club} do
    judge = user_fixture(%{node_user_id: 77})
    session = session_fixture(club, engine_event_id: 11)

    stub(fn conn, _params ->
      case conn.request_path do
        "/api/events/11/rounds" ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        "/api/rounds/21/rooms" ->
          ok(conn, [%{"id" => 71, "RoomTeams" => [%{"id" => 101, "position" => 1}]}])
      end
    end)

    assert {:error, "that team is not in this room"} =
             Sessions.pick_winner(judge, session, 71, 999)

    assert {:error, "room 72 is not part of this session"} =
             Sessions.pick_winner(judge, session, 72, 101)
  end

  test "finish completes round and event", %{head: head, club: club} do
    session = session_fixture(club, engine_event_id: 11)
    test_pid = self()

    stub(fn conn, params ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/events/11/rounds"} ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        {"PUT", "/api/rounds/21"} ->
          send(test_pid, {:round, params})
          ok(conn, %{"id" => 21, "status" => "completed"})

        {"PUT", "/api/events/11"} ->
          send(test_pid, {:event, params})
          ok(conn, %{"id" => 11, "status" => "completed"})
      end
    end)

    assert :ok = Sessions.finish(head, session)
    assert_received {:round, %{"status" => "completed"}}
    assert_received {:event, %{"status" => "completed"}}
  end
end
