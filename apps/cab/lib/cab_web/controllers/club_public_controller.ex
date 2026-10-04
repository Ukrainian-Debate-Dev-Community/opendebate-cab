defmodule CabWeb.ClubPublicController do
  use CabWeb, :controller

  alias Cab.Clubs

  plug CabWeb.ClubScope, source: :club, require: :public

  # GET /c/:club_uuid — public tree: profile + history
  def show(conn, _params) do
    club = conn.assigns.club

    history =
      case Clubs.club_history(club) do
        {:ok, history} -> history
        {:error, _message} -> []
      end

    render(conn, :show,
      history: history,
      members: Clubs.list_members(club),
      page_title: club.name
    )
  end
end
