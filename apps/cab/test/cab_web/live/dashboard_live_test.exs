defmodule CabWeb.DashboardLiveTest do
  use CabWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "mounts and lists public engine events", %{conn: conn} do
    Req.Test.stub(Core.Engine, fn conn ->
      assert conn.request_path == "/api/events"

      Req.Test.json(conn, %{
        "status" => "success",
        "data" => [
          %{
            "id" => 1,
            "name" => "Kyiv Open",
            "status" => "scheduled",
            "Organisation" => %{"id" => 1, "name" => "Debate Society"}
          }
        ]
      })
    end)

    {:ok, view, html} = live(conn, ~p"/")

    assert has_element?(view, "#create-tournament-form")
    assert html =~ "Kyiv Open"
    assert html =~ "not signed in"
  end

  test "shows the engine error inline when the engine is down", %{conn: conn} do
    Req.Test.stub(Core.Engine, fn conn ->
      Req.Test.transport_error(conn, :econnrefused)
    end)

    {:ok, view, html} = live(conn, ~p"/")

    assert has_element?(view, "#inline-error")
    assert html =~ "engine unreachable"
  end
end
