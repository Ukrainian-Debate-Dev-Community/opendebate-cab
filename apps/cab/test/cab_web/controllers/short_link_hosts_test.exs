defmodule CabWeb.ShortLinkHostsTest do
  # changes the app env (allowed hosts): not async
  use CabWeb.ConnCase, async: false

  alias Cab.ShortLinks

  test "URLs only on allowed hosts; never an open redirect", %{conn: conn} do
    for bad <- [
          "https://evil.example/x",
          "//evil.example/x",
          "/\\evil.example",
          "javascript:alert(1)",
          "ftp://example.org/x",
          "https://user@example.org/x",
          nil,
          42
        ] do
      assert ShortLinks.link(bad) == {:error, :invalid_target}, inspect(bad)
    end

    assert_raise ArgumentError, fn -> ShortLinks.short_url("https://evil.example/x") end

    Application.put_env(:cab, :short_link_hosts, ["Example.org"])
    on_exit(fn -> Application.put_env(:cab, :short_link_hosts, []) end)

    {:ok, link} = ShortLinks.link("https://example.org/news?id=1")
    assert redirected_to(get(conn, "/" <> link.code)) == "https://example.org/news?id=1"

    # a host dropped from the list no longer opens
    Application.put_env(:cab, :short_link_hosts, [])
    assert get(conn, "/" <> link.code) |> response(404)
  end
end
