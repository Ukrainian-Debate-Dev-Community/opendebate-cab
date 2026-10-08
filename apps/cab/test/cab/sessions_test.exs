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

  # the standard state read (event + round + participants + rooms)
  # that every gated lifecycle call now makes first; returns nil for
  # anything else so callers can chain their own stubs with ||
  defp state_stub(conn, participants, rooms \\ []) do
    case {conn.method, conn.request_path} do
      {"GET", "/api/events/11"} -> ok(conn, %{"id" => 11, "status" => "scheduled"})
      {"GET", "/api/events/11/rounds"} -> ok(conn, [%{"id" => 21, "sequence" => 1}])
      {"GET", "/api/events/11/participants"} -> ok(conn, participants)
      {"GET", "/api/rounds/21/rooms"} -> ok(conn, rooms)
      _ -> nil
    end
  end

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
    # the round id is stamped so later reads skip the rounds lookup
    assert session.engine_round_id == 21
    assert session.opened_by_user_id == head.id
    assert Sessions.get_for_club(club, session.uuid).id == session.id
  end

  test "state with a stamped round id fans the reads out and skips no data",
       %{club: club} do
    session = session_fixture(club, engine_event_id: 11, engine_round_id: 21)

    stub(fn conn, _params ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/events/11"} ->
          ok(conn, %{"id" => 11, "name" => "Night", "status" => "scheduled"})

        {"GET", "/api/events/11/rounds"} ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        {"GET", "/api/events/11/participants"} ->
          ok(conn, [%{"id" => 41, "role" => "speaker", "display_name" => "Ann"}])

        {"GET", "/api/rounds/21/rooms"} ->
          ok(conn, [%{"id" => 71, "status" => "pending"}])
      end
    end)

    assert {:ok, state} = Sessions.state(%{session | club: club})
    assert state.round["id"] == 21
    assert [%{"id" => 41}] = state.signups
    assert [%{"id" => 71}] = state.rooms
    assert state.stage == :running
  end

  test "signup registers self as speaker or adjudicator while :signup", %{club: club} do
    user = user_fixture(%{node_user_id: 44, name: "Ann B"})
    session = session_fixture(club, engine_event_id: 11)

    stub(fn conn, params ->
      state_stub(conn, []) ||
        case {conn.method, conn.request_path} do
          {"POST", "/api/events/11/participants"} ->
            assert params == %{
                     "display_name" => "Ann B",
                     "role" => "adjudicator",
                     "user_id" => 44
                   }

            ok(conn, %{"id" => 41, "role" => "adjudicator"})
        end
    end)

    assert {:ok, %{"id" => 41}} = Sessions.signup(user, session, "judge")
  end

  test "signup is 409-gated once sign-ups close", %{club: club} do
    user = user_fixture(%{node_user_id: 44})
    closed = closed_session_fixture(club, engine_event_id: 11)

    stub(fn conn, _params -> state_stub(conn, []) end)

    assert {:error, :conflict, message} = Sessions.signup(user, closed, "speak")
    assert message =~ "sign-ups are not open (session is closed)"
  end

  test "close_signups / reopen_signups flip the registration window", %{club: club} do
    session = session_fixture(club, engine_event_id: 11)

    stub(fn conn, _params -> state_stub(conn, []) end)

    assert {:ok, closed} = Sessions.close_signups(session)
    assert %DateTime{} = closed.signups_closed_at

    # already closed -> conflict
    assert {:error, :conflict, message} = Sessions.close_signups(%{closed | club: club})
    assert message =~ "session is closed"

    assert {:ok, reopened} = Sessions.reopen_signups(%{closed | club: club})
    assert reopened.signups_closed_at == nil

    # reopen only while closed
    assert {:error, :conflict, message} = Sessions.reopen_signups(%{reopened | club: club})
    assert message =~ "session is signup"

    # rooms made -> neither close nor reopen
    stub(fn conn, _params -> state_stub(conn, [], [%{"id" => 71, "status" => "pending"}]) end)

    assert {:error, :conflict, _} = Sessions.close_signups(%{reopened | club: club})
  end

  test "state/1 derives the stage from engine data + the registration window", %{club: club} do
    open_session = session_fixture(club, engine_event_id: 11)
    closed_session = closed_session_fixture(club, engine_event_id: 11)

    for {session, event_status, rooms, expected} <- [
          {open_session, "scheduled", [], :signup},
          {closed_session, "scheduled", [], :closed},
          {open_session, "scheduled", [%{"id" => 71, "status" => "pending"}], :running},
          {closed_session, "scheduled", [%{"id" => 71, "status" => "pending"}], :running},
          {closed_session, "completed", [%{"id" => 71, "status" => "confirmed"}], :done}
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

  test "make_rooms pairs attendance into inline temporary teams with judge chairs",
       %{head: head, club: club} do
    session = closed_session_fixture(club, engine_event_id: 11)

    speakers =
      for id <- 1..8 do
        %{"id" => id, "role" => "speaker", "display_name" => "Speaker #{id}"}
      end

    judges = [%{"id" => 99, "role" => "adjudicator", "display_name" => "Judge"}]

    proposals =
      for n <- 0..3 do
        %{"name" => "Random Team #{n + 1}", "participant_ids" => [2 * n + 1, 2 * n + 2]}
      end

    test_pid = self()

    stub(fn conn, params ->
      state_stub(conn, speakers ++ judges) ||
        case {conn.method, conn.request_path} do
          {"GET", "/api/events/11/teams/auto-generate"} ->
            ok(conn, %{"total_free_speakers" => 8, "proposed_teams" => proposals})

          {"POST", "/api/rounds/21/rooms"} ->
            send(test_pid, {:room, params})
            ok(conn, %{"id" => 71})
        end
    end)

    assert {:ok, 1} = Sessions.make_rooms(head, session)

    assert_received {:room, room_params}
    assert room_params["format_id"] == 1
    assert [%{"participant_id" => 99, "role" => "chair"}] = room_params["adjudicators"]

    # teams go in inline (temporary — purged with the room on a
    # rebuild); colliding first-name names get a suffix
    assert [
             %{"name" => "Speaker & Speaker", "participant_ids" => [1, 2], "position" => 1},
             %{"name" => "Speaker & Speaker 2", "participant_ids" => [3, 4], "position" => 2},
             %{"name" => "Speaker & Speaker 3", "participant_ids" => [5, 6], "position" => 3},
             %{"name" => "Speaker & Speaker 4", "participant_ids" => [7, 8], "position" => 4}
           ] = room_params["teams"]
  end

  test "make_rooms irons the odd attendance: pairs first, singles last",
       %{head: head, club: club} do
    session = closed_session_fixture(club, engine_event_id: 11)

    # 7 speakers + 1 judge -> one room of 3 pairs + 1 iron single
    speakers =
      for id <- 1..7 do
        %{"id" => id, "role" => "speaker", "display_name" => "Speaker #{id}"}
      end

    judges = [%{"id" => 99, "role" => "adjudicator", "display_name" => "Judge"}]

    proposals = [
      %{"name" => "Random Team 1", "participant_ids" => [1, 2]},
      %{"name" => "Random Team 2", "participant_ids" => [3, 4]},
      %{"name" => "Random Team 3", "participant_ids" => [5, 6]},
      %{"name" => "Random Team 4", "participant_ids" => [7]}
    ]

    test_pid = self()

    stub(fn conn, params ->
      state_stub(conn, speakers ++ judges) ||
        case {conn.method, conn.request_path} do
          {"GET", "/api/events/11/teams/auto-generate"} ->
            ok(conn, %{"total_free_speakers" => 7, "proposed_teams" => proposals})

          {"POST", "/api/rounds/21/rooms"} ->
            send(test_pid, {:room, params})
            ok(conn, %{"id" => 71})
        end
    end)

    assert {:ok, 1} = Sessions.make_rooms(head, session)
    assert_received {:room, room_params}

    assert [
             %{"participant_ids" => [1, 2], "position" => 1},
             %{"participant_ids" => [3, 4], "position" => 2},
             %{"participant_ids" => [5, 6], "position" => 3},
             %{"name" => "Speaker", "participant_ids" => [7], "position" => 4}
           ] = room_params["teams"]
  end

  test "make_rooms is gated on :closed and refuses thin attendance",
       %{head: head, club: club} do
    open_session = session_fixture(club, engine_event_id: 11)

    stub(fn conn, _params ->
      state_stub(conn, for(id <- 1..8, do: %{"id" => id, "role" => "speaker"}))
    end)

    # the graph gate: sign-ups close -> rooms by attendance
    assert {:error, :conflict, message} = Sessions.make_rooms(head, open_session)
    assert message =~ "rooms are composed after sign-ups close (session is signup)"

    session = closed_session_fixture(club, engine_event_id: 11)

    stub(fn conn, _params ->
      state_stub(conn, [%{"id" => 1, "role" => "speaker"}])
    end)

    assert {:error, "rooms need 4-8 speakers (have 1 signed up)"} =
             Sessions.make_rooms(head, session)

    stub(fn conn, _params ->
      state_stub(conn, for(id <- 1..8, do: %{"id" => id, "role" => "speaker"}))
    end)

    assert {:error, "need at least 1 judge(s)" <> _} = Sessions.make_rooms(head, session)
  end

  defp signup_cast do
    speakers =
      for id <- 1..8 do
        %{
          "id" => id,
          "role" => "speaker",
          "display_name" => "Speaker #{id}",
          "user_id" => 400 + id
        }
      end

    judges = [
      %{"id" => 99, "role" => "adjudicator", "display_name" => "Judge", "user_id" => 499}
    ]

    {speakers, judges}
  end

  test "pairing_proposal returns the auto-pair result without side effects", %{club: club} do
    session = closed_session_fixture(club, engine_event_id: 11)
    {speakers, judges} = signup_cast()

    proposals =
      for n <- 0..3 do
        %{"name" => "Random Team #{n + 1}", "participant_ids" => [2 * n + 1, 2 * n + 2]}
      end

    test_pid = self()

    stub(fn conn, _params ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/events/11/teams/auto-generate"} ->
          send(test_pid, :proposed)
          ok(conn, %{"total_free_speakers" => 8, "proposed_teams" => proposals})
      end
    end)

    state = %{stage: :closed, signups: speakers ++ judges}

    assert {:ok, [room]} = Sessions.pairing_proposal(session, state)
    assert room.judge_participant_id == 99
    assert room.teams == [[1, 2], [3, 4], [5, 6], [7, 8]]
    assert_received :proposed

    # odd attendance irons: 7 speakers -> 3 pairs + 1 single, last
    assert {:ok, [room]} =
             Sessions.pairing_proposal(session, %{
               stage: :closed,
               signups: Enum.take(speakers, 7) ++ judges
             })

    assert room.teams == [[1, 2], [3, 4], [5, 6], [7]]

    # a judge per room; 4 speakers minimum; only while :closed
    assert :unavailable = Sessions.pairing_proposal(session, %{stage: :closed, signups: speakers})

    assert :unavailable =
             Sessions.pairing_proposal(session, %{
               stage: :closed,
               signups: Enum.take(speakers, 3) ++ judges
             })

    assert :unavailable =
             Sessions.pairing_proposal(session, %{stage: :signup, signups: speakers ++ judges})

    assert :unavailable = Sessions.pairing_proposal(session, %{stage: :running, signups: []})
  end

  test "make_rooms/3 creates rooms exactly as composed, irons included",
       %{head: head, club: club} do
    session = closed_session_fixture(club, engine_event_id: 11)
    {speakers, judges} = signup_cast()
    test_pid = self()

    stub(fn conn, params ->
      state_stub(conn, speakers ++ judges) ||
        case {conn.method, conn.request_path} do
          {"POST", "/api/rounds/21/rooms"} ->
            send(test_pid, {:room, params})
            ok(conn, %{"id" => 71})
        end
    end)

    composition = [
      %{
        "judge_participant_id" => 99,
        "teams" => [[8, 1], [2, 7], [3, 6], [4, 5]]
      }
    ]

    assert {:ok, 1} = Sessions.make_rooms(head, session, composition)
    assert_received {:room, room_params}
    assert [%{"participant_id" => 99, "role" => "chair"}] = room_params["adjudicators"]

    assert [
             %{"participant_ids" => [8, 1], "position" => 1},
             %{"participant_ids" => [2, 7], "position" => 2},
             %{"participant_ids" => [3, 6], "position" => 3},
             %{"participant_ids" => [4, 5], "position" => 4}
           ] = room_params["teams"]

    # a 1-speaker team is a declared iron — valid composition, the
    # single speaker goes in alone (speakers 4 and 5 sit out)
    iron_composition = [
      %{
        "judge_participant_id" => 99,
        "teams" => [[8, 1], [2, 7], [3, 6], [5]]
      }
    ]

    assert {:ok, 1} = Sessions.make_rooms(head, session, iron_composition)
    assert_received {:room, room_params}

    assert [
             %{"participant_ids" => [8, 1], "position" => 1},
             %{"participant_ids" => [2, 7], "position" => 2},
             %{"participant_ids" => [3, 6], "position" => 3},
             %{"participant_ids" => [5], "position" => 4}
           ] = room_params["teams"]
  end

  test "make_rooms/3 is gated on :closed", %{head: head, club: club} do
    session = session_fixture(club, engine_event_id: 11)
    {speakers, judges} = signup_cast()

    stub(fn conn, _params -> state_stub(conn, speakers ++ judges) end)

    composition = [
      %{"judge_participant_id" => 99, "teams" => [[1, 2], [3, 4], [5, 6], [7, 8]]}
    ]

    assert {:error, :conflict, message} = Sessions.make_rooms(head, session, composition)
    assert message =~ "rooms are composed after sign-ups close"
  end

  test "make_rooms/3 validates the composition against the signups",
       %{head: head, club: club} do
    session = closed_session_fixture(club, engine_event_id: 11)
    {speakers, judges} = signup_cast()

    stub(fn conn, _params -> state_stub(conn, speakers ++ judges) end)

    compose = fn judge, teams ->
      [%{"judge_participant_id" => judge, "teams" => teams}]
    end

    full = [[1, 2], [3, 4], [5, 6], [7, 8]]

    # a speaker cannot chair; a stranger cannot speak; nobody twice
    assert {:error, %{rooms: message}} = Sessions.make_rooms(head, session, compose.(1, full))
    assert message =~ "not a signed-up judge"

    assert {:error, %{rooms: message}} =
             Sessions.make_rooms(head, session, compose.(99, [[1, 2], [3, 4], [5, 6], [7, 999]]))

    assert message =~ "999 is not a signed-up speaker"

    assert {:error, %{rooms: message}} =
             Sessions.make_rooms(head, session, compose.(99, [[1, 2], [3, 4], [5, 6], [7, 1]]))

    assert message =~ "placed more than once"

    # shape: 4 teams of 1-2 (irons allowed, empties not), judge
    # required, non-empty list
    assert {:error, %{rooms: message}} =
             Sessions.make_rooms(head, session, compose.(99, [[1, 2], [3, 4], [5, 6]]))

    assert message =~ "4 teams of 1-2"

    assert {:error, %{rooms: message}} =
             Sessions.make_rooms(head, session, compose.(99, [[1, 2], [3, 4], [5, 6], []]))

    assert message =~ "4 teams of 1-2"

    assert {:error, %{rooms: message}} =
             Sessions.make_rooms(
               head,
               session,
               compose.(99, [[1, 2], [3, 4], [5, 6], [7, 8, 1]])
             )

    assert message =~ "4 teams of 1-2"

    assert {:error, %{rooms: message}} =
             Sessions.make_rooms(head, session, [%{"teams" => full}])

    assert message =~ "judge_participant_id"

    assert {:error, %{rooms: _}} = Sessions.make_rooms(head, session, [])
    assert {:error, %{rooms: _}} = Sessions.make_rooms(head, session, "nope")

    # integer-strings (the HTML compose form) parse fine — but then
    # the engine call runs, so stub the room POST too
    stub(fn conn, _params ->
      state_stub(conn, speakers ++ judges) ||
        case {conn.method, conn.request_path} do
          {"POST", "/api/rounds/21/rooms"} -> ok(conn, %{"id" => 71})
        end
    end)

    strings =
      compose.("99", [["1", "2"], ["3", "4"], ["5", "6"], ["7", "8"]])

    assert {:ok, 1} = Sessions.make_rooms(head, session, strings)
  end

  test "signup_for signs an approved member up on the head's behalf",
       %{head: head, club: club} do
    member = user_fixture(%{node_user_id: 44, name: "Ann B"})
    membership_fixture(member, club)
    outsider = user_fixture(%{node_user_id: 55})
    session = session_fixture(club, engine_event_id: 11)
    test_pid = self()

    stub(fn conn, params ->
      state_stub(conn, []) ||
        case {conn.method, conn.request_path} do
          {"POST", "/api/events/11/participants"} ->
            send(test_pid, {:added, claims(conn), params})
            ok(conn, %{"id" => 41, "role" => params["role"]})
        end
    end)

    assert {:ok, %{"id" => 41}} = Sessions.signup_for(head, session, member.username, "speak")

    # registered AS the head, FOR the member's engine user
    assert_received {:added, %{"id" => 9}, params}

    assert params == %{
             "display_name" => "Ann B",
             "role" => "speaker",
             "user_id" => 44
           }

    # only approved members; only real kinds
    assert {:error, message} = Sessions.signup_for(head, session, outsider.username, "speak")
    assert message =~ "not an approved member"
    assert {:error, message} = Sessions.signup_for(head, session, "who-dis", "judge")
    assert message =~ "not an approved member"
    assert {:error, message} = Sessions.signup_for(head, session, member.username, "watch")
    assert message =~ ~s("speak" or "judge")
  end

  test "remove_signup: the head removes anyone, a member only themselves",
       %{head: head, club: club} do
    member = user_fixture(%{node_user_id: 44})
    membership_fixture(member, club)
    other = user_fixture(%{node_user_id: 55})
    membership_fixture(other, club)
    session = session_fixture(club, engine_event_id: 11)
    test_pid = self()

    participants = [
      %{"id" => 41, "user_id" => 44, "role" => "speaker", "display_name" => "m"},
      %{"id" => 42, "user_id" => 55, "role" => "speaker", "display_name" => "o"}
    ]

    stub(fn conn, _params ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/events/11/participants"} ->
          ok(conn, participants)

        {"DELETE", "/api/events/11/participants/" <> pid} ->
          send(test_pid, {:deleted, pid, claims(conn)})
          Req.Test.json(conn, %{"status" => "success", "message" => "Participant archived."})
      end
    end)

    # a member cannot remove someone else's signup
    assert {:error, :forbidden} = Sessions.remove_signup(member, session, 42)
    refute_received {:deleted, _pid, _claims}

    # self-removal — the engine call still runs as the club head
    # (participant deletion is owner-only in the engine)
    assert :ok = Sessions.remove_signup(member, session, 41)
    assert_received {:deleted, "41", %{"id" => 9}}

    # the head removes anyone
    assert :ok = Sessions.remove_signup(head, session, 42)
    assert_received {:deleted, "42", %{"id" => 9}}

    assert {:error, "participant 77 is not signed up" <> _} =
             Sessions.remove_signup(head, session, 77)
  end

  test "delete_rooms removes pending rooms only", %{head: head, club: club} do
    session = session_fixture(club, engine_event_id: 11)
    test_pid = self()

    rooms_stub = fn rooms ->
      stub(fn conn, _params ->
        case {conn.method, conn.request_path} do
          {"GET", "/api/events/11/rounds"} ->
            ok(conn, [%{"id" => 21, "sequence" => 1}])

          {"GET", "/api/rounds/21/rooms"} ->
            ok(conn, rooms)

          {"DELETE", "/api/rooms/" <> id} ->
            send(test_pid, {:deleted_room, id})
            Req.Test.json(conn, %{"status" => "success", "message" => "Room archived."})
        end
      end)
    end

    rooms_stub.([%{"id" => 71, "status" => "pending"}, %{"id" => 72, "status" => "pending"}])
    assert {:ok, 2} = Sessions.delete_rooms(head, session)
    assert_received {:deleted_room, "71"}
    assert_received {:deleted_room, "72"}

    rooms_stub.([%{"id" => 71, "status" => "pending"}, %{"id" => 72, "status" => "judging"}])
    assert {:error, "only pending rooms" <> _} = Sessions.delete_rooms(head, session)
    refute_received {:deleted_room, _id}

    rooms_stub.([])
    assert {:error, "this session has no rooms" <> _} = Sessions.delete_rooms(head, session)
  end

  test "editing a confirmed ballot: head only, unconfirm + replace + reconfirm, never wiped",
       %{head: head, club: club} do
    judge = user_fixture(%{node_user_id: 77})
    session = session_fixture(club, engine_event_id: 11)
    test_pid = self()
    confirmed = %{engine_room() | "status" => "confirmed"}

    stub(fn conn, params ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/events/11/rounds"} ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        {"GET", "/api/rounds/21/rooms"} ->
          ok(conn, [confirmed])

        {"PATCH", "/api/rooms/71/unconfirm"} ->
          send(test_pid, {:unconfirmed, claims(conn)})
          Req.Test.json(conn, %{"status" => "success", "message" => "ok"})

        {"POST", "/api/rooms/71/scores"} ->
          send(test_pid, {:scores, params})
          Req.Test.json(conn, %{"status" => "success", "message" => "ok"})

        {"PATCH", "/api/rooms/71/confirm"} ->
          send(test_pid, :confirmed)
          Req.Test.json(conn, %{"status" => "success", "message" => "ok"})
      end
    end)

    scores = ballot_scores([{1, 151}, {2, 157}, {3, 149}, {4, 147}])

    # the chair cannot edit once confirmed — the ballot is the head's
    assert {:error, :forbidden} = Sessions.submit_ballot(judge, session, 71, scores)
    refute_received {:unconfirmed, _}

    # the head edits: cab unconfirms as the head, the resubmission
    # replaces the ballot atomically and it re-confirms right after
    assert :ok = Sessions.submit_ballot(head, session, 71, scores)
    assert_received {:unconfirmed, %{"id" => 9}}
    assert_received {:scores, %{"teamRankings" => [_ | _]}}
    assert_received :confirmed
  end

  test "cancel archives the engine event and removes the gateway row",
       %{head: head, club: club} do
    session = session_fixture(club, engine_event_id: 11)
    test_pid = self()

    stub(fn conn, _params ->
      case {conn.method, conn.request_path} do
        {"DELETE", "/api/events/11"} ->
          send(test_pid, :event_deleted)
          Req.Test.json(conn, %{"status" => "success", "message" => "Event archived."})
      end
    end)

    assert {:ok, _deleted} = Sessions.cancel(head, session)
    assert_received :event_deleted
    assert Sessions.get_by_uuid(session.uuid) == nil
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

    # totals: p2 157 > p1 151 > p3 149 > p4 147
    scores =
      ballot_scores([{1, 151}, {2, 157}, {3, 149}, {4, 147}])

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
    assert speaks[203] == 82.0 and speaks[204] == 75.0
    assert speaks[201] == 76.0 and speaks[202] == 75.0

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
      ballot_scores([{2, 157}, {3, 149}, {4, 147}]) ++
        [
          %{"position" => 1, "speaker_participant_id" => 301, "iron" => false, "score" => 76},
          %{"position" => 1, "speaker_participant_id" => 301, "iron" => true, "score" => 75.0}
        ]

    assert :ok = Sessions.submit_ballot(judge, session, 71, scores)
    assert_received {:scores, _claims, params}

    speaks = Map.new(params["speakerScores"], &{&1["room_speaker_id"], &1["score"]})
    assert speaks[201] == 76.0 and speaks[202] == 75.0
  end

  test "submit_ballot rejects tied team totals naming the total", %{club: club} do
    judge = user_fixture(%{node_user_id: 77})
    session = session_fixture(club, engine_event_id: 11)
    stub_ballot_room(engine_room(), self())

    scores = ballot_scores([{1, 151}, {2, 151}, {3, 149}, {4, 147}])

    assert {:error, %{scores: message}} = Sessions.submit_ballot(judge, session, 71, scores)
    assert message =~ "151"
    assert message =~ "tied team totals"
    refute_received {:scores, _claims, _params}
  end

  test "submit_ballot validates score bounds and whole points", %{club: club} do
    judge = user_fixture(%{node_user_id: 77})
    session = session_fixture(club, engine_event_id: 11)

    for bad <- [49, 101, 75.5, nil, "76"] do
      scores =
        ballot_scores([{2, 157}, {3, 149}, {4, 147}]) ++
          [
            %{"position" => 1, "speaker_participant_id" => 301, "score" => bad},
            %{"position" => 1, "speaker_participant_id" => 302, "score" => 75.0}
          ]

      assert {:error, %{scores: message}} = Sessions.submit_ballot(judge, session, 71, scores)
      assert message =~ "whole points, 50-100"
    end

    # not two entries per team
    assert {:error, %{scores: message}} =
             Sessions.submit_ballot(judge, session, 71, ballot_scores([{1, 151}, {2, 157}]))

    assert message =~ "8 scores"
  end

  test "submit_ballot is judge-or-head only", %{club: club, head: head} do
    session = session_fixture(club, engine_event_id: 11)
    scores = ballot_scores([{1, 151}, {2, 157}, {3, 149}, {4, 147}])

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
      ballot_scores([{2, 157}, {3, 149}, {4, 147}]) ++
        [
          %{"position" => 1, "speaker_participant_id" => 999, "score" => 76},
          %{"position" => 1, "speaker_participant_id" => 302, "score" => 75.0}
        ]

    assert {:error, %{scores: message}} = Sessions.submit_ballot(judge, session, 71, scores)
    assert message =~ "999 does not speak at position 1"

    assert {:error, "room 72 is not part of this session"} =
             Sessions.submit_ballot(
               judge,
               session,
               72,
               ballot_scores([{1, 151}, {2, 157}, {3, 149}, {4, 147}])
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
