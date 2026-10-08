defmodule CabWeb.ClubPublicController do
  use CabWeb, :controller

  alias Cab.{Clubs, Sessions, Standings}

  plug CabWeb.ClubScope, [source: :club, require: :public] when action in [:show, :standings]

  plug CabWeb.ClubScope,
       [source: :club, require: :authenticated] when action in [:join_form, :join]

  # GET /c/:club_uuid — the club page, a PROFILE VIEW: about card
  # (meeting info, description, contacts), recent finished sessions,
  # join CTA. The owner edits the same page in place at /owner.
  def show(conn, _params) do
    club = conn.assigns.club

    render(conn, :show,
      recent: Sessions.archive(club),
      members: Clubs.list_members(club),
      page_title: club.name
    )
  end

  # GET /c/:club_uuid/standings[/:tab] — the SAME four tabs as the
  # global standings, scoped to this club (RULE 0 passthrough)
  def standings(conn, params) do
    club = conn.assigns.club

    case params["tab"] || "teams" do
      tab when tab in ~w(teams speakers judges) ->
        scope = Standings.latest_finished(club)

        conn
        |> CabWeb.Caching.no_store()
        |> render(:standings,
          tab: tab,
          scope: scope,
          rows: standings_rows(tab, scope),
          page_title: "#{club.name} · standings"
        )

      "clubs" ->
        render(conn, :standings,
          tab: "clubs",
          scope: nil,
          rows: Standings.clubs([club]),
          page_title: "#{club.name} · standings"
        )

      _tab ->
        conn |> send_resp(404, "not found") |> halt()
    end
  end

  defp standings_rows(_tab, nil), do: []
  defp standings_rows("teams", scope), do: Standings.teams(scope)
  defp standings_rows("speakers", scope), do: Standings.speakers(scope)
  defp standings_rows("judges", scope), do: Standings.judges(scope)

  # GET /c/:club_uuid/join — the join-request FORM (required: about
  # me + contact). Never a bare button.
  def join_form(conn, _params) do
    render_join(conn, %{}, %{})
  end

  # POST /c/:club_uuid/join — creates the pending membership with
  # the form's answers; the head reads them in Requests
  def join(conn, params) do
    club = conn.assigns.club

    case Clubs.request_join(conn.assigns.current_user, club, params) do
      {:ok, _membership} ->
        conn
        |> put_flash(:info, "request sent — the club head will approve it")
        |> redirect(to: ~p"/c/#{club.uuid}")

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(422)
        |> render_join(params, join_errors(changeset))
    end
  end

  defp render_join(conn, params, errors) do
    render(conn, :join,
      message: params["message"],
      contact: params["contact"],
      errors: errors,
      page_title: "#{conn.assigns.club.name} · join"
    )
  end

  defp join_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.flat_map(fn
      {field, [message | _rest]} when field in [:message, :contact] -> [{field, message}]
      {_field, [message | _rest]} -> [{:message, message}]
    end)
    |> Map.new()
  end
end
