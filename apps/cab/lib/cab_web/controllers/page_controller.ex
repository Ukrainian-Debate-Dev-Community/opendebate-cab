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
          history: Sessions.user_history(user),
          page_title: "my cab"
        )
    end
  end

  # The Tonight column, written out as words: each club's latest
  # session stage, as %{club_id => {session, stage, rooms}}. Engine
  # trouble (or a finished session) reads as quiet.
  defp tonight_by_club(clubs) do
    for club <- clubs, into: %{} do
      state =
        with %Session{} = session <- List.first(Sessions.list_for_club(club)),
             {:ok, %{stage: stage} = state} when stage != :done <-
               Sessions.state(%{session | club: club}) do
          {session, stage, length(state.rooms)}
        else
          _ -> nil
        end

      {club.id, state}
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
