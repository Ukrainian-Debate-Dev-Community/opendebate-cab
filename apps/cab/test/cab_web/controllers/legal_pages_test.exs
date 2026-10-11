defmodule CabWeb.LegalPagesTest do
  use CabWeb.ConnCase, async: true

  test "the Policy and the Terms are public pages", %{conn: conn} do
    policy = conn |> get(~p"/policy") |> html_response(200)
    assert policy =~ "Who we are"
    assert policy =~ "ВМГО \u00ABФедерація Дебатів України\u00BB"
    assert policy =~ "Your rights"

    terms = conn |> get(~p"/terms") |> html_response(200)
    assert terms =~ "Fair use"
    assert terms =~ ~s(href="/policy")
  end

  test "each language reads its own copy of the documents", %{conn: conn} do
    policy = conn |> put_req_cookie("cab_locale", "uk") |> get(~p"/policy") |> html_response(200)
    assert policy =~ "Політика конфіденційності"
    refute policy =~ "Who we are"
  end

  test "the old /privacy address leads to the Policy", %{conn: conn} do
    assert conn |> get("/privacy") |> redirected_to() == "/policy"
  end

  test "the footer links Policy, Terms and Support; sign-in names both documents",
       %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)
    assert html =~ ~s(<a href="/policy">Policy</a>)
    assert html =~ ~s(<a href="/terms">Terms</a>)
    assert html =~ "Support</a>"
    refute html =~ "Privacy&amp;Policy"

    signin = conn |> get(~p"/signin") |> html_response(200)
    assert signin =~ ~s(href="/terms")
    assert signin =~ ~s(href="/policy")
  end
end
