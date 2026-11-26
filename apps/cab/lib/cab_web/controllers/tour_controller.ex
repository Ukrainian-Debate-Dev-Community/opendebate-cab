defmodule CabWeb.TourController do
  @moduledoc """
  The guided tour: `/tour` plays it (a frame over a bar with the
  chapters and the progress), and `/tour/frame/:frame` serves a frame -
  one of cab's real pages rendered with the demo world
  (`CabWeb.Tour.Pages`). Nothing is read from the engine and nothing is
  written.
  """
  use CabWeb, :controller

  alias CabWeb.Tour

  # GET /tour
  def show(conn, _params) do
    tour = Tour.get()

    conn
    |> put_layout(false)
    |> render(:show, tour: tour, page_title: tour.title)
  end

  # GET /tour/:key - the three tours of before are one now
  def redirect_old(conn, _params), do: redirect(conn, to: ~p"/tour")

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
