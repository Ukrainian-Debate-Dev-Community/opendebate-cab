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
      recent: Sessions.club_sessions(club),
      members: Clubs.list_members(club),
      page_title: club.name
    )
  end

  # GET /c/:club_uuid/standings[/:tab] — teams · speakers · judges
  # scoped to this club (RULE 0 passthrough); Clubs is global-only
  def standings(conn, params) do
    club = conn.assigns.club

    case params["tab"] || "teams" do
      tab when tab in ~w(teams speakers judges) ->
        scope = standings_scope(club, params["session"])

        if standings_allowed?(club, conn, scope) do
          conn
          |> CabWeb.Caching.no_store()
          |> render(:standings,
            tab: tab,
            scope: scope,
            rows: standings_rows(tab, scope),
            archive: Sessions.archive(club),
            page_title: "#{club.name} · standings"
          )
        else
          deny_private_standings(conn, club)
        end

      _tab ->
        conn |> send_resp(404, "not found") |> halt()
    end
  end

  # default: the club's latest finished session; ?session=uuid walks
  # the archive (only finished sessions resolve)
  defp standings_scope(club, nil), do: Standings.latest_finished(club)

  defp standings_scope(club, session_uuid) do
    case Sessions.get_for_club(club, session_uuid) do
      nil -> nil
      session -> Standings.finished(%{session | club: club})
    end
  end

  # private = standings only: members (ladder) always pass; a guest or
  # user who PLAYED the shown session keeps that session's data — any
  # other session is lost to them
  defp standings_allowed?(%{is_private: false}, _conn, _scope), do: true

  defp standings_allowed?(_club, conn, scope) do
    Clubs.covers?(conn.assigns.club_role, :member) or
      participant_of?(conn.assigns.current_user, scope)
  end

  defp participant_of?(nil, _scope), do: false
  defp participant_of?(_user, nil), do: false

  defp participant_of?(%{node_user_id: id}, %{actor: actor, session: session})
       when is_integer(id) do
    case Cab.EngineApi.list_participants(actor, session.engine_event_id) do
      {:ok, participants} -> Enum.any?(participants, &(&1["user_id"] == id))
      _ -> false
    end
  end

  defp participant_of?(_user, _scope), do: false

  defp deny_private_standings(conn, _club) do
    case conn.assigns.current_user do
      nil ->
        conn
        |> put_flash(:error, "This club's standings are members-only — please sign in.")
        |> redirect(to: ~p"/signin")
        |> halt()

      _user ->
        conn |> send_resp(403, "standings are members-only in this club") |> halt()
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
