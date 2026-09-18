defmodule Cab.DevSeedsTest do
  use ExUnit.Case, async: true

  alias Cab.DevSeeds

  @secret "test-engine-secret"

  defp signer, do: Joken.Signer.create("HS256", @secret)

  test "seed_tournament creates bot teams and judges through the engine" do
    {:ok, counter} = Agent.start_link(fn -> %{register: 0, participants: 0, teams: 0} end)

    Req.Test.stub(Core.Engine, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      params = if body == "", do: %{}, else: Jason.decode!(body)

      case conn.request_path do
        "/api/users/register" ->
          Agent.update(counter, &Map.update!(&1, :register, fn n -> n + 1 end))
          id = Agent.get(counter, & &1.register) + 100
          token = Joken.generate_and_sign!(%{}, %{"id" => id}, signer())
          Req.Test.json(conn, %{"status" => "success", "token" => token})

        "/api/events/11/participants" ->
          Agent.update(counter, &Map.update!(&1, :participants, fn n -> n + 1 end))
          id = Agent.get(counter, & &1.participants)
          Req.Test.json(conn, %{"status" => "success", "data" => %{"id" => id}})

        "/api/events/11/teams" ->
          Agent.update(counter, &Map.update!(&1, :teams, fn n -> n + 1 end))
          assert length(params["participant_ids"]) == 2
          id = Agent.get(counter, & &1.teams)
          Req.Test.json(conn, %{"status" => "success", "data" => %{"id" => id}})
      end
    end)

    assert {:ok, %{teams: 4, judges: 2}} = DevSeeds.seed_tournament(9, 11, 4, 2)

    counts = Agent.get(counter, & &1)
    # 4 teams x 2 speakers + 2 judges = 10 shadow engine users
    assert counts.register == 10
    assert counts.participants == 10
    assert counts.teams == 4
  end
end
