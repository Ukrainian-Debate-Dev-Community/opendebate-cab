defmodule PublicWeb.FrameTest do
  @moduledoc """
  The header every page shares: the beta tag, the theme button and the
  language menu. The language is its own cookie, never the session.
  """
  use PublicWeb.ConnCase

  test "the header carries the beta tag, the theme button and the language menu", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)
    assert html =~ ~s(class="beta-tag")
    assert html =~ ~s(data-cycle="theme")
    assert html =~ ~s(href="/locale/uk")
    assert html =~ ~s(src="/js/site.js")
    assert html =~ "public-theme"
  end

  test "public pages vary by the language cookie and the browser's languages", %{conn: conn} do
    resp = get(conn, ~p"/news")
    assert get_resp_header(resp, "vary") == ["cookie, accept-language"]
  end

  test "the language menu sets only its own cookie and goes back", %{conn: conn} do
    resp =
      conn
      |> put_req_header("referer", "http://www.example.com/clubs?city=Northport")
      |> get(~p"/locale/uk")

    assert redirected_to(resp) == "/clubs?city=Northport"
    assert [cookie] = get_resp_header(resp, "set-cookie")
    assert cookie =~ "public_locale=uk"
    refute cookie =~ "_cab_key"
    refute cookie =~ "_public_key"
  end

  test "an unknown language is a 404 and another site is never the way back", %{conn: conn} do
    assert_error_sent 404, fn -> get(conn, ~p"/locale/fr") end

    resp = conn |> put_req_header("referer", "https://evil.example/x") |> get(~p"/locale/en")
    assert redirected_to(resp) == "/"
  end

  test "the page language follows the cookie, then the browser", %{conn: conn} do
    assert conn |> get(~p"/") |> html_response(200) =~ ~r{<html[^>]*lang="en"}

    assert conn
           |> put_req_header("accept-language", "uk-UA,uk;q=0.9,en;q=0.8")
           |> get(~p"/")
           |> html_response(200) =~ ~r{<html[^>]*lang="uk"}

    assert conn
           |> put_req_header("accept-language", "uk")
           |> put_req_cookie("public_locale", "en")
           |> get(~p"/")
           |> html_response(200) =~ ~r{<html[^>]*lang="en"}
  end

  test "with the Ukrainian choice the pages speak Ukrainian", %{conn: conn} do
    uk = put_req_cookie(conn, "public_locale", "uk")

    home = uk |> get(~p"/") |> html_response(200)
    assert home =~ "\u0413\u043e\u043b\u043e\u0432\u043d\u0430"
    assert home =~ ~s(class="beta-tag">\u0431\u0435\u0442\u0430)
    refute home =~ ">Home<"

    about = uk |> get(~p"/about") |> html_response(200)
    assert about =~ "UK League block one"
    assert about =~ "UK League timeline first"

    assert get_resp_header(get(uk, ~p"/"), "set-cookie") == []
  end
end
