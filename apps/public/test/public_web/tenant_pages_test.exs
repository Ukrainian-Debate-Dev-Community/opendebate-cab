defmodule PublicWeb.TenantPagesTest do
  @moduledoc """
  The organisation's part of the pages comes from the tenant folder:
  the names, footer, contacts, home and about texts, labels and the map,
  in the page language.
  """
  # some tests load a changed tenant into the shared :persistent_term
  use PublicWeb.ConnCase, async: false

  import Swoosh.TestAssertions

  alias Public.Tenant

  defp page(conn, path, locale) do
    conn |> put_req_cookie("public_locale", locale) |> get(path) |> html_response(200)
  end

  # a copy of the test tenant with `change` applied, loaded until the test ends
  defp with_tenant(change) do
    fixture = Path.expand("../support/tenant", __DIR__)
    dir = Path.join(System.tmp_dir!(), "tenant-pages-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.cp!(Path.join(fixture, "map.json"), Path.join(dir, "map.json"))
    tenant = fixture |> Path.join("tenant.json") |> File.read!() |> Jason.decode!() |> change.()
    File.write!(Path.join(dir, "tenant.json"), Jason.encode!(tenant))
    Tenant.load!(dir)

    on_exit(fn ->
      Tenant.load!()
      File.rm_rf!(dir)
    end)
  end

  test "the frame: wordmark, title and footer", %{conn: conn} do
    for {locale, prefix} <- [{"en", "League "}, {"uk", "UK League "}] do
      home = page(conn, ~p"/", locale)
      assert home =~ "<title>#{prefix}site title</title>"
      assert home =~ ~s(class="wordmark ua-brand" href="/">LeagueSite)
      assert home =~ "<p>#{prefix}org</p>"
      assert home =~ "<p>#{prefix}since 2001</p>"
      assert home =~ ~s(<a href="mailto:office@example.org">office@example.org</a>)
      assert home =~ ~s(<a href="https://chat.example.org/league">chat.example.org/league</a>)

      news = page(conn, ~p"/news", locale)
      assert news =~ "<title>" and news =~ " | LeagueSite</title>"
      assert news =~ "#{prefix}news"
    end
  end

  test "the home page", %{conn: conn} do
    for {locale, prefix} <- [{"en", "League "}, {"uk", "UK League "}] do
      home = page(conn, ~p"/", locale)

      for text <- [
            "home notice",
            "home kicker",
            "home heading",
            "home heading em",
            "home lead",
            "about link",
            "story first",
            "story second",
            "branches",
            "map"
          ] do
        assert home =~ prefix <> text, "#{locale}: #{text}"
      end

      assert home =~ ~s(id="under-construction")
      assert home =~ ~s(viewBox="0 0 200 100")
      assert home =~ ~s(points="10,10 190,10 190,90 10,90")
    end
  end

  test "without a notice the home page shows none", %{conn: conn} do
    with_tenant(&put_in(&1, ["home", "notice"], nil))
    refute conn |> get(~p"/") |> html_response(200) =~ "under-construction"
  end

  test "the about page: title, blocks, timeline, branches, contacts", %{conn: conn} do
    for {locale, prefix} <- [{"en", "League "}, {"uk", "UK League "}] do
      about = page(conn, ~p"/about", locale)

      for text <- [
            "block one",
            "block two text",
            "block three",
            "timeline first",
            "timeline third",
            "branches map",
            "office",
            "support",
            "chat"
          ] do
        assert about =~ prefix <> text, "#{locale}: #{text}"
      end

      assert about =~ "<b>01/2001</b>"
      assert about =~ ~s(class="ua-blob b3")
      assert about =~ ~s(href="mailto:support@example.org")
    end

    assert page(conn, ~p"/about", "en") =~ ~r/League\s*<br>about\s*<br>title words/
  end

  test "the branch map names its cities in the page language and moves labels", %{conn: conn} do
    en = page(conn, ~p"/about", "en")
    uk = page(conn, ~p"/about", "uk")

    assert en =~ ~r/<text[^>]*>Northport<\/text>/
    assert uk =~ ~r/<text[^>]*>UK Northport<\/text>/
    # a city the map does not name keeps its own name in every language
    assert uk =~ ~r/<text[^>]*text-anchor="end"[^>]*>Southport<\/text>/
  end

  test "the page labels", %{conn: conn} do
    for {locale, prefix} <- [{"en", "League "}, {"uk", "UK League "}] do
      assert page(conn, ~p"/news", locale) =~ "<h1>#{prefix}news</h1>"
      assert page(conn, ~p"/clubs", locale) =~ "<h1>#{prefix}clubs</h1>"
      assert page(conn, ~p"/calendar", locale) =~ "#{prefix}calendar lead"
    end
  end

  test "error pages carry the tenant's name", %{conn: conn} do
    assert conn |> get("/no-such-page") |> html_response(404) =~ " | LeagueSite</title>"
  end

  test "without event_requests_email nobody but the requester is e-mailed", %{conn: conn} do
    with_tenant(&Map.put(&1, "event_requests_email", nil))
    CabWeb.RateLimit.reset()

    answers = %{
      "email" => "org@example.org",
      "name" => "Northport Open",
      "dates" => "2026-11-14",
      "city" => "Northport",
      "format" => "BP",
      "details" => "Two days."
    }

    conn |> post(~p"/calendar/request", %{answers: answers}) |> html_response(200)

    assert_email_sent(fn email -> email.to == [{"", "org@example.org"}] end)
    refute_email_sent()
  end
end
