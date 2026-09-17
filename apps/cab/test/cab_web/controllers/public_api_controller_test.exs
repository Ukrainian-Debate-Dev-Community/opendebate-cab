defmodule CabWeb.PublicApiControllerTest do
  use CabWeb.ConnCase

  @token "portal-test-token"

  defp authed(conn), do: put_req_header(conn, "authorization", "Bearer #{@token}")

  test "rejects requests without a token", %{conn: conn} do
    conn = get(conn, ~p"/api/public/tournaments")
    assert json_response(conn, 401) == %{"error" => "unauthorized"}
  end

  test "rejects requests with a wrong token", %{conn: conn} do
    conn =
      conn
      |> put_req_header("authorization", "Bearer nope")
      |> get(~p"/api/public/tournaments")

    assert json_response(conn, 401) == %{"error" => "unauthorized"}
  end

  test "relays the engine's public events list", %{conn: conn} do
    events = [
      %{"id" => 1, "name" => "Kyiv Open 2026", "status" => "live"},
      %{"id" => 2, "name" => "Phoenix Cup", "status" => "registration"}
    ]

    Req.Test.stub(Core.Engine, fn req_conn ->
      assert req_conn.request_path == "/api/events"
      assert Plug.Conn.get_req_header(req_conn, "authorization") == []
      Req.Test.json(req_conn, events)
    end)

    conn = authed(conn) |> get(~p"/api/public/tournaments")
    assert json_response(conn, 200) == events
  end

  test "maps engine errors to 502", %{conn: conn} do
    Req.Test.stub(Core.Engine, fn req_conn ->
      Plug.Conn.send_resp(req_conn, 500, "boom")
    end)

    conn = authed(conn) |> get(~p"/api/public/tournaments")
    assert json_response(conn, 502) == %{"error" => "engine_unavailable"}
  end

  test "maps an unreachable engine to 502", %{conn: conn} do
    Req.Test.stub(Core.Engine, fn req_conn ->
      Req.Test.transport_error(req_conn, :econnrefused)
    end)

    conn = authed(conn) |> get(~p"/api/public/tournaments")
    assert json_response(conn, 502) == %{"error" => "engine_unavailable"}
  end
end
