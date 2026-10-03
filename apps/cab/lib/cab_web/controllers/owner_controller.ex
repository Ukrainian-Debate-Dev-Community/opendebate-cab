defmodule CabWeb.OwnerController do
  use CabWeb, :controller

  alias Cab.{Clubs, Sessions}
  alias Cab.Clubs.Membership
  alias Cab.Sessions.Session

  plug CabWeb.ClubScope, source: :club, require: :owner

  # GET /c/:club_uuid/owner — approvals, open session, session controls
  def show(conn, _params) do
    club = conn.assigns.club
    sessions = Sessions.list_for_club(club)
    current = List.first(sessions)

    state =
      with %Session{} <- current,
           {:ok, state} <- Sessions.state(%{current | club: club}) do
        state
      else
        _ -> nil
      end

    render(conn, :show,
      join_requests: Clubs.list_join_requests(club),
      members: Clubs.list_members(club),
      sessions: sessions,
      current: current,
      state: state,
      page_title: "#{club.name} · owner"
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

  # POST /c/:club_uuid/owner/sessions
  def open_session(conn, params) do
    case Sessions.open(conn.assigns.current_user, conn.assigns.club, params["name"]) do
      {:ok, _session} -> back(conn, info: "session opened")
      {:error, message} -> back(conn, error: message)
    end
  end

  # POST /c/:club_uuid/owner/sessions/:session_uuid/rooms
  def make_rooms(conn, %{"session_uuid" => session_uuid}) do
    with_session(conn, session_uuid, fn session ->
      case Sessions.make_rooms(conn.assigns.current_user, session) do
        {:ok, count} -> {:ok, "#{count} room(s) created"}
        error -> error
      end
    end)
  end

  # POST /c/:club_uuid/owner/sessions/:session_uuid/finish
  def finish(conn, %{"session_uuid" => session_uuid}) do
    with_session(conn, session_uuid, fn session ->
      case Sessions.finish(conn.assigns.current_user, session) do
        :ok -> {:ok, "session finished"}
        error -> error
      end
    end)
  end

  # POST /c/:club_uuid/owner/rooms/:id/motion
  def motion(conn, %{"id" => id, "motion_text" => motion_text}) do
    with {room_id, ""} <- Integer.parse(id),
         {:ok, _} <- Sessions.set_room_motion(conn.assigns.current_user, room_id, motion_text) do
      back(conn, info: "motion set")
    else
      {:error, message} -> back(conn, error: message)
      _ -> back(conn, error: "bad room id")
    end
  end

  # POST /c/:club_uuid/owner/rooms/:id/winner
  def winner(conn, %{"id" => id, "session_uuid" => session_uuid} = params) do
    with_session(conn, session_uuid, fn session ->
      with {room_id, ""} <- Integer.parse(id),
           {room_team_id, ""} <- Integer.parse(params["room_team_id"] || ""),
           :ok <-
             Sessions.pick_winner(conn.assigns.current_user, session, room_id, room_team_id) do
        {:ok, "winner recorded"}
      else
        {:error, message} -> {:error, message}
        _ -> {:error, "pick a team"}
      end
    end)
  end

  # ---------------------------------------------------------------

  defp with_join_request(conn, id, fun) do
    with {id, ""} <- Integer.parse(id),
         %Membership{} = membership <- Clubs.get_membership(id),
         true <- membership.club_id == conn.assigns.club.id do
      case fun.(membership) do
        {:ok, info} -> back(conn, info: info)
        {:error, message} -> back(conn, error: message)
      end
    else
      _ -> conn |> send_resp(404, "not found") |> halt()
    end
  end

  defp with_session(conn, session_uuid, fun) do
    case Sessions.get_for_club(conn.assigns.club, session_uuid) do
      %Session{} = session ->
        case fun.(session) do
          {:ok, info} -> back(conn, info: info)
          {:error, message} -> back(conn, error: error_message(message))
        end

      nil ->
        conn |> send_resp(404, "not found") |> halt()
    end
  end

  defp back(conn, info: info) do
    conn
    |> put_flash(:info, info)
    |> redirect(to: ~p"/c/#{conn.assigns.club.uuid}/owner")
  end

  defp back(conn, error: message) do
    conn
    |> put_flash(:error, error_message(message))
    |> redirect(to: ~p"/c/#{conn.assigns.club.uuid}/owner")
  end

  defp error_message(message) when is_binary(message), do: message
  defp error_message(other), do: inspect(other)
end
