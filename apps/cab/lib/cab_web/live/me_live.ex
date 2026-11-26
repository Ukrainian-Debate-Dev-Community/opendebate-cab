defmodule CabWeb.MeLive do
  @moduledoc """
  `/me` - the participant's hub, live: where they sit now (the room,
  their side and role, the motion and the prep clock; a chair publishes
  the motion here, fills the ballot; a team gives feedback),
  registration, invitations, my clubs and schedule, feedback on them,
  the engine's figures per format (rule 0, verbatim) and the history.
  The sessions on their schedule push changes, so a started session, a
  published motion or a ballot shows without a reload.

  `/l/:code/hub` (`:guest`) is the same page for a personal-link guest:
  their link's sessions - the seat, the motion, the ballot, feedback,
  cancelling - without an account's clubs, figures or history.
  """
  use CabWeb, :live_view

  alias Cab.{Accounts, Clubs, EngineApi, Invitations, Sessions}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    guest? = socket.assigns.live_action == :guest
    memberships = if guest?, do: [], else: Clubs.list_user_memberships(user)
    clubs = for membership <- memberships, membership.status == "approved", do: membership.club
    schedule = Sessions.user_schedule(user)

    if connected?(socket) do
      schedule |> Enum.uniq_by(& &1.session.id) |> Enum.each(&Sessions.subscribe(&1.session))
    end

    {:ok,
     socket
     |> assign(
       guest: guest?,
       by_format: if(guest?, do: [], else: stats_by_format(user)),
       invitations: if(guest?, do: [], else: Invitations.for_user(user)),
       memberships: memberships,
       tonight: Sessions.next_by_club(clubs),
       schedule: schedule,
       history: if(guest?, do: [], else: Sessions.user_history(user)),
       feedback_on_me:
         if(guest?,
           do: guest_feedback_on_me(user, schedule),
           else: Cab.Feedback.on_me_recent(user)
         ),
       # a refused ballot's typed rows and message, per room id
       ballot_drafts: %{},
       # a refused feedback's typed values and errors, per room id
       feedback_drafts: %{},
       # the registration form open on the page: %{session, kind, fields, values, errors}
       registering: nil,
       page_title: if(guest?, do: gettext("Personal link"), else: gettext("My page"))
     )
     |> load_seats()
     |> load_open_sessions()}
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

  # Register: the club's questions open inline (prefilled with the
  # member's saved answers); a club that asks none registers at once
  def handle_event("open_register", %{"session" => uuid}, socket) do
    case open_session(socket, uuid) do
      nil ->
        {:noreply, socket}

      %{session: session} ->
        {kind, fields, values} =
          Cab.Registrations.form_for(session.club, socket.assigns.current_user)

        if fields == [],
          do: register(socket, session, %{}),
          else:
            {:noreply,
             assign(socket, :registering, %{
               session: session,
               kind: kind,
               fields: fields,
               values: values,
               errors: %{}
             })}
    end
  end

  def handle_event("close_register", _params, socket),
    do: {:noreply, assign(socket, :registering, nil)}

  def handle_event("register", %{"session" => uuid} = params, socket) do
    case open_session(socket, uuid) do
      nil -> {:noreply, socket}
      %{session: session} -> register(socket, session, params["answers"] || %{})
    end
  end

  # cancels the user's own registration in an open session
  def handle_event("cancel_registration", %{"session" => uuid}, socket) do
    user = socket.assigns.current_user

    with %{session: session} <- open_session(socket, uuid),
         {:ok, state} <- Sessions.state(session),
         %{"id" => participant_id} <-
           Enum.find(state.signups, &Sessions.own_participant?(&1, user)),
         :ok <- Sessions.remove_signup(user, session, participant_id) do
      if socket.assigns.guest do
        # the guest's link went with their place: back to the club
        {:noreply,
         socket
         |> put_flash(:info, gettext("Registration cancelled."))
         |> redirect(to: ~p"/c/#{session.club.uuid}")}
      else
        {:noreply,
         socket |> put_flash(:info, gettext("Registration cancelled.")) |> refresh_registrations()}
      end
    else
      {:error, message} when is_binary(message) -> {:noreply, put_flash(socket, :error, message)}
      _other -> {:noreply, put_flash(socket, :error, gettext("that did not work — try again"))}
    end
  end

  # a speaker's team sends its feedback on the room's adjudicator, once
  # the ballot is in; a refused one keeps what was typed
  def handle_event("send_feedback", %{"session" => uuid, "room" => room} = params, socket) do
    with {room_id, ""} <- Integer.parse(room),
         %{} = seat <- speaker_seat(socket.assigns.seats, uuid, room_id) do
      attrs = Map.take(params, ~w(accuracy reasoning discussion))

      case Cab.Feedback.submit(socket.assigns.current_user, seat.session, room_id, attrs) do
        :ok ->
          {:noreply,
           socket
           |> update(:feedback_drafts, &Map.delete(&1, room_id))
           |> put_flash(:info, gettext("Feedback sent."))
           |> load_seats()}

        {:error, %{} = errors} ->
          {:noreply,
           update(socket, :feedback_drafts, &Map.put(&1, room_id, {attrs, field_errors(errors)}))}

        {:error, :conflict, message} ->
          {:noreply, socket |> put_flash(:error, message) |> load_seats()}

        {:error, message} when is_binary(message) ->
          {:noreply, put_flash(socket, :error, message)}

        _other ->
          {:noreply, put_flash(socket, :error, gettext("that did not work — try again"))}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("that did not work — try again"))}
    end
  end

  @impl true
  def render(assigns), do: CabWeb.MeHTML.show(assigns)

  defp register(socket, session, answers) do
    case Cab.Registrations.register(socket.assigns.current_user, session, answers) do
      {:ok, _participant_id} ->
        if connected?(socket), do: Sessions.subscribe(session)

        {:noreply,
         socket
         |> assign(:registering, nil)
         |> put_flash(:info, gettext("You are registered."))
         |> refresh_registrations()}

      {:error, {:answers, codes}} ->
        registering = socket.assigns.registering
        errors = Ui.FormComponents.answer_errors(registering.fields, codes)
        {:noreply, assign(socket, :registering, %{registering | values: answers, errors: errors})}

      {:error, :conflict, message} ->
        {:noreply, socket |> assign(:registering, nil) |> put_flash(:error, message)}

      {:error, message} when is_binary(message) ->
        {:noreply, put_flash(socket, :error, message)}

      _other ->
        {:noreply, put_flash(socket, :error, gettext("registration is unavailable right now"))}
    end
  end

  defp refresh_registrations(socket) do
    socket
    |> assign(:schedule, Sessions.user_schedule(socket.assigns.current_user))
    |> load_open_sessions()
  end

  defp open_session(socket, uuid),
    do: Enum.find(socket.assigns.open_sessions, &(&1.session.uuid == uuid))

  # a guest: their link's sessions while they take sign-ups (they can
  # only cancel there)
  defp load_open_sessions(%{assigns: %{guest: true}} = socket) do
    rows =
      for %{session: session, club: club} <- socket.assigns.schedule,
          Sessions.stage_of(session) == :signup,
          do: %{session: %{session | club: club}, club: club, registered: true}

    assign(socket, :open_sessions, rows)
  end

  # the sessions taking sign-ups in the user's clubs, soonest first,
  # each marked when the user is in it (their schedule says so)
  defp load_open_sessions(socket) do
    mine = MapSet.new(socket.assigns.schedule, & &1.session.id)

    rows =
      for %{status: "approved", club: club} <- socket.assigns.memberships,
          session <- Sessions.open_for_club(club) do
        %{
          session: %{session | club: club},
          club: club,
          registered: MapSet.member?(mine, session.id)
        }
      end
      |> Enum.sort_by(&(&1.session.scheduled_at || &1.session.inserted_at), DateTime)

    assign(socket, :open_sessions, rows)
  end

  # each seat with its feedback: nil (not a speaker, or not open yet),
  # :open, or {:sent, entry}; the engine is read once per session
  defp load_seats(socket) do
    seats = Sessions.user_seats(socket.assigns.current_user)

    sent =
      seats
      |> Enum.filter(&(&1.role == :speaker and Cab.Feedback.open?(&1.session, &1.room)))
      |> Enum.uniq_by(& &1.session.id)
      |> Map.new(&{&1.session.id, Cab.Feedback.all(&1.session)})

    assign(socket, :seats, Enum.map(seats, &Map.put(&1, :feedback, seat_feedback(&1, sent))))
  end

  defp seat_feedback(%{role: :speaker} = seat, sent) do
    case Map.fetch(sent, seat.session.id) do
      {:ok, feedback} ->
        case Cab.Feedback.sent_by(feedback, seat.room, seat.room_team) do
          nil -> :open
          entry -> {:sent, entry}
        end

      :error ->
        nil
    end
  end

  defp seat_feedback(_seat, _sent), do: nil

  defp speaker_seat(seats, uuid, room_id) do
    Enum.find(
      seats,
      &(&1.role == :speaker and &1.session.uuid == uuid and &1.room["id"] == room_id)
    )
  end

  defp field_errors(errors) do
    for {key, message} <- errors, key in ~w(accuracy reasoning discussion), into: %{} do
      {String.to_existing_atom(key), message}
    end
  end

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

  # a guest who adjudicated: the feedback on them in their finished
  # link sessions, anonymous, as My page shows an account's
  defp guest_feedback_on_me(user, schedule) do
    for %{session: session, club: club} <- schedule,
        session.finished_at != nil,
        session = %{session | club: club},
        {:ok, state} <- [Sessions.state(session)],
        entries = Cab.Feedback.on_adjudicator(session, state, user),
        entries != [] do
      %{
        session: session,
        state: state,
        entries: entries,
        average: Cab.Feedback.my_average(session, state, user)
      }
    end
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
