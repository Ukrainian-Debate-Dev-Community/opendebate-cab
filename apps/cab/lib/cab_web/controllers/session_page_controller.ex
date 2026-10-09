defmodule CabWeb.SessionPageController do
  @moduledoc """
  The session page's REST actions (the page itself is
  `CabWeb.SessionLive`): cancel a registration, the room page, the
  motion and the ballot.

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
      |> put_flash(:info, "Registration cancelled.")
      |> redirect(to: back.(session))
    else
      nil ->
        signin_or_404(conn, session_uuid)

      {:error, :forbidden} ->
        conn |> CabWeb.ErrorHTML.respond(403)

      {:error, :conflict, message} ->
        bounce(conn, session_uuid, message)

      {:error, message} ->
        bounce(conn, session_uuid, error_message(message))

      _ ->
        conn |> CabWeb.ErrorHTML.respond(404)
    end
  end

  # POST .../rooms/:id/motion — chair or head sets this room's motion
  def motion(conn, %{"session_uuid" => session_uuid, "id" => id} = params) do
    with_chaired_room(conn, session_uuid, id, fn conn, session, room ->
      attrs =
        %{infoslide: presence(params["infoslide"]), keyword: presence(params["keyword"])}
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Map.new()

      case Sessions.set_room_motion(
             conn.assigns.current_user,
             session,
             room["id"],
             params["motion_text"],
             attrs
           ) do
        {:ok, _} ->
          conn
          |> put_flash(:info, "Motion published.")
          |> redirect(to: ~p"/c/#{conn.assigns.club.uuid}/s/#{session.uuid}/rooms/#{room["id"]}")

        {:error, message} ->
          conn
          |> put_flash(:error, error_message(message))
          |> redirect(to: ~p"/c/#{conn.assigns.club.uuid}/s/#{session.uuid}/rooms/#{room["id"]}")
      end
    end)
  end

  # GET .../rooms/:id/ballot — the room judge's ballot (chair or head)
  def ballot(conn, %{"id" => id} = params) do
    with_chaired_room(conn, params["session_uuid"], id, fn conn, session, room ->
      if Sessions.motion?(room),
        do: render_ballot(conn, session, room, nil, nil),
        else: motion_first(conn, session, room)
    end)
  end

  # no motion, no ballot: back to the room, where the motion is set
  defp motion_first(conn, session, room) do
    conn
    |> put_flash(:error, "Publish the room's motion first.")
    |> redirect(to: ~p"/c/#{conn.assigns.club.uuid}/s/#{session.uuid}/rooms/#{room["id"]}")
  end

  # POST .../rooms/:id/ballot — redirect + flash, amber re-render
  def submit_ballot(conn, %{"id" => id} = params) do
    with_chaired_room(conn, params["session_uuid"], id, fn conn, session, room ->
      scores = BallotForm.scores_from_params(params["ballot"])

      case Sessions.submit_ballot(conn.assigns.current_user, session, room["id"], scores) do
        :ok ->
          conn
          |> put_flash(:info, "Ballot submitted.")
          |> redirect(to: ~p"/c/#{conn.assigns.club.uuid}/s/#{session.uuid}")

        {:error, :forbidden} ->
          conn |> CabWeb.ErrorHTML.respond(403)

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
      page_title: "Ballot — #{CabWeb.SessionFormat.room_label(room)}"
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

        Sessions.room_chair?(room, user) or Cab.Clubs.covers?(conn.assigns.club_role, :owner) ->
          fun.(conn, %{session | club: club}, room)

        true ->
          conn |> CabWeb.ErrorHTML.respond(403)
      end
    else
      _ -> conn |> CabWeb.ErrorHTML.respond(404)
    end
  end

  defp signin_or_404(conn, session_uuid) do
    case {conn.assigns.current_user, Sessions.get_for_club(conn.assigns.club, session_uuid)} do
      {nil, %Session{}} ->
        conn
        |> put_flash(:error, "Please sign in.")
        |> redirect(to: ~p"/signin")
        |> halt()

      _ ->
        conn |> CabWeb.ErrorHTML.respond(404)
    end
  end

  defp bounce(conn, session_uuid, message) do
    conn
    |> put_flash(:error, message)
    |> redirect(to: ~p"/c/#{conn.assigns.club.uuid}/s/#{session_uuid}")
  end

  defp presence(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp presence(_value), do: nil

  defp error_message(message) when is_binary(message), do: message
  defp error_message(_other), do: "This session is unavailable right now."
end
