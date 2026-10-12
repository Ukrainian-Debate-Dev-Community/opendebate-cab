defmodule CabWeb.RateLimitTest do
  @moduledoc """
  The JSON API's rate limit: 20 anonymous requests per IP and a burst of
  20 per signed-in account, then 429 with Retry-After; RateLimit-*
  headers on every limited response; off unless enabled.
  """
  use CabWeb.ConnCase, async: false

  import Cab.Fixtures

  @on [enabled: true, signed_in: {60, 20}, anonymous: {20, 20}, trust_cf_ip: true]

  setup do
    before = Application.get_env(:cab, CabWeb.RateLimit)
    Application.put_env(:cab, CabWeb.RateLimit, @on)
    CabWeb.RateLimit.reset()

    on_exit(fn ->
      Application.put_env(:cab, CabWeb.RateLimit, before)
      CabWeb.RateLimit.reset()
    end)
  end

  defp clubs(conn, ip),
    do: conn |> put_req_header("cf-connecting-ip", ip) |> get(~p"/api/cab/v1/clubs")

  test "an anonymous IP gets 20 requests, then 429 with Retry-After", %{conn: conn} do
    for n <- 1..20 do
      resp = clubs(conn, "203.0.113.7")
      assert resp.status == 200, "request #{n} was refused"
    end

    refused = clubs(conn, "203.0.113.7")
    assert refused.status == 429
    assert json_response(refused, 429)["error"] == "too many requests"
    [retry] = get_resp_header(refused, "retry-after")
    assert String.to_integer(retry) >= 1

    # another visitor has a bucket of their own
    assert clubs(conn, "198.51.100.9").status == 200
  end

  test "a signed-in account has its own bucket of 20", %{conn: conn} do
    user = user_fixture()
    signed_in = init_test_session(conn, %{user_id: user.id})

    for _ <- 1..20, do: assert(get(signed_in, ~p"/api/cab/v1/clubs").status == 200)
    assert get(signed_in, ~p"/api/cab/v1/clubs").status == 429

    # the anonymous bucket of the same address is untouched
    assert clubs(conn, "127.0.0.1").status == 200
  end

  test "limited responses say how much is left", %{conn: conn} do
    resp = clubs(conn, "192.0.2.1")
    assert get_resp_header(resp, "ratelimit-limit") == ["20"]
    assert get_resp_header(resp, "ratelimit-remaining") == ["19"]
    assert [_reset] = get_resp_header(resp, "ratelimit-reset")
  end

  test "off, nothing is counted", %{conn: conn} do
    Application.put_env(:cab, CabWeb.RateLimit, Keyword.put(@on, :enabled, false))
    resp = clubs(conn, "192.0.2.2")
    assert resp.status == 200
    assert get_resp_header(resp, "ratelimit-limit") == []
  end

  test "pages and the API docs are not limited", %{conn: conn} do
    for _ <- 1..25, do: assert(get(conn, ~p"/api/cab/docs").status == 200)
  end
end
