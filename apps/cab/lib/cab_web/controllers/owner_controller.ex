defmodule CabWeb.OwnerController do
  use CabWeb, :controller

  alias Cab.{Clubs, Links, Sessions}
  alias Cab.Clubs.Membership
  alias Cab.Links.Link
  alias Cab.Sessions.Session

  plug CabWeb.ClubScope, source: :club, require: :owner

  # ---------------------------------------------------------------
  # The club page, owner path: the SAME profile page as /c/:club but
  # as an edit-in-place form (Save lives in the chrome)
  # ---------------------------------------------------------------

  # GET /c/:club_uuid/owner
  def club(conn, _params) do
    render(conn, :club, page_title: "#{conn.assigns.club.name} · edit")
  end

  # POST /c/:club_uuid/owner/club — the in-place save; twin of
  # PATCH /api/v1/clubs/:uuid
  def update_club(conn, params) do
    attrs =
      Map.take(params, ["name", "city", "meeting_info", "description", "contacts", "is_private"])

    case Clubs.update_club(conn.assigns.club, attrs) do
      {:ok, _club} ->
        conn
        |> put_flash(:info, "club profile saved")
        |> redirect(to: ~p"/c/#{conn.assigns.club.uuid}/owner")

      {:error, %Ecto.Changeset{}} ->
        conn
        |> put_flash(:error, "the club needs a name")
        |> redirect(to: ~p"/c/#{conn.assigns.club.uuid}/owner")
    end
  end

  # ---------------------------------------------------------------
  # Sessions archive (owner path): previous progress + the
  # open-session form (gold "Open new session" in the chrome)
  # ---------------------------------------------------------------

  # GET /c/:club_uuid/owner/sessions
  def sessions(conn, _params) do
    club = conn.assigns.club

    render(conn, :sessions,
      archive: Sessions.archive(club),
      live: live_session(conn),
      page_title: "#{club.name} · sessions"
    )
  end

  # POST /c/:club_uuid/owner/sessions — name + optional date/time;
  # lands on the new session's owner surface
  def open_session(conn, params) do
    with {:ok, scheduled_at} <- Sessions.parse_schedule(params["date"], params["time"]),
         {:ok, session} <-
           Sessions.open(
             conn.assigns.current_user,
             conn.assigns.club,
             params["name"],
             scheduled_at
           ) do
      conn
      |> put_flash(:info, "session opened — sign-ups are live")
      |> redirect(to: ~p"/c/#{conn.assigns.club.uuid}/owner/s/#{session.uuid}")
    else
      {:error, message} ->
        conn
        |> put_flash(:error, error_message(message))
        |> redirect(to: ~p"/c/#{conn.assigns.club.uuid}/owner/sessions")
    end
  end

  # ---------------------------------------------------------------
  # Members page, owner path: roster + join requests (the form's
  # answers shown) + remove
  # ---------------------------------------------------------------

  # GET /c/:club_uuid/owner/members
  def members(conn, _params) do
    club = conn.assigns.club

    render(conn, :members,
      members: Clubs.list_members(club),
      join_requests: Clubs.list_join_requests(club),
      page_title: "#{club.name} · members"
    )
  end

  # POST /c/:club_uuid/owner/join-requests/:id/approve
  def approve(conn, %{"id" => id}) do
    with_join_request(conn, id, fn membership ->
      case Clubs.approve_join(membership) do
        {:ok, _} -> {:ok, "join request approved"}
        error -> error
      end
    end)
  end

  # POST /c/:club_uuid/owner/join-requests/:id/decline
  def decline(conn, %{"id" => id}) do
    with_join_request(conn, id, fn membership ->
      case Clubs.decline_join(membership) do
        {:ok, _} -> {:ok, "join request declined"}
        error -> error
      end
    end)
  end

  # POST /c/:club_uuid/owner/members/:user_id/remove
  def remove_member(conn, %{"user_id" => user_id}) do
    with {user_id, ""} <- Integer.parse(user_id),
         {:ok, _membership} <- Clubs.remove_member(conn.assigns.club, user_id) do
      back_members(conn, info: "member removed")
    else
      {:error, message} -> back_members(conn, error: error_message(message))
      _ -> conn |> send_resp(404, "not found") |> halt()
    end
  end

  # ---------------------------------------------------------------
  # The interim owner session surface (M8a): the M7 Registration +
  # Tonight + Rooms tab content on one page — same behavior, new
  # address. M8b re-behaves it.
  # ---------------------------------------------------------------

  # GET /c/:club_uuid/owner/s/:session_uuid
  def session(conn, %{"session_uuid" => session_uuid}) do
    club = conn.assigns.club

    with %Session{} = session <- Sessions.get_for_club(club, session_uuid),
         {:ok, state} <- Sessions.state(%{session | club: club}) do
      render(conn, :session,
        current: session,
        state: state,
        links: Links.list_for_session(session),
        members: Clubs.list_members(club),
        page_title: "#{club.name} · #{state.event["name"]}"
      )
    else
      nil ->
        conn |> send_resp(404, "not found") |> halt()

      {:error, message} ->
        conn
        |> put_flash(:error, error_message(message))
        |> redirect(to: ~p"/c/#{club.uuid}/owner/sessions")
    end
  end

  # POST .../owner/sessions/:session_uuid/close-signups
  def close_signups(conn, %{"session_uuid" => session_uuid}) do
    with_session(conn, session_uuid, fn session ->
      case Sessions.close_signups(session) do
        {:ok, _session} -> {:ok, "sign-ups closed — make or compose rooms when ready"}
        error -> error
      end
    end)
  end

  # POST .../owner/sessions/:session_uuid/reopen-signups
  def reopen_signups(conn, %{"session_uuid" => session_uuid}) do
    with_session(conn, session_uuid, fn session ->
      case Sessions.reopen_signups(session) do
        {:ok, _session} -> {:ok, "sign-ups reopened"}
        error -> error
      end
    end)
  end

  # POST .../owner/sessions/:session_uuid/signups — the head signs an
  # approved member up on their behalf
  def add_signup(conn, %{"session_uuid" => session_uuid} = params) do
    with_session(conn, session_uuid, fn session ->
      case Sessions.signup_for(
             conn.assigns.current_user,
             session,
             params["username"],
             params["as"]
           ) do
        {:ok, _participant} -> {:ok, "signed #{params["username"]} up to #{params["as"]}"}
        error -> error
      end
    end)
  end

  # POST .../owner/sessions/:session_uuid/links — the head issues a
  # guest link by hand; the personal URL lands in the flash
  def issue_link(conn, %{"session_uuid" => session_uuid} = params) do
    with_session(conn, session_uuid, fn session ->
      case Links.register_guest(session, params["name"], params["as"] || "") do
        {:ok, link} ->
          {:ok, "guest link for #{link.user.name}: #{url(~p"/l/#{link.code}")}"}

        error ->
          error
      end
    end)
  end

  # POST .../owner/links/:id/revoke — the personal URL stops working
  # immediately (any signup stays; remove it on the session surface)
  def revoke_link(conn, %{"id" => id}) do
    with {id, ""} <- Integer.parse(id),
         %Link{} = link <- Links.get_link(id),
         true <- link.club_id == conn.assigns.club.id,
         {:ok, link} <- Links.revoke(link) do
      conn
      |> put_flash(:info, "guest link revoked — it stops working immediately")
      |> redirect(to: ~p"/c/#{conn.assigns.club.uuid}/owner/s/#{link.session.uuid}")
    else
      {:error, message} ->
        conn
        |> put_flash(:error, error_message(message))
        |> redirect(to: ~p"/c/#{conn.assigns.club.uuid}/owner/sessions")

      _ ->
        conn |> send_resp(404, "not found") |> halt()
    end
  end

  # POST .../owner/sessions/:session_uuid/signups/:participant_id/remove
  def remove_signup(conn, %{"session_uuid" => session_uuid, "participant_id" => participant_id}) do
    with_session(conn, session_uuid, fn session ->
      case Integer.parse(participant_id) do
        {participant_id, ""} ->
          case Sessions.remove_signup(conn.assigns.current_user, session, participant_id) do
            :ok -> {:ok, "signup removed"}
            error -> error
          end

        _ ->
          {:error, "bad participant id"}
      end
    end)
  end

  # GET .../owner/sessions/:session_uuid/compose — the drag-and-drop
  # allocation page (the ONLY allocation UI). Rooms count derives
  # from attendance — floor(speakers/8) baseline — and "+ room"
  # reloads with ?rooms=N up to attendance/4.
  def compose(conn, %{"session_uuid" => session_uuid} = params) do
    club = conn.assigns.club

    with %Session{} = session <- Sessions.get_for_club(club, session_uuid),
         {:ok, state} <- Sessions.state(%{session | club: club}) do
      case state.stage do
        :closed ->
          speakers = Enum.count(state.signups, &(&1["role"] == "speaker"))
          max_rooms = max(div(speakers, 4), 1)
          rooms = params["rooms"] |> rooms_param(max(div(speakers, 8), 1)) |> clamp(max_rooms)

          render(conn, :compose,
            session: session,
            state: state,
            rooms: rooms,
            max_rooms: max_rooms,
            page_title: "#{club.name} · compose rooms"
          )

        _stage ->
          conn
          |> put_flash(
            :error,
            "close sign-ups first — rooms are composed from the final attendance"
          )
          |> redirect(to: ~p"/c/#{club.uuid}/owner/s/#{session.uuid}")
      end
    else
      nil ->
        conn |> send_resp(404, "not found") |> halt()

      {:error, message} ->
        conn
        |> put_flash(:error, error_message(message))
        |> redirect(to: ~p"/c/#{club.uuid}/owner/sessions")
    end
  end

  defp rooms_param(value, default) do
    case is_binary(value) && Integer.parse(value) do
      {rooms, ""} -> rooms
      _ -> default
    end
  end

  defp clamp(rooms, max_rooms), do: rooms |> max(1) |> min(max_rooms)

  # POST .../owner/sessions/:session_uuid/rooms — the gold one-click
  # auto path; with "rooms" params (the compose form) the head's
  # explicit composition is used instead
  def make_rooms(conn, %{"session_uuid" => session_uuid} = params) do
    with_session(conn, session_uuid, fn session ->
      result =
        case params["rooms"] do
          nil -> Sessions.make_rooms(conn.assigns.current_user, session)
          rooms -> Sessions.make_rooms(conn.assigns.current_user, session, compose_spec(rooms))
        end

      case result do
        {:ok, count} -> {:ok, "#{count} room(s) created"}
        error -> error
      end
    end)
  end

  # the dnd page posts rooms[i][og|oo|cg|co][1|2] + rooms[i][judge]
  # (empty slots post ""); the API takes the canonical
  # {"judge_participant_id", "teams"} shape directly. Rows left
  # entirely empty (an unused "+ room" row) are dropped.
  defp compose_spec(%{} = rooms) do
    rooms
    |> Enum.sort_by(fn {index, _room} ->
      case Integer.parse(index) do
        {i, ""} -> i
        _ -> 0
      end
    end)
    |> Enum.map(fn {_index, room} ->
      %{
        "judge_participant_id" => presence(room["judge"]),
        "teams" =>
          for side <- ~w(og oo cg co) do
            team = room[side] || %{}

            ~w(1 2)
            |> Enum.map(&presence(team[&1]))
            |> Enum.reject(&is_nil/1)
          end
      }
    end)
    |> Enum.reject(&empty_room?/1)
  end

  defp compose_spec(other), do: other

  defp empty_room?(%{"judge_participant_id" => nil, "teams" => teams}),
    do: Enum.all?(teams, &(&1 == []))

  defp empty_room?(_room), do: false

  defp presence(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp presence(value), do: value

  # POST .../owner/sessions/:session_uuid/rooms/delete — rebuild:
  # pending rooms go away so the head can recompose
  def delete_rooms(conn, %{"session_uuid" => session_uuid}) do
    with_session(conn, session_uuid, fn session ->
      case Sessions.delete_rooms(conn.assigns.current_user, session) do
        {:ok, count} -> {:ok, "#{count} room(s) deleted — compose or make rooms again"}
        error -> error
      end
    end)
  end

  # POST .../owner/sessions/:session_uuid/cancel
  def cancel_session(conn, %{"session_uuid" => session_uuid}) do
    case Sessions.get_for_club(conn.assigns.club, session_uuid) do
      %Session{} = session ->
        case Sessions.cancel(conn.assigns.current_user, session) do
          {:ok, _session} ->
            conn
            |> put_flash(:info, "session cancelled")
            |> redirect(to: ~p"/c/#{conn.assigns.club.uuid}/owner/sessions")

          {:error, message} ->
            conn
            |> put_flash(:error, error_message(message))
            |> redirect(to: ~p"/c/#{conn.assigns.club.uuid}/owner/s/#{session.uuid}")
        end

      nil ->
        conn |> send_resp(404, "not found") |> halt()
    end
  end

  # POST .../owner/sessions/:session_uuid/finish — results live on
  # the public session page
  def finish(conn, %{"session_uuid" => session_uuid}) do
    case Sessions.get_for_club(conn.assigns.club, session_uuid) do
      %Session{} = session ->
        case Sessions.finish(conn.assigns.current_user, session) do
          :ok ->
            conn
            |> put_flash(:info, "session finished")
            |> redirect(to: ~p"/c/#{conn.assigns.club.uuid}/s/#{session.uuid}")

          {:error, message} ->
            conn
            |> put_flash(:error, error_message(message))
            |> redirect(to: ~p"/c/#{conn.assigns.club.uuid}/owner/s/#{session.uuid}")
        end

      nil ->
        conn |> send_resp(404, "not found") |> halt()
    end
  end

  # ---------------------------------------------------------------

  defp with_join_request(conn, id, fun) do
    with {id, ""} <- Integer.parse(id),
         %Membership{} = membership <- Clubs.get_membership(id),
         true <- membership.club_id == conn.assigns.club.id do
      case fun.(membership) do
        {:ok, info} -> back_members(conn, info: info)
        {:error, message} -> back_members(conn, error: message)
      end
    else
      _ -> conn |> send_resp(404, "not found") |> halt()
    end
  end

  defp with_session(conn, session_uuid, fun) do
    case Sessions.get_for_club(conn.assigns.club, session_uuid) do
      %Session{} = session ->
        back = ~p"/c/#{conn.assigns.club.uuid}/owner/s/#{session.uuid}"

        case fun.(session) do
          {:ok, info} -> conn |> put_flash(:info, info) |> redirect(to: back)
          {:error, :conflict, message} -> flash_error(conn, back, message)
          {:error, message} -> flash_error(conn, back, message)
        end

      nil ->
        conn |> send_resp(404, "not found") |> halt()
    end
  end

  defp flash_error(conn, back, message) do
    conn
    |> put_flash(:error, error_message(message))
    |> redirect(to: back)
  end

  defp back_members(conn, info: info) do
    conn
    |> put_flash(:info, info)
    |> redirect(to: ~p"/c/#{conn.assigns.club.uuid}/owner/members")
  end

  defp back_members(conn, error: message) do
    conn
    |> put_flash(:error, error_message(message))
    |> redirect(to: ~p"/c/#{conn.assigns.club.uuid}/owner/members")
  end

  # the live-session fallback for room actions addressed by id only
  defp live_session(conn), do: conn.assigns[:nav_session]

  defp error_message(message) when is_binary(message), do: message
  defp error_message(%{rooms: message}), do: message
  defp error_message(%{name: message}), do: message
  defp error_message(other), do: inspect(other)
end
