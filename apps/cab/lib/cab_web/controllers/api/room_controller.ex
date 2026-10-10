defmodule CabWeb.Api.RoomController do
  use CabWeb, :controller

  alias Cab.Sessions
  alias CabWeb.ClubScope

  action_fallback CabWeb.Api.FallbackController

  plug ClubScope, [source: :session, require: :owner] when action in [:create, :delete]
  # room routes carry no club in the URL (engine room ids), so the
  # club is resolved from the required "session_uuid" body field; the
  # engine additionally enforces chair rights on its side
  plug ClubScope, [source: :room_session, require: :member] when action in [:motion, :ballot]

  # POST /api/v1/sessions/:uuid/rooms {"rooms": [{"adjudicator_participant_id",
  # "teams": [[pid,pid] x4]}]} — the head's composition; the spec is
  # REQUIRED, cab never pairs anyone automatically
  def create(conn, %{"rooms" => rooms_spec}) do
    with {:ok, count} <-
           Sessions.make_rooms(conn.assigns.current_user, conn.assigns.session, rooms_spec) do
      conn |> put_status(201) |> json(%{rooms_created: count})
    end
  end

  def create(_conn, _params),
    do: {:error, %{rooms: "the rooms spec is required — nothing is allocated automatically"}}

  # DELETE /api/v1/sessions/:uuid/rooms — rebuild: pending rooms (and
  # their temporary teams) go away so the head can recompose
  def delete(conn, _params) do
    with {:ok, count} <- Sessions.delete_rooms(conn.assigns.current_user, conn.assigns.session) do
      json(conn, %{rooms_deleted: count})
    end
  end

  # POST /api/v1/rooms/:id/motion {"session_uuid", "motion_text"}
  def motion(conn, %{"id" => id, "motion_text" => motion_text} = params) do
    attrs = Map.take(params, ["infoslide", "keyword"])

    with {:ok, room_id} <- room_id(id),
         {:ok, _data} <-
           Sessions.set_room_motion(
             conn.assigns.current_user,
             conn.assigns.session,
             room_id,
             motion_text,
             attrs
           ) do
      # publishing through the API starts prep like the room page does
      Sessions.set_prep_until(
        conn.assigns.session,
        room_id,
        DateTime.add(DateTime.utc_now(), 15, :minute)
      )

      json(conn, %{
        room_id: room_id,
        motion: %{text: motion_text, infoslide: attrs["infoslide"], keyword: attrs["keyword"]}
      })
    end
  end

  def motion(_conn, _params), do: {:error, "motion_text is required"}

  # POST /api/v1/rooms/:id/ballot {"session_uuid", "scores": [8 x
  # {"position", "speaker_participant_id", "iron", "score"}]} — ranks
  # derive from team totals, winner = rank 1, room ends confirmed
  def ballot(conn, %{"id" => id, "scores" => scores}) when is_list(scores) do
    with {:ok, room_id} <- room_id(id),
         :ok <-
           Sessions.submit_ballot(
             conn.assigns.current_user,
             conn.assigns.session,
             room_id,
             scores
           ) do
      json(conn, %{room_id: room_id, status: "confirmed"})
    end
  end

  def ballot(_conn, _params), do: {:error, "scores (a list of 8 entries) is required"}

  defp room_id(id) do
    case Integer.parse(id) do
      {room_id, ""} -> {:ok, room_id}
      _ -> {:error, "bad room id"}
    end
  end
end
