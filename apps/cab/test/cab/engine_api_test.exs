defmodule Cab.EngineApiTest do
  use ExUnit.Case, async: true

  alias Cab.EngineApi

  @secret "test-engine-secret"

  defp signer, do: Joken.Signer.create("HS256", @secret)

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
    {:ok, claims} = Joken.verify(token, signer())
    claims
  end

  test "create_organisation uses an isAdmin token and defaults owner to actor" do
    stub(fn conn, params ->
      assert conn.method == "POST"
      assert conn.request_path == "/api/organisations"
      assert params == %{"name" => "Org", "owner_id" => 9}
      assert %{"id" => 9, "isAdmin" => true} = claims(conn)
      ok(conn, %{"id" => 3, "name" => "Org"})
    end)

    assert {:ok, %{"id" => 3}} = EngineApi.create_organisation(9, "Org")
  end

  test "add_owner posts targetUserId as admin" do
    stub(fn conn, params ->
      assert conn.request_path == "/api/organisations/3/owners"
      assert params == %{"targetUserId" => 9}
      assert %{"isAdmin" => true} = claims(conn)
      Req.Test.json(conn, %{"status" => "success", "message" => "Owner added successfully."})
    end)

    assert {:ok, %{"message" => _}} = EngineApi.add_owner(9, 3, 9)
  end

  test "create_event posts to the organisation-scoped route as the actor" do
    stub(fn conn, params ->
      assert conn.request_path == "/api/events/3"
      assert params["name"] == "Kyiv Open"
      assert %{"id" => 9, "isAdmin" => false} = claims(conn)
      ok(conn, %{"id" => 11, "name" => "Kyiv Open", "status" => "scheduled"})
    end)

    assert {:ok, %{"id" => 11}} = EngineApi.create_event(9, 3, "Kyiv Open")
  end

  test "create_round posts name and sequence" do
    stub(fn conn, params ->
      assert conn.request_path == "/api/events/11/rounds"
      assert params == %{"name" => "Round 1", "sequence" => 1}
      ok(conn, %{"id" => 21, "sequence" => 1})
    end)

    assert {:ok, %{"id" => 21}} = EngineApi.create_round(9, 11, "Round 1", 1)
  end

  test "update_round PUTs the round" do
    stub(fn conn, params ->
      assert conn.method == "PUT"
      assert conn.request_path == "/api/rounds/21"
      assert params == %{"status" => "completed"}
      ok(conn, %{"id" => 21, "status" => "completed"})
    end)

    assert {:ok, %{"status" => "completed"}} =
             EngineApi.update_round(9, 21, %{status: "completed"})
  end

  test "add_participant includes user_id only when given" do
    stub(fn conn, params ->
      assert conn.request_path == "/api/events/11/participants"
      assert params == %{"display_name" => "Alice", "role" => "speaker", "user_id" => 77}
      ok(conn, %{"id" => 41, "display_name" => "Alice"})
    end)

    assert {:ok, %{"id" => 41}} = EngineApi.add_participant(9, 11, "Alice", "speaker", 77)
  end

  test "create_room posts format, teams, adjudicators and optional motion" do
    stub(fn conn, params ->
      assert conn.request_path == "/api/rounds/21/rooms"
      assert params["format_id"] == 1
      assert params["motion_id"] == 31
      assert [%{"team_id" => 51, "position" => 1} | _] = params["teams"]
      assert [%{"participant_id" => 61, "role" => "chair"}] = params["adjudicators"]
      Req.Test.json(conn, %{"status" => "success", "message" => "Room created"})
    end)

    assert {:ok, _} =
             EngineApi.create_room(
               9,
               21,
               [%{team_id: 51, position: 1}],
               [%{participant_id: 61, role: "chair"}],
               motion_id: 31
             )
  end

  test "delete_room DELETEs the room" do
    stub(fn conn, _params ->
      assert conn.method == "DELETE"
      assert conn.request_path == "/api/rooms/71"
      Req.Test.json(conn, %{"status" => "success", "message" => "Room deleted"})
    end)

    assert {:ok, _} = EngineApi.delete_room(9, 71)
  end

  test "set_room_motion posts the judge's motion to the room" do
    stub(fn conn, params ->
      assert conn.method == "POST"
      assert conn.request_path == "/api/rooms/71/motion"
      assert params == %{"motion_text" => "THW"}
      ok(conn, %{"motion" => %{"id" => 31, "is_released" => true}, "room_id" => 71})
    end)

    assert {:ok, %{"motion" => %{"id" => 31}}} = EngineApi.set_room_motion(9, 71, "THW")
  end

  test "submit_scores posts rankings and speaker scores" do
    stub(fn conn, params ->
      assert conn.request_path == "/api/rooms/71/scores"
      assert [%{"room_team_id" => 1, "rank" => 1}] = params["teamRankings"]
      assert [%{"room_speaker_id" => 2, "score" => 75.5}] = params["speakerScores"]
      Req.Test.json(conn, %{"status" => "success", "message" => "Scores submitted"})
    end)

    assert {:ok, _} =
             EngineApi.submit_scores(
               9,
               71,
               [%{room_team_id: 1, rank: 1}],
               [%{room_speaker_id: 2, score: 75.5}]
             )
  end

  test "confirm and unconfirm PATCH the room" do
    stub(fn conn, _params ->
      assert conn.method == "PATCH"

      assert conn.request_path in [
               "/api/rooms/71/confirm",
               "/api/rooms/71/unconfirm"
             ]

      Req.Test.json(conn, %{"status" => "success", "message" => "ok"})
    end)

    assert {:ok, _} = EngineApi.confirm_room(9, 71)
    assert {:ok, _} = EngineApi.unconfirm_room(9, 71)
  end

  test "standings read the calculated endpoints" do
    stub(fn conn, _params ->
      case conn.request_path do
        "/api/events/11/standings/calculated/teams" ->
          ok(conn, [%{"id" => 51, "name" => "Alpha", "total_points" => 6}])

        "/api/events/11/standings/calculated/speakers" ->
          ok(conn, [%{"id" => 41, "name" => "Alice", "total_points" => 240.5}])
      end
    end)

    assert {:ok, [%{"name" => "Alpha"}]} = EngineApi.team_standings(9, 11)
    assert {:ok, [%{"name" => "Alice"}]} = EngineApi.speaker_standings(9, 11)
  end

  test "engine error messages are surfaced" do
    stub(fn conn, _params ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(403, ~s({"status":"fail","message":"nope"}))
    end)

    assert {:error, "nope"} = EngineApi.get_event(9, 11)
  end

  test "transport errors become readable messages" do
    stub(fn conn, _params -> Req.Test.transport_error(conn, :econnrefused) end)

    assert {:error, "engine unreachable: " <> _} = EngineApi.get_event(9, 11)
  end
end
