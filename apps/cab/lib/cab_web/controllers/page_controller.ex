defmodule CabWeb.PageController do
  use CabWeb, :controller

  alias Cab.{Clubs, Invitations, Sessions}

  # GET / — the clubs directory with each club's next session, the
  # same for everyone; signed in, banners point at a session open in
  # one of my clubs and at invitations waiting on My page
  def home(conn, _params) do
    clubs = Clubs.list_clubs()
    next = Sessions.next_by_club(clubs)

    {open_club, invitations} =
      case conn.assigns.current_user do
        nil ->
          {nil, 0}

        user ->
          {find_open_club(Clubs.list_user_memberships(user), next),
           length(Invitations.for_user(user))}
      end

    render(conn, :home,
      clubs: clubs,
      member_counts: Clubs.member_counts(Enum.map(clubs, & &1.id)),
      tonight: next,
      open_club: open_club,
      invitations: invitations
    )
  end

  # GET /policy — how cab handles personal data
  def policy(conn, _params), do: render(conn, :policy, page_title: "Policy")

  # GET /terms — the terms of use
  def terms(conn, _params), do: render(conn, :terms, page_title: "Terms")

  # GET /privacy — the policy's old address
  def privacy_moved(conn, _params), do: redirect(conn, to: ~p"/policy")

  # The first of my clubs with a session open right now (registration
  # or running), for the banner above the directory.
  defp find_open_club(memberships, next) do
    Enum.find_value(memberships, fn membership ->
      case membership.status == "approved" && next[membership.club_id] do
        {_session, stage, _rooms} when stage in [:signup, :running] -> membership.club
        _ -> nil
      end
    end)
  end
end
