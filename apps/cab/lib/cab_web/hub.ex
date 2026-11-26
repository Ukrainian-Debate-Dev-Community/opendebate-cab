defmodule CabWeb.Hub do
  @moduledoc """
  My page is where a participant works (their seat, the motion, the
  ballot, feedback, registration); a guest's is their personal link's
  page, `/l/:code/hub`. A session's room, ballot and feedback pages
  are the club head's; `away/2` says where anyone else goes instead.
  """
  use Gettext, backend: CabWeb.Gettext

  @doc "The viewer's hub: My page, a guest's link page, or nil (anonymous, a dead link)."
  def home(nil), do: nil

  def home(user) do
    if Map.get(user, :guest, false) do
      case Cab.Links.latest_code(user) do
        nil -> nil
        code -> "/l/#{code}/hub"
      end
    else
      "/me"
    end
  end

  @doc "nil: the viewer stays (the head); else the path to send them to."
  def away(club_role, user) do
    cond do
      Cab.Clubs.covers?(club_role, :owner) -> nil
      path = home(user) -> path
      true -> "/signin?" <> URI.encode_query(return_to: "/me")
    end
  end

  @doc "The word that goes with the redirect."
  def notice(user) do
    if user && Map.get(user, :guest, false),
      do:
        gettext("Your room, the motion, the ballot and feedback are on your personal link page."),
      else: gettext("Your room, the motion, the ballot and feedback are on My page.")
  end

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
        |> Phoenix.Controller.put_flash(:info, notice(conn.assigns.current_user))
        |> Phoenix.Controller.redirect(to: path)
    end
  end
end
