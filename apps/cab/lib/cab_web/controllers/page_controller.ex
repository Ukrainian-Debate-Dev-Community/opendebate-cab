defmodule CabWeb.PageController do
  use CabWeb, :controller

  alias Cab.{Clubs, Sessions}
  alias Cab.Sessions.Session

  # GET / — public: the clubs directory with each club's next
  # session; signed in: the cabinet (my clubs + my schedule)
  def home(conn, _params) do
    case conn.assigns.current_user do
      nil ->
        clubs = Clubs.list_clubs()

        render(conn, :home,
          clubs: clubs,
          member_counts: Clubs.member_counts(Enum.map(clubs, & &1.id)),
          tonight: tonight_by_club(clubs)
        )

      user ->
        memberships = Clubs.list_user_memberships(user)

        clubs =
          for membership <- memberships, membership.status == "approved", do: membership.club

        tonight = tonight_by_club(clubs)

        render(conn, :home,
          memberships: memberships,
          tonight: tonight,
          open_club: find_open_club(memberships, tonight),
          schedule: Sessions.user_schedule(user),
          invitations: Cab.Invitations.for_user(user),
          page_title: "my cab"
        )
    end
  end

  # GET /policy — how cab handles personal data
  def policy(conn, _params), do: render(conn, :policy, page_title: "Policy")

  # GET /terms — the terms of use
  def terms(conn, _params), do: render(conn, :terms, page_title: "Terms")

  # GET /privacy — the policy's old address
  def privacy_moved(conn, _params), do: redirect(conn, to: ~p"/policy")

  # The Next session column: each club's unfinished session and its
  # stage, as %{club_id => {session, stage, rooms}} — cab's own
  # records, no engine call; no unfinished session reads as nil.
  defp tonight_by_club(clubs) do
    for club <- clubs, into: %{} do
      case Sessions.current_for_club(club) do
        %Session{} = session ->
          {club.id, {session, Sessions.stage_of(session), session.rooms_count}}

        nil ->
          {club.id, nil}
      end
    end
  end

  # The first of my clubs with a session open right now (sign-up or
  # running) — the cabinet's tonight banner.
  defp find_open_club(memberships, tonight) do
    Enum.find_value(memberships, fn membership ->
      case tonight[membership.club_id] do
        {_session, stage, _rooms} when stage in [:signup, :running] -> membership.club
        _ -> nil
      end
    end)
  end
end
