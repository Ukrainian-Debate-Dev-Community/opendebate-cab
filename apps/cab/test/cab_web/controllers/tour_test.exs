defmodule CabWeb.TourTest do
  @moduledoc """
  The guided tours play cab's real pages with demo data: every step's
  frame renders and every target it spotlights is on it, so a page that
  changes shape fails here - the consistency check the tours stand for.
  Nothing reaches the engine (no stub is set) and nothing is written.
  """
  use CabWeb.ConnCase, async: true

  alias CabWeb.Tour

  test "the list offers every tour", %{conn: conn} do
    html = conn |> get(~p"/tour") |> html_response(200)

    for tour <- Tour.all() do
      assert html =~ ~s(href="/tour/#{tour.key}")
      assert html =~ Phoenix.HTML.html_escape(tour.title) |> Phoenix.HTML.safe_to_string()
    end
  end

  test "a player carries its steps and reads as a list without script", %{conn: conn} do
    html = conn |> get(~p"/tour/head") |> html_response(200)
    assert html =~ ~s(id="tour")
    assert html =~ ~s(data-steps=)
    assert html =~ ~s(class="tour-slider")
    assert html =~ "The club head&#39;s tour"
    assert html =~ ~s(href="/tour/participant")

    assert conn |> get(~p"/tour/nobody") |> response(404)
    assert conn |> get(~p"/tour/frame/nothing") |> response(404)
  end

  for tour <- Tour.all(), {step, index} <- Enum.with_index(tour.steps), step.frame do
    @step step
    test "#{tour.key} step #{index + 1} (#{step.frame}): the frame renders, #{step.target || "the page"} is on it",
         %{conn: conn} do
      html = conn |> get(~p"/tour/frame/#{@step.frame}") |> html_response(200)

      if target = @step.target do
        found = html |> LazyHTML.from_document() |> LazyHTML.query(target)
        assert Enum.count(found) > 0, "#{@step.frame} misses #{target}"
      end
    end
  end

  test "a frame shows the demo, never the viewer", %{conn: conn} do
    viewer = Cab.Fixtures.user_fixture(%{username: "real-viewer"})

    html =
      conn
      |> init_test_session(%{user_id: viewer.id})
      |> get(~p"/tour/frame/me-now")
      |> html_response(200)

    refute html =~ "real-viewer"
    assert html =~ "Anna Shevchuk"
  end
end
