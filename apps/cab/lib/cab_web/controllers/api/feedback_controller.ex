defmodule CabWeb.Api.FeedbackController do
  @moduledoc """
  The feedback twins of the session pages. Sending is for a member of
  one of the room's teams; reading returns only what the caller may
  see: the club head everything with the team and the progress, a team
  its own feedback, an adjudicator theirs (once the session is finished
  and without the team).
  """

  use CabWeb, :controller

  alias Cab.{Clubs, Feedback, Sessions}
  alias CabWeb.ClubScope

  action_fallback CabWeb.Api.FallbackController

  plug ClubScope, [source: :room_session, require: :authenticated] when action == :create
  plug ClubScope, [source: :session, require: :authenticated] when action == :index

  # POST /api/cab/v1/rooms/:id/feedback {"session_uuid", "accuracy",
  # "reasoning", "discussion"}
  def create(conn, %{"id" => id} = params) do
    attrs = Map.take(params, ["accuracy", "reasoning", "discussion"])

    with {room_id, ""} <- Integer.parse(to_string(id)),
         :ok <-
           Feedback.submit(conn.assigns.current_user, conn.assigns.session, room_id, attrs) do
      conn |> put_status(201) |> json(%{room_id: room_id, status: "sent"})
    else
      :error -> {:error, gettext("That room is not part of this session.")}
      error -> error
    end
  end

  # GET /api/cab/v1/sessions/:uuid/feedback
  def index(conn, _params) do
    %{session: session, club: club, current_user: user} = conn.assigns
    session = %{session | club: club}

    with {:ok, state} <- Sessions.state(session) do
      if Clubs.covers?(conn.assigns.club_role, :owner) do
        feedback = Feedback.all(session)

        json(conn, %{
          feedback: Enum.map(feedback, &public_entry(&1, state, true)),
          progress:
            Enum.map(Feedback.progress(state, feedback), fn {room_id, {sent, teams}} ->
              %{room: room_no(state, room_id), sent: sent, teams: teams}
            end)
        })
      else
        own =
          for room <- state.rooms,
              entry = Feedback.own_for_room(session, state, room, user),
              entry != nil,
              do: public_entry(entry, state, true)

        on_me =
          Enum.map(Feedback.on_adjudicator(session, state, user), &public_entry(&1, state, false))

        json(conn, %{
          feedback: own,
          on_your_adjudication: on_me,
          your_average: on_me != [] && Feedback.my_average(session, state, user)
        })
      end
    end
  end

  defp public_entry(entry, state, with_team?) do
    base = %{
      room: room_no(state, entry.room_id),
      accuracy: entry.accuracy,
      reasoning: entry.reasoning,
      score: entry.score,
      discussion: entry.discussion
    }

    if with_team?,
      do: Map.merge(base, %{team: entry[:team], adjudicator: entry[:adjudicator]}),
      else: base
  end

  defp room_no(state, room_id) do
    case Enum.find(state.rooms, &(&1["id"] == room_id)) do
      %{"no" => no} -> "R#{no}"
      _ -> nil
    end
  end
end
