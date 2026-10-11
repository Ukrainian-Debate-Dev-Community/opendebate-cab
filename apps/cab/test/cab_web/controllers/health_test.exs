defmodule CabWeb.HealthTest do
  use CabWeb.ConnCase, async: true

  test "GET /healthz answers ok and sets no cookie", %{conn: conn} do
    conn = get(conn, "/healthz")
    assert response(conn, 200) == "ok"
    assert get_resp_header(conn, "set-cookie") == []
  end

  test "the release can migrate" do
    Code.ensure_loaded!(Cab.Release)
    assert function_exported?(Cab.Release, :migrate, 0)
  end
end
