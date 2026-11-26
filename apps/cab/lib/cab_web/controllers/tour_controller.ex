defmodule CabWeb.TourController do
  @moduledoc """
  The guided tours: `/tour` lists them, `/tour/:key` plays one (a frame
  over a bar with the caption and a progress slider), and
  `/tour/frame/:frame` serves a frame - one of cab's real pages
  rendered with the demo world (`CabWeb.Tour.Pages`). Nothing is read
  from the engine and nothing is written.
  """
  use CabWeb, :controller

  alias CabWeb.Tour

  # GET /tour
  def index(conn, _params) do
    render(conn, :index, tours: Tour.all(), page_title: gettext("Guided tours"))
  end

  # GET /tour/:key
  def show(conn, %{"key" => key}) do
    case Tour.get(key) do
      nil ->
        CabWeb.ErrorHTML.respond(conn, 404)

      tour ->
        conn
        |> put_layout(false)
        |> render(:show,
          tour: tour,
          others: Enum.reject(Tour.all(), &(&1.key == key)),
          page_title: tour.title
        )
    end
  end

  # GET /tour/frame/:frame - a demo page; the viewer's own identity
  # never shows in it
  def frame(conn, %{"frame" => frame}) do
    case Tour.Pages.frame(frame) do
      nil ->
        CabWeb.ErrorHTML.respond(conn, 404)

      {view, template, assigns} ->
        conn
        |> put_resp_header("x-robots-tag", "noindex")
        |> put_layout(false)
        |> put_view(html: view)
        |> render(template, assigns)
    end
  end
end
