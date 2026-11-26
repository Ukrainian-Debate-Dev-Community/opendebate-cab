defmodule CabWeb.TourTest do
  @moduledoc """
  The guided tour plays cab's real pages with demo data: every step's
  frame renders, and the part it spotlights, the fields it types into
  and what it clicks are all on it, so a page that changes shape fails
  here - the consistency check the tour stands for. Nothing reaches the
  engine (no stub is set) and nothing is written.
  """
  use CabWeb.ConnCase, async: true

  alias CabWeb.Tour

  test "/tour plays the tour; it reads as a list without script", %{conn: conn} do
    html = conn |> get(~p"/tour") |> html_response(200)
    assert html =~ ~s(id="tour")
    assert html =~ ~s(data-steps=)
    assert html =~ ~s(class="tour-slider")
    assert html =~ ~s(class="tour-chapters")
    assert html =~ ~s(class="tour-steps")

    # the three tours of before are this one
    assert conn |> get(~p"/tour/head") |> redirected_to() == "/tour"
    assert conn |> get(~p"/tour/frame/nothing") |> response(404)
  end

  for {step, index} <- Enum.with_index(Tour.get().steps), step.frame do
    @step step
    test "step #{index + 1} (#{step.frame}): the frame renders with all the step points at",
         %{conn: conn} do
      html = conn |> get(~p"/tour/frame/#{@step.frame}") |> html_response(200)
      page = LazyHTML.from_document(html)

      selectors =
        [@step.target, @step.click | Enum.map(@step.set ++ @step.fill, &elem(&1, 0))]
        |> Enum.reject(&is_nil/1)

      for selector <- selectors do
        assert Enum.count(LazyHTML.query(page, selector)) > 0, "#{@step.frame} misses #{selector}"
      end
    end
  end

  test "the tour opens and closes with a card, names whose eyes, and holds long enough to read" do
    tour = Tour.get()
    assert hd(tour.steps).frame == nil
    assert List.last(tour.steps).finale

    for step <- tour.steps do
      assert Tour.hold(step) >= 4000
      assert step.frame == nil or step.as, "#{step.frame} says nobody's eyes"
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
