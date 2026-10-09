defmodule CabWeb.Api.SessionController do
  use CabWeb, :controller

  alias Cab.Sessions
  alias CabWeb.ClubScope

  action_fallback CabWeb.Api.FallbackController

  plug ClubScope, [source: :club, require: :owner] when action == :create
  plug ClubScope, [source: :session, require: :public] when action == :show

  plug ClubScope,
       [source: :session, require: :owner]
       when action in [
              :finish,
              :delete,
              :close_signups,
              :reopen_signups,
              :start,
              :reopen_registration
            ]

  # POST /api/v1/clubs/:uuid/sessions
  # {"name": optional, "date": "YYYY-MM-DD" optional, "time": "HH:MM" optional}
  def create(conn, params) do
    with {:ok, scheduled_at} <- Sessions.parse_schedule(params["date"], params["time"]),
         {:ok, session} <-
           Sessions.open(
             conn.assigns.current_user,
             conn.assigns.club,
             params["name"],
             scheduled_at
           ) do
      conn
      |> put_status(201)
      |> json(%{
        uuid: session.uuid,
        engine_event_id: session.engine_event_id,
        scheduled_at: session.scheduled_at
      })
    end
  end

  # GET /api/v1/sessions/:uuid — the public session detail twin:
  # stage derived from engine state + the gateway registration window
  # and, once ballots are in, the winner
  def show(conn, _params) do
    session = conn.assigns.session

    with {:ok, state} <- Sessions.state(session) do
      json(conn, %{
        uuid: session.uuid,
        club_uuid: conn.assigns.club.uuid,
        stage: state.stage,
        scheduled_at: session.scheduled_at,
        signups_closed_at: session.signups_closed_at,
        event: state.event,
        round: state.round,
        signups: state.signups,
        rooms: state.rooms,
        winner: Sessions.winner_from_rooms(state.rooms),
        winners:
          Enum.map(
            Sessions.winners_by_room(state.rooms),
            fn {room, name} -> %{room: CabWeb.SessionFormat.room_label(room), team: name} end
          )
      })
    end
  end

  # POST /api/v1/sessions/:uuid/start {"rooms": [...]} — M9's one
  # action: closes registration and creates the rooms from the
  # allocator state (the spec is REQUIRED; nothing is auto-placed)
  def start(conn, %{"rooms" => rooms_spec}) when is_list(rooms_spec) do
    with {:ok, count} <-
           Sessions.start(conn.assigns.current_user, conn.assigns.session, rooms_spec) do
      json(conn, %{uuid: conn.assigns.session.uuid, stage: :running, rooms_created: count})
    end
  end

  def start(conn, _params) do
    conn
    |> put_status(422)
    |> json(%{
      error: "validation failed",
      details: %{rooms: "the allocator spec is required — nothing is allocated automatically"}
    })
  end

  # POST /api/v1/sessions/:uuid/reopen-registration — pending rooms
  # die, the public window opens again
  def reopen_registration(conn, _params) do
    with {:ok, session} <-
           Sessions.reopen_registration(conn.assigns.current_user, conn.assigns.session) do
      json(conn, %{uuid: session.uuid, stage: :signup})
    end
  end

  # POST /api/v1/sessions/:uuid/close-signups — flow-2's explicit
  # "sign-ups close" edge; 409 unless the session is :signup
  def close_signups(conn, _params) do
    with {:ok, session} <- Sessions.close_signups(conn.assigns.session) do
      json(conn, %{uuid: session.uuid, stage: :closed})
    end
  end

  # POST /api/v1/sessions/:uuid/reopen-signups — 409 unless :closed
  def reopen_signups(conn, _params) do
    with {:ok, session} <- Sessions.reopen_signups(conn.assigns.session) do
      json(conn, %{uuid: session.uuid, stage: :signup})
    end
  end

  # POST /api/v1/sessions/:uuid/finish
  def finish(conn, _params) do
    with :ok <- Sessions.finish(conn.assigns.current_user, conn.assigns.session) do
      json(conn, %{uuid: conn.assigns.session.uuid, status: "completed"})
    end
  end

  # DELETE /api/v1/sessions/:uuid — head cancels: engine event
  # archived, gateway row removed, club back to "no session"
  def delete(conn, _params) do
    with {:ok, _session} <- Sessions.cancel(conn.assigns.current_user, conn.assigns.session) do
      json(conn, %{uuid: conn.assigns.session.uuid, status: "cancelled"})
    end
  end
end
