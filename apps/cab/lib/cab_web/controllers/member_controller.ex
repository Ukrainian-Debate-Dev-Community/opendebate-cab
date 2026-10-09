defmodule CabWeb.MemberController do
  use CabWeb, :controller

  alias Cab.Clubs

  plug CabWeb.ClubScope, source: :club, require: :roster

  # GET /c/:club_uuid/members — the roster: public for a public club,
  # members-only for a private one (the owner's view with requests and
  # revoke lives in the owner tree)
  def members(conn, _params) do
    club = conn.assigns.club

    render(conn, :members,
      members: Clubs.list_members(club),
      page_title: "#{club.name} — members"
    )
  end
end
