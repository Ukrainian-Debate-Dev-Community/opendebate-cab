defmodule CabWeb.PageController do
  use CabWeb, :controller

  alias Cab.{Clubs, Invitations, Sessions}

  # GET / - the clubs directory with each club's next session, the
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

  # GET /policy - how cab handles personal data
  def policy(conn, _params), do: legal(conn, "policy", gettext("Policy"))

  # GET /terms - the terms of use
  def terms(conn, _params), do: legal(conn, "terms", gettext("Terms"))

  # GET /privacy - the policy's old address
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

  # Policy and Terms are documents kept outside the code, one file per
  # language in priv/legal/<locale>/, read on each request so an edit
  # shows without a release; a language without its own copy gets English.
  defp legal(conn, doc, title) do
    body =
      [Gettext.get_locale(CabWeb.Gettext), "en"]
      |> Enum.map(&Path.join([:code.priv_dir(:cab), "legal", &1, doc <> ".html"]))
      |> Enum.find_value(&(File.exists?(&1) && File.read!(&1)))

    render(conn, :legal, doc: doc, body: Phoenix.HTML.raw(body), page_title: title)
  end
end
