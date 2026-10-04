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

  # Engine room: chair user 77, 4 teams at positions 1..4; team at
  # position p is room_team 100+p with room_speakers 200+2p-1/200+2p
  # spoken by participants 300+2p-1/300+2p.
  defp engine_room(chair_user_id \\ 77) do
    %{
      "id" => 71,
      "status" => "judging",
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
  end

  # two entries per position; score = totals[position] split 60/40
  defp ballot_scores(totals) do
    Enum.flat_map(totals, fn {position, total} ->
      [
        %{
          "position" => position,
          "speaker_participant_id" => 300 + position * 2 - 1,
          "iron" => false,
          "score" => total - 75.0
        },
        %{
          "position" => position,
          "speaker_participant_id" => 300 + position * 2,
          "iron" => false,
          "score" => 75.0
        }
      ]
    end)
  end

  defp stub_ballot_room(room, test_pid) do
    stub(fn conn, params ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/events/11/rounds"} ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        {"GET", "/api/rounds/21/rooms"} ->
          ok(conn, [room])

        {"POST", "/api/rooms/71/scores"} ->
          send(test_pid, {:scores, claims(conn), params})
          Req.Test.json(conn, %{"status" => "success", "message" => "ok"})

        {"PATCH", "/api/rooms/71/confirm"} ->
          send(test_pid, {:confirmed, claims(conn)})
          Req.Test.json(conn, %{"status" => "success", "message" => "ok"})
      end
    end)
  end

  test "submit_ballot derives ranks from totals, submits as the judge and confirms as the head",
       %{club: club} do
    judge = user_fixture(%{node_user_id: 77})
    session = session_fixture(club, engine_event_id: 11)
    stub_ballot_room(engine_room(), self())

    # totals: p2 157.5 > p1 151.5 > p3 149.5 > p4 147.5
    scores =
      ballot_scores([{1, 151.5}, {2, 157.5}, {3, 149.5}, {4, 147.5}])

    assert :ok = Sessions.submit_ballot(judge, session, 71, scores)

    # the ballot goes in as the judge (engine chair guard applies)
    assert_received {:scores, %{"id" => 77}, params}

    assert params["teamRankings"] == [
             %{"room_team_id" => 102, "rank" => 1},
             %{"room_team_id" => 101, "rank" => 2},
             %{"room_team_id" => 103, "rank" => 3},
             %{"room_team_id" => 104, "rank" => 4}
           ]

    speaks = Map.new(params["speakerScores"], &{&1["room_speaker_id"], &1["score"]})
    assert map_size(speaks) == 8
    assert speaks[203] == 82.5 and speaks[204] == 75.0
    assert speaks[201] == 76.5 and speaks[202] == 75.0

    # confirm is owner-only in the engine -> runs as the club head
    assert_received {:confirmed, %{"id" => 9}}
  end

  test "submit_ballot maps an iron speech onto the teammate's slot", %{club: club} do
    judge = user_fixture(%{node_user_id: 77})
    session = session_fixture(club, engine_event_id: 11)
    stub_ballot_room(engine_room(), self())

    # participant 301 speaks both OG speeches (iron) — second score
    # lands on room_speaker 202, the teammate's slot
    scores =
      ballot_scores([{2, 157.5}, {3, 149.5}, {4, 147.5}]) ++
        [
          %{"position" => 1, "speaker_participant_id" => 301, "iron" => false, "score" => 76.5},
          %{"position" => 1, "speaker_participant_id" => 301, "iron" => true, "score" => 75.0}
        ]

    assert :ok = Sessions.submit_ballot(judge, session, 71, scores)
    assert_received {:scores, _claims, params}

    speaks = Map.new(params["speakerScores"], &{&1["room_speaker_id"], &1["score"]})
    assert speaks[201] == 76.5 and speaks[202] == 75.0
  end

  test "submit_ballot rejects tied team totals naming the total", %{club: club} do
    judge = user_fixture(%{node_user_id: 77})
    session = session_fixture(club, engine_event_id: 11)
    stub_ballot_room(engine_room(), self())

    scores = ballot_scores([{1, 151.0}, {2, 151.0}, {3, 149.5}, {4, 147.5}])

    assert {:error, %{scores: message}} = Sessions.submit_ballot(judge, session, 71, scores)
    assert message =~ "151"
    assert message =~ "tied team totals"
    refute_received {:scores, _claims, _params}
  end

  test "submit_ballot validates score bounds and the 0.5 step", %{club: club} do
    judge = user_fixture(%{node_user_id: 77})
    session = session_fixture(club, engine_event_id: 11)

    for bad <- [49.5, 100.5, 75.3, nil, "76"] do
      scores =
        ballot_scores([{2, 157.5}, {3, 149.5}, {4, 147.5}]) ++
          [
            %{"position" => 1, "speaker_participant_id" => 301, "score" => bad},
            %{"position" => 1, "speaker_participant_id" => 302, "score" => 75.0}
          ]

      assert {:error, %{scores: message}} = Sessions.submit_ballot(judge, session, 71, scores)
      assert message =~ "50-100 in 0.5 steps"
    end

    # not two entries per team
    assert {:error, %{scores: message}} =
             Sessions.submit_ballot(judge, session, 71, ballot_scores([{1, 151.5}, {2, 157.5}]))

    assert message =~ "8 scores"
  end

  test "submit_ballot is judge-or-head only", %{club: club, head: head} do
    session = session_fixture(club, engine_event_id: 11)
    scores = ballot_scores([{1, 151.5}, {2, 157.5}, {3, 149.5}, {4, 147.5}])

    # a member who is neither the room's chair nor the head -> forbidden
    outsider = user_fixture(%{node_user_id: 55})
    membership_fixture(outsider, club)
    stub_ballot_room(engine_room(77), self())

    assert {:error, :forbidden} = Sessions.submit_ballot(outsider, session, 71, scores)
    refute_received {:scores, _claims, _params}

    # the head is not the chair but submits under full control
    assert :ok = Sessions.submit_ballot(head, session, 71, scores)
    assert_received {:scores, %{"id" => 9}, _params}
    assert_received {:confirmed, %{"id" => 9}}
  end

  test "submit_ballot rejects foreign speakers and foreign rooms", %{club: club} do
    judge = user_fixture(%{node_user_id: 77})
    session = session_fixture(club, engine_event_id: 11)
    stub_ballot_room(engine_room(), self())

    scores =
      ballot_scores([{2, 157.5}, {3, 149.5}, {4, 147.5}]) ++
        [
          %{"position" => 1, "speaker_participant_id" => 999, "score" => 76.5},
          %{"position" => 1, "speaker_participant_id" => 302, "score" => 75.0}
        ]

    assert {:error, %{scores: message}} = Sessions.submit_ballot(judge, session, 71, scores)
    assert message =~ "999 does not speak at position 1"

    assert {:error, "room 72 is not part of this session"} =
             Sessions.submit_ballot(
               judge,
               session,
               72,
               ballot_scores([{1, 151.5}, {2, 157.5}, {3, 149.5}, {4, 147.5}])
             )
  end

  test "user_history lists finished participations with the winner flag",
       %{club: club} do
    speaker = user_fixture(%{node_user_id: 44})
    membership_fixture(speaker, club)
    judge = user_fixture(%{node_user_id: 77})
    membership_fixture(judge, club)
    session = session_fixture(club, engine_event_id: 11)

    # an approved membership in a club without sessions adds nothing
    other_club = club_fixture(user_fixture(%{node_user_id: 8}))
    membership_fixture(speaker, other_club)

    stub(fn conn, _params ->
      case conn.request_path do
        "/api/events/organisation/3" ->
          ok(conn, [
            %{"id" => 11, "name" => "Night 1", "status" => "completed"},
            %{"id" => 12, "name" => "Open night", "status" => "scheduled"}
          ])

        "/api/events/11/participants" ->
          ok(conn, [
            %{"id" => 41, "user_id" => 44, "role" => "speaker"},
            %{"id" => 42, "user_id" => 77, "role" => "adjudicator"}
          ])

        "/api/events/11/rounds" ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        "/api/rounds/21/rooms" ->
          ok(conn, [
            %{
              "id" => 71,
              "status" => "confirmed",
              "RoomTeams" => [
                %{
                  "id" => 101,
                  "rank" => 1,
                  "RoomSpeakers" => [%{"id" => 201, "EventParticipant" => %{"id" => 41}}]
                },
                %{
                  "id" => 102,
                  "rank" => 2,
                  "RoomSpeakers" => [%{"id" => 202, "EventParticipant" => %{"id" => 43}}]
                }
              ]
            }
          ])
      end
    end)

    assert [row] = Sessions.user_history(speaker)
    assert row.club == club.name
    assert row.role == "speaker"
    assert row.won == true
    assert row.date == session.inserted_at

    # the judge participated but never competes for the win
    assert [judge_row] = Sessions.user_history(judge)
    assert judge_row.role == "judge"
    assert judge_row.won == false

    # a user without an engine counterpart never participated
    assert Sessions.user_history(user_fixture(%{node_user_id: nil})) == []
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
