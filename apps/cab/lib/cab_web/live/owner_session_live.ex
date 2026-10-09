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
         |> assign(:suggestions, %{members: [], users: [], guest: nil})
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

  def handle_event("add_typed", %{"q" => q}, socket) do
    %{club: club, current: current, state: state} = socket.assigns
    add(socket, Invitations.resolve(club, current, state.signups, q))
  end

  def handle_event("start", _params, socket) do
    socket.assigns.current_user
    |> Sessions.start_from_draft(socket.assigns.current)
    |> reply(socket, &"Session started with #{&1} room(s).")
  end

  def handle_event("make_rooms", _params, socket) do
    socket.assigns.current_user
    |> Sessions.make_rooms_from_draft(socket.assigns.current)
    |> reply(socket, &"#{&1} room(s) created.")
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
    do: {:noreply, put_flash(socket, :error, "that did not work — try again")}

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
      |> assign(:page_title, "#{club.name} — #{state.event["name"]}")
    else
      _ ->
        socket
        |> put_flash(:error, "This session is unavailable right now.")
        |> redirect(to: ~p"/c/#{club.uuid}/owner")
    end
  end

  defp with_user(id, wrap) do
    case Accounts.get_user(to_int(id)) do
      nil -> nil
      user -> wrap.(user)
    end
  end

  defp add(socket, resolved) do
    %{current_user: head, current: session} = socket.assigns

    case CabWeb.OwnerController.add_resolved(head, session, resolved) do
      {:ok, info} ->
        {:noreply,
         socket
         |> put_flash(:info, info)
         |> assign(:query, "")
         |> assign(:suggestions, %{members: [], users: [], guest: nil})}

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
