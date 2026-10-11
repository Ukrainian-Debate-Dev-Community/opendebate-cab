defmodule CabWeb.LegalPagesTest do
  use CabWeb.ConnCase, async: false

  test "the Policy and the Terms are public pages", %{conn: conn} do
    policy = conn |> get(~p"/policy") |> html_response(200)
    assert policy =~ "Test policy"
    assert policy =~ ~s(class="pbody legal-doc")

    terms = conn |> get(~p"/terms") |> html_response(200)
    assert terms =~ "Test terms"
    assert terms =~ ~s(href="/policy")
  end

  test "each language reads its own copy, English when it has none", %{conn: conn} do
    uk = conn |> put_req_cookie("cab_locale", "uk")
    assert uk |> get(~p"/policy") |> html_response(200) =~ "Тестова політика"
    assert uk |> get(~p"/terms") |> html_response(200) =~ "Test terms"
  end

  test "a deployment without documents answers 404", %{conn: conn} do
    dir = Application.get_env(:cab, :legal_dir)
    Application.put_env(:cab, :legal_dir, Path.join(dir, "missing"))
    on_exit(fn -> Application.put_env(:cab, :legal_dir, dir) end)

    assert_error_sent 404, fn -> get(conn, ~p"/policy") end
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
