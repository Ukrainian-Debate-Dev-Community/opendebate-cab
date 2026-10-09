defmodule Core.EngineTest do
  use ExUnit.Case, async: true

  alias Core.Engine

  @secret "test-engine-secret"

  defp signer, do: Joken.Signer.create("HS256", @secret)

  defp engine_token(claims), do: Joken.generate_and_sign!(%{}, claims, signer())

  describe "mint_token/2" do
    test "signs an HS256 token with id/isAdmin and short expiry" do
      token = Engine.mint_token(42)

      assert {:ok, claims} = Joken.verify(token, signer())
      assert claims["id"] == 42
      assert claims["isAdmin"] == false
      assert claims["exp"] - claims["iat"] == 300
      assert_in_delta claims["iat"], System.os_time(:second), 5
    end

    test "admin flag is carried in the payload" do
      assert {:ok, claims} = Joken.verify(Engine.mint_token(1, true), signer())
      assert claims["isAdmin"] == true
    end
  end

  describe "provision_user/1" do
    test "registers the user and returns the id claim of the response token" do
      Req.Test.stub(Core.Engine, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/api/users/register"

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        params = Jason.decode!(body)
        assert params["username"] == "debater"
        assert String.length(params["password"]) >= 24

        Req.Test.json(conn, %{"status" => "ok", "token" => engine_token(%{"id" => 42})})
      end)

      assert {:ok, 42} = Engine.provision_user("debater")
    end

    test "retries with a suffixed username on conflict" do
      Req.Test.stub(Core.Engine, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        params = Jason.decode!(body)

        if params["username"] == "taken" do
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(409, ~s({"error":"username taken"}))
        else
          assert params["username"] =~ ~r/^taken-[0-9a-f]{4}$/
          Req.Test.json(conn, %{"status" => "ok", "token" => engine_token(%{"id" => 7})})
        end
      end)

      assert {:ok, 7} = Engine.provision_user("taken")
    end

    test "gives up after repeated conflicts" do
      Req.Test.stub(Core.Engine, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(409, ~s({"error":"username taken"}))
      end)

      assert {:error, :username_conflict} = Engine.provision_user("always-taken")
    end

    test "returns an error when the engine is unreachable" do
      Req.Test.stub(Core.Engine, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, %Req.TransportError{reason: :econnrefused}} =
               Engine.provision_user("debater")
    end

    test "returns an error when the response token lacks an id claim" do
      Req.Test.stub(Core.Engine, fn conn ->
        Req.Test.json(conn, %{"status" => "ok", "token" => engine_token(%{"sub" => "nope"})})
      end)

      assert {:error, :missing_id_claim} = Engine.provision_user("debater")
    end
  end

  describe "request helpers" do
    test "get/2 attaches a bearer token minted for the given user" do
      Req.Test.stub(Core.Engine, fn conn ->
        assert ["Bearer " <> token] = Plug.Conn.get_req_header(conn, "authorization")
        assert {:ok, %{"id" => 5}} = Joken.verify(token, signer())
        Req.Test.json(conn, %{"ok" => true})
      end)

      assert {:ok, %Req.Response{status: 200, body: %{"ok" => true}}} =
               Engine.get(5, "/api/anything")
    end

    test "post/3 sends JSON with a bearer token" do
      Req.Test.stub(Core.Engine, fn conn ->
        assert ["Bearer " <> _] = Plug.Conn.get_req_header(conn, "authorization")
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body) == %{"name" => "Kyiv Open"}
        Req.Test.json(conn, %{"id" => 1})
      end)

      assert {:ok, %Req.Response{status: 200, body: %{"id" => 1}}} =
               Engine.post(5, "/api/events", %{name: "Kyiv Open"})
    end

    test "public_get/1 sends no authorization header" do
      Req.Test.stub(Core.Engine, fn conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == []
        Req.Test.json(conn, [%{"id" => 1}])
      end)

      assert {:ok, %Req.Response{status: 200, body: [%{"id" => 1}]}} =
               Engine.public_get("/api/events")
    end
  end

  test "a drained connection pool is an engine error, not a crash" do
    Req.Test.stub(Core.Engine, fn _conn ->
      raise "Finch was unable to provide a connection within the timeout due to excess queuing"
    end)

    assert {:error, %RuntimeError{message: "the engine is busy" <> _}} =
             Core.Engine.get(1, "/api/events/1")

    Req.Test.stub(Core.Engine, fn _conn -> raise "something else" end)
    assert_raise RuntimeError, "something else", fn -> Core.Engine.get(1, "/api/events/1") end
  end
end
