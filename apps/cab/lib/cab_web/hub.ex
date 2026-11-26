defmodule CabWeb.Hub do
  @moduledoc """
  My page is where a participant works (their seat, the motion, the
  ballot, feedback, registration); a session's room, ballot and
  feedback pages are the club head's. `away/2` says where anyone else
  goes instead. A guest keeps these pages until their link page is the
  same hub.
  """
  use Gettext, backend: CabWeb.Gettext

  @doc "nil: the viewer stays (the head, a guest); else the path to send them to."
  def away(club_role, user) do
    cond do
      Cab.Clubs.covers?(club_role, :owner) -> nil
      user && Map.get(user, :guest, false) -> nil
      user -> "/me"
      true -> "/signin?" <> URI.encode_query(return_to: "/me")
    end
  end

  @doc "The word that goes with the redirect."
  def notice, do: gettext("Your room, the motion, the ballot and feedback are on My page.")

  @doc """
  A controller page that is the head's: `fun.(conn)` for those who
  stay, else the redirect with the notice.
  """
  def head_page(conn, fun) do
    case away(conn.assigns.club_role, conn.assigns.current_user) do
      nil ->
        fun.(conn)

      path ->
        conn
        |> Phoenix.Controller.put_flash(:info, notice())
        |> Phoenix.Controller.redirect(to: path)
    end
  end
end
