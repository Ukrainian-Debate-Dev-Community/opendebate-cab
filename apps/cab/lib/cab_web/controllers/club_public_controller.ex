defmodule CabWeb.ClubPublicController do
  use CabWeb, :controller

  alias Cab.Clubs

  plug CabWeb.ClubScope, [source: :club, require: :public] when action == :show
  plug CabWeb.ClubScope, [source: :club, require: :authenticated] when action == :join

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
