defmodule CabWeb.ClubPublicController do
  use CabWeb, :controller

  alias Cab.{Clubs, Sessions}

  plug CabWeb.ClubScope, [source: :club, require: :public] when action in [:show, :standings]
  plug CabWeb.ClubScope, [source: :club, require: :authenticated] when action == :join

  # GET /c/:club_uuid — P4 club welcome: about card, recent sessions
  # (-> P6), top-members teaser (-> P7)
  def show(conn, _params) do
    club = conn.assigns.club
    standings = Sessions.club_standings(club)

    render(conn, :show,
      recent: Enum.take(standings.winners, 5),
      top_members: Enum.take(standings.members, 3),
      members: Clubs.list_members(club),
      page_title: club.name
    )
  end

  # GET /c/:club_uuid/standings — P7 club standings: member stats
  # across sessions + the session winners timeline (-> P6)
  def standings(conn, _params) do
    club = conn.assigns.club
    standings = Sessions.club_standings(club)

    render(conn, :standings,
      members: standings.members,
      winners: standings.winners,
      page_title: "#{club.name} · standings"
    )
  end

  # POST /c/:club_uuid/join — HTML twin of the join-requests API
  # action: same context call, but the browser lands back on the
  # club page with a banner instead of raw JSON
  def join(conn, _params) do
    club = conn.assigns.club

    case Clubs.request_join(conn.assigns.current_user, club) do
      {:ok, _membership} ->
        conn
        |> put_flash(:info, "request sent — the club head will approve it")
        |> redirect(to: ~p"/c/#{club.uuid}")

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_flash(:error, join_error(changeset))
        |> redirect(to: ~p"/c/#{club.uuid}")
    end
  end

  defp join_error(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.flat_map(fn {_field, messages} -> messages end)
    |> List.first() || "could not send the join request"
  end
end
