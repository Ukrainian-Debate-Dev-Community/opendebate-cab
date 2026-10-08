defmodule CabWeb.PageController do
  use CabWeb, :controller

  alias Cab.{Clubs, Sessions}
  alias Cab.Sessions.Session

  # GET / — the global welcome on the sidenav shell: public = the
  # clubs directory (with the words "Tonight" column); signed in =
  # the same page with my clubs and my sessions added (the cabinet)
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
          page_title: "my cab"
        )
    end
  end

  # GET /privacy — the data & privacy policy, public
  def privacy(conn, _params) do
    render(conn, :privacy, page_title: "Privacy&Policy")
  end

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
