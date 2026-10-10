defmodule CabWeb.OwnerSessionLive do
  @moduledoc """
  `/c/:club_uuid/owner/s/:session_uuid` — the owner session page, live:
  signups appear as people register, and the allocator works on the
  SERVER-HELD draft (`Cab.Sessions.place/3`, `unplace/2`). A drop is one
  event; the server saves it and every open copy of the page re-renders
  from the same draft. Start session (or Make these rooms at :closed)
  turns the draft into rooms. The page's other actions stay REST
  posts to their owner routes.
  """
  use CabWeb, :live_view

  alias Cab.{Accounts, Clubs, Invitations, Links, Sessions}

  @impl true
  def mount(%{"session_uuid" => session_uuid}, _session, socket) do
    case Sessions.get_for_club(socket.assigns.club, session_uuid) do
      nil ->
        raise CabWeb.NotFoundError

      session ->
        if connected?(socket), do: Sessions.subscribe(session)

        {:ok,
         socket
         |> assign(:session_uuid, session.uuid)
         |> assign(:query, "")
         |> load()}
    end
  end

  @impl true
  def handle_info({:session_state, _uuid, state}, socket),
    do: {:noreply, load(socket, {:ok, state})}

  def handle_info({:session_changed, _uuid}, socket), do: {:noreply, load(socket)}

  def handle_info({:draft_changed, _uuid, draft}, socket) do
    %{current: session, state: state} = socket.assigns

    {:noreply,
     assign(socket, :draft, Sessions.draft(%{session | draft_allocation: draft}, state.signups))}
  end

  @impl true
  def handle_event("place", %{"id" => id, "slot" => slot}, socket) do
    socket.assigns.current
    |> Sessions.place(to_int(id), slot)
    |> reply(socket)
  end

  def handle_event("unplace", %{"id" => id}, socket) do
    socket.assigns.current
    |> Sessions.unplace(to_int(id))
    |> reply(socket)
  end

  # the add field: suggestions as the head types, one click adds
  def handle_event("search", %{"q" => q}, socket) do
    %{club: club, current: current, state: state} = socket.assigns

    {:noreply,
     socket
     |> assign(:query, q)
     |> assign(:suggestions, Invitations.search(club, current, state.signups, q))}
  end

  def handle_event("add_member", %{"id" => id}, socket),
    do: add(socket, with_user(id, &{:member, &1}))

  def handle_event("invite", %{"id" => id}, socket),
    do: add(socket, with_user(id, &{:user, &1}))

  def handle_event("add_guest", %{"name" => name}, socket), do: add(socket, {:guest, name})

  # the address is only shown back to the head, never stored
  def handle_event("add_guest_by_email", %{"name" => name, "email" => email}, socket) do
    case String.trim(name) do
      "" ->
        {:noreply, put_flash(socket, :error, gettext("Enter a name."))}

      name ->
        add(socket, {:guest, name}, fn _info ->
          gettext(
            "%{name} added as a guest. Copy their personal link from People and send it to %{email}.",
            name: name,
            email: String.trim(email)
          )
        end)
    end
  end

  def handle_event("add_typed", %{"q" => q}, socket) do
    %{club: club, current: current, state: state} = socket.assigns
    add(socket, Invitations.resolve(club, current, state.signups, q))
  end

  def handle_event("start", _params, socket) do
    socket.assigns.current_user
    |> Sessions.start_from_draft(socket.assigns.current)
    |> reply(socket, &gettext("Session started with %{count} room(s).", count: &1))
  end

  def handle_event("make_rooms", _params, socket) do
    socket.assigns.current_user
    |> Sessions.make_rooms_from_draft(socket.assigns.current)
    |> reply(socket, &gettext("%{count} room(s) created.", count: &1))
  end

  @impl true
  def render(assigns), do: CabWeb.OwnerHTML.session(assigns)

  # success re-renders through the broadcast; errors become a flash
  defp reply(result, socket, info \\ nil)

  defp reply({:ok, value}, socket, info) do
    socket = if info, do: put_flash(socket, :info, info.(value)), else: socket
    {:noreply, socket}
  end

  defp reply({:error, :conflict, message}, socket, _info),
    do: {:noreply, put_flash(socket, :error, message)}

  defp reply({:error, %{} = details}, socket, _info),
    do: {:noreply, put_flash(socket, :error, details |> Map.values() |> Enum.join(" "))}

  defp reply({:error, message}, socket, _info) when is_binary(message),
    do: {:noreply, put_flash(socket, :error, message)}

  defp reply(_other, socket, _info),
    do: {:noreply, put_flash(socket, :error, gettext("that did not work — try again"))}

  defp load(socket, read \\ nil) do
    club = socket.assigns.club
    session = Sessions.get_for_club(club, socket.assigns.session_uuid)

    with %{} <- session,
         session = %{session | club: club},
         {:ok, state} <- read || Sessions.state(session) do
      socket
      |> assign(:current, session)
      |> assign(:state, state)
      |> assign(:draft, Sessions.draft(session, state.signups))
      |> assign(:links, Links.list_for_session(session))
      |> assign(:invitations, Invitations.for_session(session))
      |> assign(:members, Clubs.list_members(club))
      |> assign(:my_ballot_room, my_ballot_room(state, socket.assigns.current_user))
      |> assign_feedback(session, state)
      |> assign(
        :suggestions,
        Invitations.search(club, session, state.signups, socket.assigns.query)
      )
      |> assign(:page_title, "#{club.name} — #{state.event["name"]}")
    else
      _ ->
        socket
        |> put_flash(:error, gettext("This session is unavailable right now."))
        |> redirect(to: ~p"/c/#{club.uuid}/owner")
    end
  end

  # every team's feedback with its team, read once a ballot is in
  defp assign_feedback(socket, session, state) do
    feedback =
      if Enum.any?(state.rooms, &(&1["status"] in ["completed", "confirmed"])),
        do: Cab.Feedback.all(session),
        else: []

    assign(socket, feedback: feedback, feedback_progress: Cab.Feedback.progress(state, feedback))
  end

  # the room the head chairs while its ballot is still open
  defp my_ballot_room(%{stage: :running, rooms: rooms}, user) do
    Enum.find(rooms, fn room ->
      room["status"] in ["pending", "judging", "completed"] and Sessions.motion?(room) and
        Sessions.room_chair?(room, user)
    end)
  end

  defp my_ballot_room(_state, _user), do: nil

  defp with_user(id, wrap) do
    case Accounts.get_user(to_int(id)) do
      nil -> nil
      user -> wrap.(user)
    end
  end

  defp add(socket, resolved, words \\ & &1) do
    %{current_user: head, current: session} = socket.assigns

    case CabWeb.OwnerController.add_resolved(head, session, resolved) do
      {:ok, info} ->
        {:noreply,
         socket
         |> put_flash(:info, words.(info))
         |> assign(:query, "")
         |> load()}

      error ->
        reply(error, socket)
    end
  end

  defp to_int(id) when is_integer(id), do: id

  defp to_int(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> -1
    end
  end
end
