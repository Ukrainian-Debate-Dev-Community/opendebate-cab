defmodule CabWeb.ShortLinkController do
  @moduledoc """
  Short links: `/<code>` opens the session, `/<code>/<n>` its room n
  (rooms are numbered inside the session). Anything that is not a
  live code is a plain 404.
  """
  use CabWeb, :controller

  alias Cab.Sessions
  alias Cab.Sessions.Session

  # GET /:short
  def session(conn, %{"short" => short}) do
    with_session(conn, short, fn session ->
      redirect(conn, to: ~p"/c/#{session.club.uuid}/s/#{session.uuid}")
    end)
  end

  # GET /:short/:room
  def room(conn, %{"short" => short, "room" => room}) do
    with_session(conn, short, fn session ->
      page = ~p"/c/#{session.club.uuid}/s/#{session.uuid}"

      with {no, ""} when no > 0 <- Integer.parse(room),
           id when is_integer(id) <- Sessions.room_id_by_number(session, no) do
        redirect(conn, to: ~p"/c/#{session.club.uuid}/s/#{session.uuid}/rooms/#{id}")
      else
        _ ->
          conn
          |> put_flash(:info, "Room #{room} is not open yet; here is the session.")
          |> redirect(to: page)
      end
    end)
  end

  defp with_session(conn, short, fun) do
    with true <- Session.short_code?(short),
         %Session{club: %{archived_at: nil}} = session <- Sessions.get_by_short_code(short) do
      fun.(session)
    else
      _ -> CabWeb.ErrorHTML.respond(conn, 404)
    end
  end
end
