defmodule CabWeb.Api.RoomController do
  use CabWeb, :controller

  alias Cab.Sessions
  alias CabWeb.ClubScope

  action_fallback CabWeb.Api.FallbackController

  plug ClubScope, [source: :session, require: :owner] when action == :create
  # room routes carry no club in the URL (engine room ids), so the
  # club is resolved from the required "session_uuid" body field; the
  # engine additionally enforces chair rights on its side
  plug ClubScope, [source: :room_session, require: :member] when action in [:motion, :winner]

  # POST /api/v1/sessions/:uuid/rooms — attendance pairing
  def create(conn, _params) do
    with {:ok, count} <- Sessions.make_rooms(conn.assigns.current_user, conn.assigns.session) do
      conn |> put_status(201) |> json(%{rooms_created: count})
    end
  end

  # POST /api/v1/rooms/:id/motion {"session_uuid", "motion_text"}
  def motion(conn, %{"id" => id, "motion_text" => motion_text}) do
    with {:ok, room_id} <- room_id(id),
         {:ok, data} <-
           Sessions.set_room_motion(conn.assigns.current_user, room_id, motion_text) do
      json(conn, %{room_id: room_id, motion: data["motion"]})
    end
  end

  def motion(_conn, _params), do: {:error, "motion_text is required"}

  # POST /api/v1/rooms/:id/winner {"session_uuid", "room_team_id"}
  def winner(conn, %{"id" => id, "room_team_id" => room_team_id})
      when is_integer(room_team_id) do
    with {:ok, room_id} <- room_id(id),
         :ok <-
           Sessions.pick_winner(
             conn.assigns.current_user,
             conn.assigns.session,
             room_id,
             room_team_id
           ) do
      json(conn, %{room_id: room_id, status: "confirmed"})
    end
  end

  def winner(_conn, _params), do: {:error, "room_team_id (integer) is required"}

  defp room_id(id) do
    case Integer.parse(id) do
      {room_id, ""} -> {:ok, room_id}
      _ -> {:error, "bad room id"}
    end
  end
end
