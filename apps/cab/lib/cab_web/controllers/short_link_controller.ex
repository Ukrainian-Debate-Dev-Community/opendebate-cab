defmodule CabWeb.ShortLinkController do
  @moduledoc """
  Short links (`Cab.ShortLinks`): `/<code>` opens its target - a cab
  path, a URL on an allowed host, or a session's page; `/<code>/<n>`
  opens room n of a session (rooms are numbered inside the session).
  Anything that is not a live code is a plain 404.
  """
  use CabWeb, :controller

  alias Cab.Sessions
  alias Cab.Sessions.Session

  # GET /:short
  def session(conn, %{"short" => short}) do
    case Cab.ShortLinks.resolve(short) do
      {:path, path} -> redirect(conn, to: path)
      {:url, url} -> redirect(conn, external: url)
      {:session, %Session{club: %{archived_at: nil}} = session} -> open_session(conn, session)
      _ -> CabWeb.ErrorHTML.respond(conn, 404)
    end
  end

  defp open_session(conn, session),
    do: redirect(conn, to: ~p"/c/#{session.club.uuid}/s/#{session.uuid}")

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
          |> put_flash(
            :info,
            gettext("Room %{room} is not open yet; here is the session.", room: room)
          )
          |> redirect(to: page)
      end
    end)
  end

  # room links exist for sessions only
  defp with_session(conn, short, fun) do
    case Cab.ShortLinks.resolve(short) do
      {:session, %Session{club: %{archived_at: nil}} = session} -> fun.(session)
      _ -> CabWeb.ErrorHTML.respond(conn, 404)
    end
  end
end
