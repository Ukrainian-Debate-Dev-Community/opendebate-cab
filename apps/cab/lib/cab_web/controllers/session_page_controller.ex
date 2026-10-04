defmodule CabWeb.SessionPageController do
  @moduledoc """
  P6 `/c/:club_uuid/s/:session_uuid` — THE session page: one page per
  session, public, stage-aware (signup -> who's registered; running ->
  the playing page with the draw; done -> results and winner).

  Its actions are identity-gated, not tree-gated: cancel removes only
  the viewer's OWN registration, the ballot opens only for the room's
  chair (or the head) — which is exactly how a guest (session identity
  adopted via `/l/:code`) registers out or judges through this page.
  """

  use CabWeb, :controller

  alias Cab.Accounts.User
  alias Cab.Sessions
  alias Cab.Sessions.Session
  alias CabWeb.BallotForm

  plug CabWeb.ClubScope, source: :club, require: :public

  # GET /c/:club_uuid/s/:session_uuid
  def show(conn, %{"session_uuid" => session_uuid}) do
    club = conn.assigns.club

    with %Session{} = session <- Sessions.get_for_club(club, session_uuid),
         {:ok, state} <- Sessions.state(%{session | club: club}) do
      user = conn.assigns.current_user
      my_signup = my_signup(state, user)

      render(conn, :show,
        session: session,
        state: state,
        winner: Sessions.winner_from_rooms(state.rooms),
        my_signup: my_signup,
        my_ballot_room: my_ballot_room(state, user),
        my_room_id: my_room_id(state, user, my_signup),
        page_title: "#{club.name} · #{state.event["name"]}"
      )
    else
      nil ->
        conn |> send_resp(404, "not found") |> halt()

      {:error, message} ->
        conn
        |> put_flash(:error, error_message(message))
        |> redirect(to: ~p"/c/#{club.uuid}")
    end
  end

  # POST .../signups/:participant_id/remove — the viewer cancels
  # their OWN registration (member or guest alike; the context
  # authorises owner-or-self)
  def cancel_signup(conn, %{"session_uuid" => session_uuid, "participant_id" => participant_id}) do
    club = conn.assigns.club
    back = fn session -> ~p"/c/#{club.uuid}/s/#{session.uuid}" end

    with %User{} = user <- conn.assigns.current_user,
         %Session{} = session <- Sessions.get_for_club(club, session_uuid),
         {pid, ""} <- Integer.parse(participant_id),
         :ok <- Sessions.remove_signup(user, %{session | club: club}, pid) do
      conn
      |> put_flash(:info, "registration cancelled")
      |> redirect(to: back.(session))
    else
      nil ->
        signin_or_404(conn, session_uuid)

      {:error, :forbidden} ->
        conn |> send_resp(403, "forbidden") |> halt()

      {:error, :conflict, message} ->
        bounce(conn, session_uuid, message)

      {:error, message} ->
        bounce(conn, session_uuid, error_message(message))

      _ ->
        conn |> send_resp(404, "not found") |> halt()
    end
  end

  # GET .../rooms/:id/ballot — the room judge's ballot (chair or head)
  def ballot(conn, %{"id" => id} = params) do
    with_chaired_room(conn, params["session_uuid"], id, fn conn, session, room ->
      render_ballot(conn, session, room, nil, nil)
    end)
  end

  # POST .../rooms/:id/ballot — redirect + flash, amber re-render
  def submit_ballot(conn, %{"id" => id} = params) do
    with_chaired_room(conn, params["session_uuid"], id, fn conn, session, room ->
      scores = BallotForm.scores_from_params(params["ballot"])

      case Sessions.submit_ballot(conn.assigns.current_user, session, room["id"], scores) do
        :ok ->
          conn
          |> put_flash(:info, "ballot submitted — the room is confirmed")
          |> redirect(to: ~p"/c/#{conn.assigns.club.uuid}/s/#{session.uuid}")

        {:error, :forbidden} ->
          conn |> send_resp(403, "forbidden") |> halt()

        {:error, %{scores: message}} ->
          conn
          |> put_status(422)
          |> render_ballot(session, room, params["ballot"], message)

        {:error, message} ->
          conn
          |> put_status(422)
          |> render_ballot(session, room, params["ballot"], error_message(message))
      end
    end)
  end

  defp render_ballot(conn, session, room, ballot_params, error) do
    render(conn, :ballot,
      session: session,
      room: room,
      teams: BallotForm.teams(room, ballot_params),
      error: error,
      page_title: "ballot · R#{room["id"]}"
    )
  end

  # Resolves the room INSIDE this session and gates it: only the
  # room's chair (member or guest) or the head sees a ballot page;
  # anonymous hits the auth wall (P1).
  defp with_chaired_room(conn, session_uuid, id, fun) do
    club = conn.assigns.club

    with {room_id, ""} <- Integer.parse(id || ""),
         %Session{} = session <- Sessions.get_for_club(club, session_uuid || ""),
         {:ok, state} <- Sessions.state(%{session | club: club}),
         %{} = room <- Enum.find(state.rooms, &(&1["id"] == room_id)) do
      user = conn.assigns.current_user

      cond do
        user == nil ->
          conn
          |> put_flash(:error, "Please sign in.")
          |> redirect(to: ~p"/signin")
          |> halt()

        Sessions.room_chair?(room, user) or conn.assigns.club_role == :owner ->
          fun.(conn, %{session | club: club}, room)

        true ->
          conn |> send_resp(403, "forbidden") |> halt()
      end
    else
      _ -> conn |> send_resp(404, "not found") |> halt()
    end
  end

  defp my_signup(%{signups: signups}, %User{node_user_id: node_user_id})
       when is_integer(node_user_id) do
    Enum.find(signups, &(&1["user_id"] == node_user_id))
  end

  defp my_signup(_state, _user), do: nil

  # the chrome's gold "Fill ballot" segment: the open room this
  # viewer chairs
  defp my_ballot_room(%{stage: :running, rooms: rooms}, %User{} = user) do
    Enum.find(rooms, fn room ->
      room["status"] in ["pending", "judging"] and Sessions.room_chair?(room, user)
    end)
  end

  defp my_ballot_room(_state, _user), do: nil

  # the draw row tint: the room carrying the viewer's participant
  # (speaker slot or chair)
  defp my_room_id(%{stage: :running, rooms: rooms}, user, my_signup) do
    my_pid = my_signup && my_signup["id"]

    Enum.find_value(rooms, fn room ->
      speaking =
        is_integer(my_pid) and
          Enum.any?(room["RoomTeams"] || [], fn room_team ->
            Enum.any?(
              room_team["RoomSpeakers"] || [],
              &(get_in(&1, ["EventParticipant", "id"]) == my_pid)
            )
          end)

      if speaking or (user && Sessions.room_chair?(room, user)), do: room["id"]
    end)
  end

  defp my_room_id(_state, _user, _my_signup), do: nil

  defp signin_or_404(conn, session_uuid) do
    case {conn.assigns.current_user, Sessions.get_for_club(conn.assigns.club, session_uuid)} do
      {nil, %Session{}} ->
        conn
        |> put_flash(:error, "Please sign in.")
        |> redirect(to: ~p"/signin")
        |> halt()

      _ ->
        conn |> send_resp(404, "not found") |> halt()
    end
  end

  defp bounce(conn, session_uuid, message) do
    conn
    |> put_flash(:error, message)
    |> redirect(to: ~p"/c/#{conn.assigns.club.uuid}/s/#{session_uuid}")
  end

  defp error_message(message) when is_binary(message), do: message
  defp error_message(_other), do: "the session is unavailable right now"
end
