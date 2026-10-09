defmodule CabWeb.SessionLive do
  @moduledoc """
  P6 `/c/:club_uuid/s/:session_uuid` — THE session page, live: one
  page per session, public, stage-aware, re-read whenever the session
  announces a change (signups, rooms, motions, ballots, finish).

  Its actions stay REST: Register links to `/r/:sess`, cancel and the
  ballot POST to their controller routes, so every write keeps its
  API twin. Identity-gated, not tree-gated — a guest (session
  identity adopted via `/l/:code`) sees the same page.
  """
  use CabWeb, :live_view

  alias Cab.Accounts.User
  alias Cab.Sessions

  @impl true
  def mount(%{"session_uuid" => session_uuid}, _session, socket) do
    club = socket.assigns.club

    case Sessions.get_for_club(club, session_uuid) do
      nil ->
        raise CabWeb.NotFoundError

      session ->
        session = %{session | club: club}
        if connected?(socket), do: Sessions.subscribe(session)
        {:ok, socket |> assign(:session, session) |> load()}
    end
  end

  @impl true
  def handle_info({:session_changed, _uuid}, socket), do: {:noreply, load(socket)}

  @impl true
  def render(assigns), do: CabWeb.SessionPageHTML.show(assigns)

  defp load(socket) do
    %{session: session, current_user: user, club: club} = socket.assigns

    case Sessions.state(session) do
      {:ok, state} ->
        my_signup = my_signup(state, user)

        socket
        |> assign(:state, state)
        |> assign(:winner, Sessions.winner_from_rooms(state.rooms))
        |> assign(:my_signup, my_signup)
        |> assign(:my_ballot_room, my_ballot_room(state, user))
        |> assign(:my_room_id, my_room_id(state, user, my_signup))
        |> assign(:page_title, "#{club.name} — #{state.event["name"]}")

      {:error, _message} ->
        # the session vanished (cancelled) or the engine is down —
        # back to the club page, which degrades gracefully
        socket
        |> put_flash(:error, "the session is unavailable right now")
        |> redirect(to: ~p"/c/#{club.uuid}")
    end
  end

  defp my_signup(%{signups: signups}, %User{node_user_id: node_user_id})
       when is_integer(node_user_id) do
    Enum.find(signups, &(&1["user_id"] == node_user_id))
  end

  defp my_signup(_state, _user), do: nil

  # the chrome's gold "Fill ballot" segment: the open room this
  # viewer chairs — a completed (not yet confirmed) ballot is still
  # editable by resubmission
  defp my_ballot_room(%{stage: :running, rooms: rooms}, %User{} = user) do
    Enum.find(rooms, fn room ->
      room["status"] in ["pending", "judging", "completed"] and Sessions.room_chair?(room, user)
    end)
  end

  defp my_ballot_room(_state, _user), do: nil

  # the row tint: the room carrying the viewer's participant (speaker
  # slot or chair)
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
end
