defmodule CabWeb.LocaleTest do
  use CabWeb.ConnCase, async: true

  alias CabWeb.Locale

  test "English unless the browser prefers Ukrainian" do
    assert Locale.from_header(["uk-UA,uk;q=0.9,en;q=0.8"]) == "uk"
    assert Locale.from_header(["en-US,en;q=0.9,uk;q=0.8"]) == "en"
    assert Locale.from_header(["de-DE,uk;q=0.7"]) == "uk"
    assert Locale.from_header(["de-DE,fr;q=0.7"]) == nil
    assert Locale.from_header([]) == nil
  end

  test "pages render in the browser's language, the switch overrides it", %{conn: conn} do
    html =
      conn
      |> put_req_header("accept-language", "uk-UA,uk;q=0.9")
      |> get(~p"/")
      |> html_response(200)

    assert html =~ ~r/<html[^>]*lang="uk"/
    assert html =~ ~s(href="/locale/en")

    english = conn |> get(~p"/") |> html_response(200)
    assert english =~ ~r/<html[^>]*lang="en"/

    switched =
      conn
      |> put_req_header("referer", "http://www.example.com/standings/teams")
      |> get(~p"/locale/en")

    assert redirected_to(switched) == "/standings/teams"
    assert switched.resp_cookies["cab_locale"].value == "en"

    kept =
      conn
      |> put_req_cookie("cab_locale", "en")
      |> put_req_header("accept-language", "uk-UA")
      |> get(~p"/")
      |> html_response(200)

    assert kept =~ ~r/<html[^>]*lang="en"/
  end

  test "the switch never sends you to another site, and knows only its languages",
       %{conn: conn} do
    away =
      conn |> put_req_header("referer", "https://evil.example/phish") |> get(~p"/locale/uk")

    assert redirected_to(away) == "/"
    assert conn |> get(~p"/locale/de") |> response(404)
  end
end
