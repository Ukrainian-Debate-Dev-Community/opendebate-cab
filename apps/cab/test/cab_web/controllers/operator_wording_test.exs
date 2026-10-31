defmodule CabWeb.OperatorWordingTest do
  # changes the app's :operator, so not async
  use CabWeb.ConnCase, async: false

  defmodule League do
    @behaviour CabWeb.Operator

    @impl true
    def info do
      %{
        directory_title: "Debate clubs of the League",
        welcome: "The League's clubs, all in one place.",
        tagline: "The home of the League's clubs"
      }
    end
  end

  setup do
    before = Application.get_env(:cab, :operator)
    on_exit(fn -> Application.put_env(:cab, :operator, before) end)
  end

  test "without an operator, cab names no organisation", %{conn: conn} do
    Application.put_env(:cab, :operator, nil)

    home = conn |> get(~p"/") |> html_response(200)
    assert home =~ "Debate clubs"
    assert home =~ "follow standings and your own results in one place"
    refute home =~ "Ukrain"

    signin = build_conn() |> get(~p"/signin") |> html_response(200)
    assert signin =~ "The home of debate clubs"
    refute signin =~ "Ukrain"
  end

  test "the operator's own words replace them", %{conn: conn} do
    Application.put_env(:cab, :operator, League)

    home = conn |> get(~p"/") |> html_response(200)
    assert home =~ "Debate clubs of the League"
    assert home =~ "The League&#39;s clubs, all in one place."

    signin = build_conn() |> get(~p"/signin") |> html_response(200)
    assert signin =~ "The home of the League&#39;s clubs"
  end
end
