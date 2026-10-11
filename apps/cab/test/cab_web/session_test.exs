defmodule CabWeb.SessionTest do
  use ExUnit.Case, async: false

  alias CabWeb.Session

  # a cab session cookie as cab itself would sign it
  defp cookie_for(user_id) do
    conn = %Plug.Conn{secret_key_base: CabWeb.Endpoint.config(:secret_key_base)}
    opts = Plug.Session.COOKIE.init(signing_salt: Session.options()[:signing_salt])
    Plug.Session.COOKIE.put(conn, nil, %{"user_id" => user_id}, opts)
  end

  test "reads the user id from cab's own cookie" do
    assert Session.user_id(cookie_for(42)) == 42
  end

  test "a tampered or missing cookie is nobody" do
    cookie = cookie_for(42)
    assert Session.user_id(cookie <> "x") == nil
    assert Session.user_id("garbage") == nil
    assert Session.user_id(nil) == nil
  end

  test "the cookie domain is a deploy setting" do
    refute Keyword.has_key?(Session.options(), :domain)
    Application.put_env(:cab, :session_cookie_domain, ".example.org")
    on_exit(fn -> Application.delete_env(:cab, :session_cookie_domain) end)
    assert Session.options()[:domain] == ".example.org"
  end
end
