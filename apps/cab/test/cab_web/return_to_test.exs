defmodule CabWeb.ReturnToTest do
  # changes the app's :return_hosts, so not async
  use CabWeb.ConnCase, async: false

  import Cab.Fixtures

  alias CabWeb.ReturnTo

  setup do
    before = Application.get_env(:cab, :return_hosts)
    Application.put_env(:cab, :return_hosts, ["example.org"])
    on_exit(fn -> Application.put_env(:cab, :return_hosts, before) end)
  end

  test "local paths and the return hosts only" do
    assert ReturnTo.accept("/c/abc") == "/c/abc"
    assert ReturnTo.accept("https://example.org/manage") == "https://example.org/manage"
    assert ReturnTo.accept("https://EXAMPLE.org/manage") == "https://EXAMPLE.org/manage"

    for refused <- [
          "//evil.example/x",
          "/\\evil.example",
          "https://evil.example/manage",
          "https://example.org.evil.example/",
          "javascript:alert(1)",
          "example.org/manage",
          nil
        ] do
      assert ReturnTo.accept(refused) == nil, inspect(refused)
    end
  end

  test "signing in returns to a sibling site that asked", %{conn: conn} do
    user = user_fixture()

    back =
      conn
      |> init_test_session(%{return_to: "https://example.org/manage"})
      |> Phoenix.Controller.fetch_flash()
      |> CabWeb.AuthController.signed_in(user)

    assert redirected_to(back) == "https://example.org/manage"

    # an unknown host stored somehow is ignored
    home =
      build_conn()
      |> init_test_session(%{return_to: "https://evil.example/"})
      |> Phoenix.Controller.fetch_flash()
      |> CabWeb.AuthController.signed_in(user)

    assert redirected_to(home) == "/"
  end

  test "already signed in, /signin sends straight back", %{conn: conn} do
    user = user_fixture()
    signed = conn |> init_test_session(%{user_id: user.id})

    assert signed
           |> get(~p"/signin?#{[return_to: "https://example.org/manage"]}")
           |> redirected_to() == "https://example.org/manage"

    assert signed
           |> get(~p"/signin?#{[return_to: "https://evil.example/"]}")
           |> redirected_to() == "/"
  end

  test "only the sign-in that asked returns there", %{conn: conn} do
    # the provider hop needs an OAuth app configured (a dummy one here)
    oauth = Application.get_env(:ueberauth, Ueberauth.Strategy.Github.OAuth)

    Application.put_env(:ueberauth, Ueberauth.Strategy.Github.OAuth,
      client_id: "x",
      client_secret: "y"
    )

    on_exit(fn ->
      Application.put_env(:ueberauth, Ueberauth.Strategy.Github.OAuth, oauth || [])
    end)

    # the page carries the address on its buttons, nothing is stored yet
    page = conn |> get(~p"/signin?#{[return_to: "https://example.org/manage"]}")
    html = html_response(page, 200)
    assert html =~ ~s(href="/auth/github?return_to=https%3A%2F%2Fexample.org%2Fmanage")
    assert get_session(page, :return_to) == nil

    # going to the provider from that page stores it
    hop = conn |> get(~p"/auth/github?#{[return_to: "https://example.org/manage"]}")
    assert get_session(hop, :return_to) == "https://example.org/manage"

    # an abandoned one does not follow a later sign-in on cab itself:
    # /signin without an address clears it, and its buttons carry none
    fresh =
      build_conn()
      |> init_test_session(%{return_to: "https://example.org/manage"})
      |> get(~p"/signin")

    assert get_session(fresh, :return_to) == nil
    assert html_response(fresh, 200) =~ ~s(href="/auth/github")
    refute html_response(fresh, 200) =~ "return_to"

    # nor does a provider hop that carries none
    plain =
      build_conn()
      |> init_test_session(%{return_to: "https://example.org/manage"})
      |> get(~p"/auth/github")

    assert get_session(plain, :return_to) == nil
  end
end
