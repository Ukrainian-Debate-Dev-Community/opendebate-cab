defmodule CabWeb.Api.SessionController do
  use CabWeb, :controller

  alias Cab.Sessions
  alias CabWeb.{ClubScope, SessionFormat}

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
      |> json(%{uuid: session.uuid, scheduled_at: session.scheduled_at})
    end
  end

  # GET /api/v1/sessions/:uuid - the session as anyone may read it: names,
  # stage, rooms, motions and results, no engine ids or accounts. The
  # club head also gets every room's and person's `id` (their API calls
  # address rooms and people by it); a room's chair gets them for the
  # room they chair, which the ballot call needs; everyone gets the id
  # of their own registration, to leave it.
  def show(conn, _params) do
    %{session: session, club: club, current_user: user} = conn.assigns

    with {:ok, state} <- Sessions.state(session) do
      head? = Cab.Clubs.covers?(conn.assigns.club_role, :owner)
      ids? = fn room -> head? or (user != nil and Sessions.room_chair?(room, user)) end

      json(conn, %{
        uuid: session.uuid,
        club_uuid: club.uuid,
        name: state.event["name"],
        stage: state.stage,
        scheduled_at: session.scheduled_at,
        signups_closed_at: session.signups_closed_at,
        short_link: Sessions.short_url(session),
        signups: Enum.map(state.signups, &public_signup(&1, head?, user)),
        rooms: Enum.map(state.rooms, &public_room(&1, state.signups, ids?.(&1))),
        winner: Sessions.winner_from_rooms(state.rooms),
        winners:
          Enum.map(
            Sessions.winners_by_room(state.rooms),
            fn {room, name} -> %{room: "R#{room["no"]}", team: name} end
          )
      })
    end
  end

  # the head sees every id; anyone else only their own (to leave)
  defp public_signup(participant, head?, user) do
    own? = user != nil and Sessions.own_participant?(participant, user)

    %{name: participant["display_name"], role: participant["role"]}
    |> with_id(participant["id"], head? or own?)
  end

  defp public_room(room, signups, ids?) do
    motion = room["Motion"]

    %{
      no: room["no"],
      status: room["status"],
      motion:
        motion &&
          %{
            text: motion["motion_text"],
            infoslide: motion["infoslide"],
            keyword: motion["keyword"],
            prep_until: room["prep_until"]
          },
      adjudicator: SessionFormat.judge_name(room, signups),
      teams:
        for room_team <- SessionFormat.sorted_teams(room) do
          %{
            side: Enum.at(~w(OG OO CG CO), (room_team["position"] || 1) - 1),
            name: get_in(room_team, ["Team", "name"]),
            rank: room_team["rank"],
            points: SessionFormat.team_points(room_team),
            speakers: public_speakers(room_team, ids?)
          }
        end
    }
    |> with_id(room["id"], ids?)
  end

  # a speaker per speech, in speaking order; ids for those who act on it
  defp public_speakers(room_team, ids?) do
    slots = Enum.sort_by(room_team["RoomSpeakers"] || [], &{&1["rank"] || 0, &1["id"] || 0})

    room_team
    |> SessionFormat.speeches()
    |> Enum.zip(slots)
    |> Enum.map(fn {speech, slot} ->
      %{name: speech.name, score: speech.points, iron: speech.iron}
      |> with_id(get_in(slot, ["EventParticipant", "id"]), ids?)
    end)
  end

  defp with_id(map, id, true), do: Map.put(map, :id, id)
  defp with_id(map, _id, _ids?), do: map

  # POST /api/v1/sessions/:uuid/start {"rooms": [...]} - M9's one
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
      details: %{rooms: "the allocator spec is required; nothing is allocated automatically"}
    })
  end

  # POST /api/v1/sessions/:uuid/reopen-registration - pending rooms
  # die, the public window opens again
  def reopen_registration(conn, _params) do
    with {:ok, session} <-
           Sessions.reopen_registration(conn.assigns.current_user, conn.assigns.session) do
      json(conn, %{uuid: session.uuid, stage: :signup})
    end
  end

  # POST /api/v1/sessions/:uuid/close-signups - flow-2's explicit
  # "sign-ups close" edge; 409 unless the session is :signup
  def close_signups(conn, _params) do
    with {:ok, session} <- Sessions.close_signups(conn.assigns.session) do
      json(conn, %{uuid: session.uuid, stage: :closed})
    end
  end

  # POST /api/v1/sessions/:uuid/reopen-signups - 409 unless :closed
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

  # DELETE /api/v1/sessions/:uuid - head cancels: engine event
  # archived, gateway row removed, club back to "no session"
  def delete(conn, _params) do
    with {:ok, _session} <- Sessions.cancel(conn.assigns.current_user, conn.assigns.session) do
      json(conn, %{uuid: conn.assigns.session.uuid, status: "cancelled"})
    end
  end
end
