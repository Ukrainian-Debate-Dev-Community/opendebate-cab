defmodule CabWeb.PageController do
  use CabWeb, :controller

  alias Cab.{Clubs, Sessions}
  alias Cab.Sessions.Session

  # GET / — signed-out: plain sign-in page; signed-in: the cabinet
  def home(conn, _params) do
    case conn.assigns.current_user do
      nil ->
        render(conn, :home)

      user ->
        memberships = Clubs.list_user_memberships(user)

        render(conn, :home,
          memberships: memberships,
          member_counts: Clubs.member_counts(Enum.map(memberships, & &1.club_id)),
          open_club: find_open_club(memberships),
          page_title: "my cabinet"
        )
    end
  end

  # The first of my clubs with a session currently open (sign-up or
  # running) — the cabinet's "what's happening now" banner.
  defp find_open_club(memberships) do
    memberships
    |> Enum.filter(&(&1.status == "approved"))
    |> Enum.find_value(fn membership ->
      with %Session{} = session <- List.first(Sessions.list_for_club(membership.club)),
           {:ok, %{stage: stage}} when stage in [:signup, :running] <-
             Sessions.state(%{session | club: membership.club}) do
        membership.club
      else
        _ -> nil
      end
    end)
  end
end
