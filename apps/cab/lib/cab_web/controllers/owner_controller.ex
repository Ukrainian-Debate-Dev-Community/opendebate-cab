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

  # GET /c/:club_uuid/owner — the club page as an edit-in-place form,
  # with the session archive and the open-session form below (v3.1:
  # there is no separate owner Sessions page)
  def club(conn, _params) do
    club = conn.assigns.club

    render(conn, :club,
      archive: Sessions.club_sessions(club),
      live: Sessions.current_for_club(club),
      page_title: "#{club.name} — edit"
    )
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
  # Opening a session (the form lives on /owner)
  # ---------------------------------------------------------------

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
        |> redirect(to: ~p"/c/#{conn.assigns.club.uuid}/owner")
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
      page_title: "#{club.name} — members"
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
      _ -> conn |> CabWeb.ErrorHTML.respond(404)
    end
  end

  # ---------------------------------------------------------------
  # The owner session page and its lifecycle actions
  # ---------------------------------------------------------------

  # POST .../owner/sessions/:session_uuid/start — the gold action:
  # closes registration and creates the rooms from the dragged
  # allocator state (only the room count was automatic)
  def start(conn, %{"session_uuid" => session_uuid} = params) do
    with_session(conn, session_uuid, fn session ->
      case params["rooms"] do
        %{} = rooms ->
          case Sessions.start(conn.assigns.current_user, session, compose_spec(rooms)) do
            {:ok, count} -> {:ok, "session started — #{count} room(s)"}
            error -> error
          end

        _missing ->
          {:error, "drag people into the rooms first — nothing is allocated automatically"}
      end
    end)
  end

  # POST .../owner/sessions/:session_uuid/reopen-registration — from a
  # running session with all rooms still pending: rooms die, the
  # public window opens again
  def reopen_registration(conn, %{"session_uuid" => session_uuid}) do
    with_session(conn, session_uuid, fn session ->
      case Sessions.reopen_registration(conn.assigns.current_user, session) do
        {:ok, _session} -> {:ok, "registration reopened — pending rooms cleared"}
        error -> error
      end
    end)
  end

  # POST .../owner/sessions/:session_uuid/close-signups
  def close_signups(conn, %{"session_uuid" => session_uuid}) do
    with_session(conn, session_uuid, fn session ->
      case Sessions.close_signups(session) do
        {:ok, _session} -> {:ok, "sign-ups closed — drag people into the rooms when ready"}
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
             params["username"]
           ) do
        {:ok, _participant} -> {:ok, "signed #{params["username"]} up"}
        error -> error
      end
    end)
  end

  # POST .../owner/sessions/:session_uuid/links — the head issues a
  # guest link by hand; the personal URL lands in the flash
  def issue_link(conn, %{"session_uuid" => session_uuid} = params) do
    with_session(conn, session_uuid, fn session ->
      case Links.register_guest(session, params["name"]) do
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
        |> redirect(to: ~p"/c/#{conn.assigns.club.uuid}/owner")

      _ ->
        conn |> CabWeb.ErrorHTML.respond(404)
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

  # POST .../owner/sessions/:session_uuid/rooms — the allocator form
  # at :closed; the head's explicit composition, never auto-paired
  def make_rooms(conn, %{"session_uuid" => session_uuid} = params) do
    with_session(conn, session_uuid, fn session ->
      case params["rooms"] do
        %{} = rooms ->
          case Sessions.make_rooms(conn.assigns.current_user, session, compose_spec(rooms)) do
            {:ok, count} -> {:ok, "#{count} room(s) created"}
            error -> error
          end

        _missing ->
          {:error, "drag people into the rooms first — nothing is allocated automatically"}
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
        {:ok, count} -> {:ok, "#{count} room(s) deleted — allocate the rooms again"}
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
            |> redirect(to: ~p"/c/#{conn.assigns.club.uuid}/owner")

          {:error, message} ->
            conn
            |> put_flash(:error, error_message(message))
            |> redirect(to: ~p"/c/#{conn.assigns.club.uuid}/owner/s/#{session.uuid}")
        end

      nil ->
        conn |> CabWeb.ErrorHTML.respond(404)
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
        conn |> CabWeb.ErrorHTML.respond(404)
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
      _ -> conn |> CabWeb.ErrorHTML.respond(404)
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
        conn |> CabWeb.ErrorHTML.respond(404)
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

  defp error_message(message) when is_binary(message), do: message
  defp error_message(%{rooms: message}), do: message
  defp error_message(%{name: message}), do: message
  defp error_message(other), do: inspect(other)
end
