defmodule CabWeb.MeLive do
  @moduledoc """
  `/me` - the participant's hub, live: where they sit now (the room,
  their side and role, the motion and the prep clock; a chair publishes
  the motion here), invitations, my clubs and schedule, feedback to
  give and on them, the engine's figures per format (rule 0, verbatim)
  and the history. The sessions on their schedule push changes, so a
  started session, a published motion or a ballot shows without a
  reload.
  """
  use CabWeb, :live_view

  alias Cab.{Accounts, Clubs, EngineApi, Invitations, Sessions}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    memberships = Clubs.list_user_memberships(user)
    clubs = for membership <- memberships, membership.status == "approved", do: membership.club
    schedule = Sessions.user_schedule(user)

    if connected?(socket) do
      schedule |> Enum.uniq_by(& &1.session.id) |> Enum.each(&Sessions.subscribe(&1.session))
    end

    {:ok,
     socket
     |> assign(
       by_format: stats_by_format(user),
       invitations: Invitations.for_user(user),
       memberships: memberships,
       tonight: Sessions.next_by_club(clubs),
       schedule: schedule,
       history: Sessions.user_history(user),
       feedback_to_give: Cab.Feedback.to_give(user),
       feedback_on_me: Cab.Feedback.on_me_recent(user),
       # a refused ballot's typed rows and message, per room id
       ballot_drafts: %{},
       page_title: gettext("My page")
     )
     |> load_seats()}
  end

  # ?format=bp|aus: the figures of that format
  @impl true
  def handle_params(params, _uri, socket) do
    by_format = socket.assigns.by_format
    {format, stats} = chosen_stats(by_format, params["format"])

    {:noreply,
     assign(socket,
       stats: stats,
       stats_format: format,
       stats_formats: Enum.map(by_format, &elem(&1, 0))
     )}
  end

  # a session on the schedule changed (rooms made, a motion out, a
  # ballot in): read where the user sits again
  @impl true
  def handle_info({:session_state, _uuid, _state}, socket), do: {:noreply, load_seats(socket)}
  def handle_info({:session_changed, _uuid}, socket), do: {:noreply, load_seats(socket)}
  def handle_info(_message, socket), do: {:noreply, socket}

  # the chair publishes (or updates) their room's motion; a first
  # publish starts 15 minutes of prep
  @impl true
  def handle_event("publish_motion", %{"session" => uuid, "room" => room} = params, socket) do
    with {room_id, ""} <- Integer.parse(room),
         %{} = seat <- chair_seat(socket.assigns.seats, uuid, room_id),
         {:ok, _} <-
           Sessions.set_room_motion(
             socket.assigns.current_user,
             seat.session,
             room_id,
             params["motion_text"],
             motion_attrs(params)
           ) do
      first? = is_nil(seat.room["Motion"])

      if first?,
        do:
          Sessions.set_prep_until(
            seat.session,
            room_id,
            DateTime.add(DateTime.utc_now(), 15, :minute)
          )

      {:noreply,
       socket
       |> put_flash(
         :info,
         if(first?, do: gettext("Motion published."), else: gettext("Motion updated."))
       )
       |> load_seats()}
    else
      {:error, message} when is_binary(message) -> {:noreply, put_flash(socket, :error, message)}
      _other -> {:noreply, put_flash(socket, :error, gettext("that did not work — try again"))}
    end
  end

  # the chair's ballot, inline: ranks derive from the totals; a refused
  # one keeps what was typed, with the message
  def handle_event("submit_ballot", %{"session" => uuid, "room" => room} = params, socket) do
    with {room_id, ""} <- Integer.parse(room),
         %{} = seat <- chair_seat(socket.assigns.seats, uuid, room_id) do
      scores = CabWeb.BallotForm.scores_from_params(params["ballot"], Cab.Format.of(seat.session))

      case Sessions.submit_ballot(socket.assigns.current_user, seat.session, room_id, scores) do
        :ok ->
          {:noreply,
           socket
           |> update(:ballot_drafts, &Map.delete(&1, room_id))
           |> put_flash(:info, gettext("Ballot submitted."))
           |> load_seats()}

        {:error, :forbidden} ->
          {:noreply,
           put_flash(socket, :error, gettext("This ballot is the club head's to edit now."))}

        {:error, %{scores: message}} ->
          {:noreply,
           update(socket, :ballot_drafts, &Map.put(&1, room_id, {params["ballot"], message}))}

        {:error, message} when is_binary(message) ->
          {:noreply,
           update(socket, :ballot_drafts, &Map.put(&1, room_id, {params["ballot"], message}))}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("that did not work — try again"))}
    end
  end

  @impl true
  def render(assigns), do: CabWeb.MeHTML.show(assigns)

  defp load_seats(socket),
    do: assign(socket, :seats, Sessions.user_seats(socket.assigns.current_user))

  defp chair_seat(seats, uuid, room_id) do
    Enum.find(
      seats,
      &(&1.role == :chair and &1.session.uuid == uuid and &1.room["id"] == room_id)
    )
  end

  defp motion_attrs(params) do
    for key <- ~w(infoslide keyword),
        value = String.trim(params[key] || ""),
        value != "",
        into: %{},
        do: {String.to_existing_atom(key), value}
  end

  # the engine's figures per format the user has debated (Cab.Format
  # order): BP places and Australs wins never in one figure
  defp stats_by_format(user) do
    case Accounts.ensure_node_user(user) do
      %{node_user_id: id} when is_integer(id) ->
        for format <- Cab.Format.all(),
            {:ok, %{} = stats} <- [EngineApi.user_stats(id, id, format.code)],
            (get_in(stats, ["overview", "total_debates_ranked"]) || 0) > 0,
            do: {format, stats}

      _ ->
        []
    end
  end

  # the format asked for, else the one debated most
  defp chosen_stats([], _asked), do: {nil, nil}

  defp chosen_stats(by_format, asked) do
    Enum.find(by_format, fn {format, _stats} -> format.key == asked end) ||
      Enum.max_by(by_format, fn {_format, stats} -> stats["overview"]["total_debates_ranked"] end)
  end
end
