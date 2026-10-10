defmodule CabWeb.FeedbackController do
  @moduledoc """
  A team's feedback on its room's adjudicator
  (`/c/:club/s/:session/rooms/:id/feedback`): the form for a member of
  one of the room's teams, or what the team already sent. Everything is
  kept in the engine (`Cab.Feedback`).
  """

  use CabWeb, :controller

  alias Cab.{Feedback, Sessions}
  alias Cab.Sessions.Session

  plug CabWeb.ClubScope, source: :club, require: :public

  # GET .../rooms/:id/feedback
  def new(conn, %{"session_uuid" => session_uuid, "id" => id}) do
    with_team_room(conn, session_uuid, id, fn conn, session, state, room, room_team ->
      render_form(conn, session, state, room, room_team, %{}, %{})
    end)
  end

  # POST .../rooms/:id/feedback {"accuracy", "reasoning", "discussion"}
  def create(conn, %{"session_uuid" => session_uuid, "id" => id} = params) do
    with_team_room(conn, session_uuid, id, fn conn, session, state, room, room_team ->
      attrs = Map.take(params, ["accuracy", "reasoning", "discussion"])
      back = ~p"/c/#{conn.assigns.club.uuid}/s/#{session.uuid}/rooms/#{room["id"]}/feedback"

      case Feedback.submit(conn.assigns.current_user, session, room["id"], attrs) do
        :ok ->
          conn |> put_flash(:info, gettext("Feedback sent.")) |> redirect(to: back)

        {:error, :forbidden} ->
          CabWeb.ErrorHTML.respond(conn, 403)

        {:error, %{} = errors} ->
          conn
          |> put_status(422)
          |> render_form(session, state, room, room_team, attrs, field_errors(errors))

        {:error, :conflict, message} ->
          conn |> put_flash(:error, message) |> redirect(to: back)

        {:error, message} ->
          conn |> put_flash(:error, message) |> redirect(to: back)
      end
    end)
  end

  defp render_form(conn, session, state, room, room_team, values, errors) do
    # nothing can be sent before the ballot, so only then ask the engine
    sent =
      if room["status"] in ["completed", "confirmed"],
        do: Feedback.sent_by(Feedback.all(session), room, room_team)

    render(conn, :new,
      session: session,
      room: room,
      room_team: room_team,
      adjudicator: CabWeb.SessionFormat.judge_name(room, state.signups),
      open: Feedback.open?(session, room),
      sent: sent,
      values: values,
      errors: errors,
      page_title: gettext("Feedback — %{room}", room: CabWeb.SessionFormat.room_label(room))
    )
  end

  defp field_errors(errors) do
    for {key, message} <- errors, key in ~w(accuracy reasoning discussion), into: %{} do
      {String.to_existing_atom(key), message}
    end
  end

  # the room inside this session, for a member of one of its teams;
  # anyone else is turned away
  defp with_team_room(conn, session_uuid, id, fun) do
    club = conn.assigns.club
    user = conn.assigns.current_user

    with {room_id, ""} <- Integer.parse(id || ""),
         %Session{} = session <- Sessions.get_for_club(club, session_uuid || ""),
         session = %{session | club: club},
         {:ok, state} <- Sessions.state(session),
         %{} = room <- Enum.find(state.rooms, &(&1["id"] == room_id)) do
      cond do
        user == nil ->
          conn
          |> put_flash(:error, gettext("Please sign in."))
          |> redirect(to: ~p"/signin")

        room_team = Feedback.my_room_team(state, room, user) ->
          fun.(conn, session, state, room, room_team)

        true ->
          CabWeb.ErrorHTML.respond(conn, 403)
      end
    else
      _ -> CabWeb.ErrorHTML.respond(conn, 404)
    end
  end
end
