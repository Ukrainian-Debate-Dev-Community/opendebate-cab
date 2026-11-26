defmodule CabWeb.FeedbackController do
  @moduledoc """
  The old feedback page's address (`/c/:club/s/:session/rooms/:id/feedback`):
  a team gives feedback on its hub now (My page, a guest's link page),
  so the address leads there; the head goes to the session's page,
  where every team's feedback is.
  """

  use CabWeb, :controller

  plug CabWeb.ClubScope, source: :club, require: :public

  # GET .../rooms/:id/feedback
  def new(conn, %{"session_uuid" => session_uuid}) do
    CabWeb.Hub.head_page(conn, fn conn ->
      redirect(conn, to: ~p"/c/#{conn.assigns.club.uuid}/owner/s/#{session_uuid}")
    end)
  end
end
