defmodule CabWeb.PageController do
  use CabWeb, :controller

  alias Cab.{Clubs, Sessions}
  alias Cab.Sessions.Session

  # GET / — P2 signed-out: the front page (pitch + clubs directory);
  # P3 signed-in: the cabinet (my clubs, my sessions, account)
  def home(conn, _params) do
    case conn.assigns.current_user do
      nil ->
        clubs = Clubs.list_clubs()
        club_ids = Enum.map(clubs, & &1.id)

        render(conn, :home,
          clubs: clubs,
          member_counts: Clubs.member_counts(club_ids),
          session_counts: Sessions.session_counts(club_ids)
        )

      user ->
        memberships = Clubs.list_user_memberships(user)
        tonight = tonight_by_club(memberships)

        render(conn, :home,
          memberships: memberships,
          tonight: tonight,
          open_club: find_open_club(memberships, tonight),
          history: Sessions.user_history(user),
          page_title: "my cabinet"
        )
    end
  end

  # The cabinet's Tonight column: each approved club's latest session
  # stage, as %{club_id => {session, stage}}.
  defp tonight_by_club(memberships) do
    for membership <- memberships, membership.status == "approved", into: %{} do
      state =
        with %Session{} = session <- List.first(Sessions.list_for_club(membership.club)),
             {:ok, %{stage: stage}} when stage != :done <-
               Sessions.state(%{session | club: membership.club}) do
          {session, stage}
        else
          _ -> nil
        end

      {membership.club_id, state}
    end
  end

  # The first of my clubs with a session open right now (sign-up or
  # running) — the cabinet's tonight banner.
  defp find_open_club(memberships, tonight) do
    Enum.find_value(memberships, fn membership ->
      case tonight[membership.club_id] do
        {_session, stage} when stage in [:signup, :running] -> membership.club
        _ -> nil
      end
    end)
  end
end
