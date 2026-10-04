defmodule CabWeb.ClubPublicController do
  use CabWeb, :controller

  alias Cab.{Clubs, Sessions}
  alias Cab.Sessions.Session

  plug CabWeb.ClubScope, [source: :club, require: :public] when action in [:show, :session]
  plug CabWeb.ClubScope, [source: :club, require: :authenticated] when action == :join

  # GET /c/:club_uuid — public tree: profile + history (rows link to
  # the public session detail page)
  def show(conn, _params) do
    club = conn.assigns.club

    history =
      case Clubs.club_history(club) do
        {:ok, history} -> history
        {:error, _message} -> []
      end

    session_uuids =
      Map.new(Sessions.list_for_club(club), &{&1.engine_event_id, &1.uuid})

    render(conn, :show,
      history: history,
      session_uuids: session_uuids,
      members: Clubs.list_members(club),
      page_title: club.name
    )
  end

  # GET /c/:club_uuid/s/:session_uuid — the public session detail
  # page: name/date, stage, rooms with teams and speakers, motions,
  # confirmed results (ranks), winner
  def session(conn, %{"session_uuid" => session_uuid}) do
    club = conn.assigns.club

    with %Session{} = session <- Sessions.get_for_club(club, session_uuid),
         {:ok, state} <- Sessions.state(%{session | club: club}) do
      render(conn, :session,
        session: session,
        state: state,
        winner: Sessions.winner_from_rooms(state.rooms),
        page_title: "#{club.name} · #{state.event["name"]}"
      )
    else
      nil ->
        conn |> send_resp(404, "not found") |> halt()

      {:error, message} ->
        conn
        |> put_flash(:error, if(is_binary(message), do: message, else: "session unavailable"))
        |> redirect(to: ~p"/c/#{club.uuid}")
    end
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
