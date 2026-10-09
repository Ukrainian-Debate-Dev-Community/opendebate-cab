defmodule CabWeb.RoomLive do
  @moduledoc """
  `/c/:club_uuid/s/:session_uuid/rooms/:id` — ONE room URL for every
  viewer, live: the draw, the motion the moment it is published (with
  the prep clock), the ballot state. Identity picks what renders: the
  chair or the head also gets the motion form and the ballot link.
  The motion and the ballot stay REST posts to their routes.
  """
  use CabWeb, :live_view

  alias Cab.Sessions

  @impl true
  def mount(%{"session_uuid" => session_uuid, "id" => id}, _session, socket) do
    club = socket.assigns.club

    with {room_id, ""} <- Integer.parse(id),
         %{} = session <- Sessions.get_for_club(club, session_uuid) do
      session = %{session | club: club}
      if connected?(socket), do: Sessions.subscribe(session)

      {:ok,
       socket
       |> assign(:session, session)
       |> assign(:room_id, room_id)
       |> load()}
    else
      _ -> raise CabWeb.NotFoundError
    end
  end

  @impl true
  def handle_info({:session_state, _uuid, state}, socket),
    do: {:noreply, show(socket, {:ok, state})}

  def handle_info({:session_changed, _uuid}, socket), do: {:noreply, load(socket)}
  def handle_info({:draft_changed, _uuid, _draft}, socket), do: {:noreply, socket}

  @impl true
  def render(assigns), do: CabWeb.SessionPageHTML.room(assigns)

  defp load(socket), do: show(socket, Sessions.state(socket.assigns.session))

  defp show(socket, read) do
    %{room_id: room_id, club: club} = socket.assigns

    with {:ok, state} <- read,
         %{} = room <- Enum.find(state.rooms, &(&1["id"] == room_id)) do
      socket
      |> assign(:state, state)
      |> assign(:room, room)
      |> assign(:can_act, can_act?(room, socket.assigns))
      |> assign(:can_edit_ballot, can_edit_ballot?(room, socket.assigns))
      |> assign(:page_title, "#{club.name} — #{room_label(room)}")
    else
      nil ->
        if socket.assigns[:room], do: rooms_gone(socket), else: raise(CabWeb.NotFoundError)

      {:error, _message} ->
        socket
        |> put_flash(:error, "This session is unavailable right now.")
        |> redirect(to: ~p"/c/#{club.uuid}")
    end
  end

  # the room was rebuilt away (registration reopened) while open
  defp rooms_gone(socket) do
    %{club: club, session: session} = socket.assigns

    socket
    |> put_flash(:info, "The rooms were deleted. Back to the session.")
    |> redirect(to: ~p"/c/#{club.uuid}/s/#{session.uuid}")
  end

  # a confirmed ballot is the head's to edit (the chair's while open),
  # same rule as Cab.Sessions.submit_ballot/4
  defp can_edit_ballot?(%{"status" => "confirmed"}, %{club_role: role}),
    do: Cab.Clubs.covers?(role, :owner)

  defp can_edit_ballot?(%{"status" => status} = room, assigns)
       when status in ["pending", "judging", "completed"],
       do: Sessions.motion?(room) and can_act?(room, assigns)

  defp can_edit_ballot?(_room, _assigns), do: false

  defp can_act?(room, %{current_user: user, club_role: role}) do
    (user != nil and Sessions.room_chair?(room, user)) or Cab.Clubs.covers?(role, :owner)
  end
end
