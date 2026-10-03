defmodule CabWeb.Api.SessionController do
  use CabWeb, :controller

  alias Cab.Sessions
  alias CabWeb.ClubScope

  action_fallback CabWeb.Api.FallbackController

  plug ClubScope, [source: :club, require: :owner] when action == :create
  plug ClubScope, [source: :session, require: :member] when action == :show
  plug ClubScope, [source: :session, require: :owner] when action == :finish

  # POST /api/v1/clubs/:uuid/sessions {"name": optional}
  def create(conn, params) do
    with {:ok, session} <-
           Sessions.open(conn.assigns.current_user, conn.assigns.club, params["name"]) do
      conn
      |> put_status(201)
      |> json(%{uuid: session.uuid, engine_event_id: session.engine_event_id})
    end
  end

  # GET /api/v1/sessions/:uuid — stage derived from engine state
  def show(conn, _params) do
    session = conn.assigns.session

    with {:ok, state} <- Sessions.state(session) do
      json(conn, %{
        uuid: session.uuid,
        club_uuid: conn.assigns.club.uuid,
        stage: state.stage,
        event: state.event,
        round: state.round,
        signups: state.signups,
        rooms: state.rooms
      })
    end
  end

  # POST /api/v1/sessions/:uuid/finish
  def finish(conn, _params) do
    with :ok <- Sessions.finish(conn.assigns.current_user, conn.assigns.session) do
      json(conn, %{uuid: conn.assigns.session.uuid, status: "completed"})
    end
  end
end
