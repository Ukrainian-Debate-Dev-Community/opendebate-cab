defmodule CabWeb.MemberController do
  use CabWeb, :controller

  alias Cab.Sessions
  alias Cab.Sessions.Session
  alias CabWeb.BallotForm

  plug CabWeb.ClubScope, source: :club, require: :member

  # GET /c/:club_uuid/member — sessions list + current session + signups
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
      sessions: sessions,
      current: current,
      state: state,
      my_ballot_room: my_ballot_room(state, conn.assigns.current_user),
      page_title: "#{club.name} · member"
    )
  end

  # GET /c/:club_uuid/member/rooms/:id/ballot — the room judge's ballot
  def ballot(conn, %{"id" => id}) do
    with_ballot_room(conn, id, fn conn, session, room ->
      render_ballot(conn, session, room, nil, nil)
    end)
  end

  # POST /c/:club_uuid/member/rooms/:id/ballot — in-tree twin of the
  # ballot API action: redirect + flash, re-render amber on errors
  def submit_ballot(conn, %{"id" => id} = params) do
    with_ballot_room(conn, id, fn conn, session, room ->
      scores = BallotForm.scores_from_params(params["ballot"])

      case Sessions.submit_ballot(conn.assigns.current_user, session, room["id"], scores) do
        :ok ->
          conn
          |> put_flash(:info, "ballot submitted — the room is confirmed")
          |> redirect(to: ~p"/c/#{conn.assigns.club.uuid}/member")

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

  # Resolves the room inside the club's current session and gates it:
  # only the room's chair (or the head) ever sees a ballot page.
  defp with_ballot_room(conn, id, fun) do
    club = conn.assigns.club

    with {room_id, ""} <- Integer.parse(id),
         %Session{} = session <- List.first(Sessions.list_for_club(club)),
         {:ok, state} <- Sessions.state(%{session | club: club}),
         %{} = room <- Enum.find(state.rooms, &(&1["id"] == room_id)) do
      if Sessions.room_chair?(room, conn.assigns.current_user) or
           conn.assigns.club_role == :owner do
        fun.(conn, session, room)
      else
        conn |> send_resp(403, "forbidden") |> halt()
      end
    else
      _ -> conn |> send_resp(404, "not found") |> halt()
    end
  end

  # the chrome's "Fill ballot" segment: the open room this member chairs
  defp my_ballot_room(%{stage: :running, rooms: rooms}, user) do
    Enum.find(rooms, fn room ->
      room["status"] in ["pending", "judging"] and Sessions.room_chair?(room, user)
    end)
  end

  defp my_ballot_room(_state, _user), do: nil

  # POST /c/:club_uuid/member/sessions/:session_uuid/signups
  def signup(conn, %{"session_uuid" => session_uuid} = params) do
    club = conn.assigns.club
    kind = params["as"]

    with %Session{} = session <- Sessions.get_for_club(club, session_uuid),
         true <- kind in ["speak", "judge"],
         {:ok, _participant} <- Sessions.signup(conn.assigns.current_user, session, kind) do
      conn
      |> put_flash(:info, "signed up to #{kind}")
      |> redirect(to: ~p"/c/#{club.uuid}/member")
    else
      nil ->
        conn |> send_resp(404, "not found") |> halt()

      false ->
        conn
        |> put_flash(:error, ~s(sign up "as" must be "speak" or "judge"))
        |> redirect(to: ~p"/c/#{club.uuid}/member")

      {:error, message} ->
        conn
        |> put_flash(:error, error_message(message))
        |> redirect(to: ~p"/c/#{club.uuid}/member")
    end
  end

  defp error_message(message) when is_binary(message), do: message
  defp error_message(_other), do: "could not sign up"
end
