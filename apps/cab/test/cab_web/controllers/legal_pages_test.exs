defmodule CabWeb.LegalPagesTest do
  use CabWeb.ConnCase, async: false

  test "the Policy and the Terms are public pages", %{conn: conn} do
    policy = conn |> get(~p"/policy") |> html_response(200)

    assert policy =~
             ~s(<header><h1>Test policy</h1><p class="doc-meta">Last updated: 1 January 2026</p></header>)

    assert policy =~ ~s(<mark class="todo">[address]</mark>)
    assert policy =~ ~s(<a href="/terms">Terms</a>)
    refute policy =~ "<script>alert"

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

  defmodule Operator do
    def info, do: %{support_email: "help@example.org", org_text: "Run by Example."}
  end

  test "the footer links Policy and Terms, and Support once an operator gives one; sign-in names both documents",
       %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)
    assert html =~ ~s(<a href="/policy">Policy</a>)
    assert html =~ ~s(<a href="/terms">Terms</a>)
    refute html =~ "Support"
    refute html =~ "Privacy&amp;Policy"

    Application.put_env(:cab, :operator, Operator)
    on_exit(fn -> Application.delete_env(:cab, :operator) end)
    html = conn |> get(~p"/") |> html_response(200)
    assert html =~ ~s(href="mailto:help@example.org")
    assert html =~ "Run by Example."

    signin = conn |> get(~p"/signin") |> html_response(200)
    assert signin =~ ~s(href="/terms")
    assert signin =~ ~s(href="/policy")
  end
end
