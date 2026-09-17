defmodule CabWeb.ClubLive do
  @moduledoc """
  Routine club session (design flow graph 2): open a one-round
  session, members register THEMSELVES with one click (graph 4 —
  speak or judge), rooms are made from attendance, judges pick
  winners, the session lands in club history. Session state lives in
  the engine, so every member's browser shows the same stage.
  """

  use CabWeb, :live_view

  import CabWeb.Ui

  alias Cab.Clubs
  alias CabWeb.LiveAuth

  def mount(_params, _session, socket) do
    socket =
      assign(socket,
        page_title: "Club session",
        clubs: Clubs.list_clubs(),
        club: nil,
        session: nil,
        history: [],
        notice: nil
      )

    {:ok, socket}
  end

  def handle_event("create_club", %{"name" => name}, socket) do
    case Clubs.create_club(%{name: String.trim(name)}) do
      {:ok, club} ->
        {:noreply,
         socket |> assign(clubs: Clubs.list_clubs(), club: club, error: nil) |> load()}

      {:error, changeset} ->
        {:noreply, assign(socket, error: "could not create club: #{inspect(changeset.errors)}")}
    end
  end

  def handle_event("select_club", %{"club-id" => club_id}, socket) do
    {:noreply, socket |> assign(club: Clubs.get_club(club_id), error: nil) |> load()}
  end

  def handle_event("refresh", _params, socket) do
    {:noreply, load(socket)}
  end

  def handle_event("open_session", %{"name" => name, "motion" => motion}, socket) do
    with club when club != nil <- socket.assigns.club,
         {:ok, actor} <- LiveAuth.actor(socket.assigns.current_user),
         {:ok, _event} <-
           Clubs.open_session(actor, club, presence(name, default_session_name()), motion) do
      {:noreply, socket |> assign(notice: "session open — waiting for sign-ups") |> load()}
    else
      nil -> {:noreply, assign(socket, error: "select or create a club first")}
      {:error, message} -> {:noreply, assign(socket, error: message)}
    end
  end

  def handle_event("signup", %{"role" => role}, socket) when role in ["speaker", "adjudicator"] do
    user = socket.assigns.current_user

    with %{event: event} <- socket.assigns.session,
         {:ok, actor} <- LiveAuth.actor(user),
         {:ok, _} <- Clubs.signup(actor, event["id"], user.name || user.username, role) do
      {:noreply, socket |> assign(notice: "you are in — #{tonight(role)}") |> load()}
    else
      nil -> {:noreply, assign(socket, error: "no open session")}
      {:error, message} -> {:noreply, assign(socket, error: message)}
    end
  end

  def handle_event("make_rooms", _params, socket) do
    with %{event: event, round: round} <- socket.assigns.session,
         {:ok, actor} <- LiveAuth.actor(socket.assigns.current_user),
         {:ok, count} <- Clubs.make_rooms(actor, event["id"], round) do
      {:noreply, socket |> assign(notice: "#{count} room(s) made — debate on") |> load()}
    else
      nil -> {:noreply, assign(socket, error: "no open session")}
      {:error, message} -> {:noreply, assign(socket, error: message)}
    end
  end

  def handle_event("pick_winner", %{"room-id" => room_id, "room-team-id" => rt_id}, socket) do
    %{rooms: rooms} = socket.assigns.session
    room = Enum.find(rooms, &(to_string(&1["id"]) == room_id))

    with true <- room != nil,
         {winner_id, ""} <- Integer.parse(rt_id),
         {:ok, actor} <- LiveAuth.actor(socket.assigns.current_user),
         :ok <- Clubs.pick_winner(actor, room, winner_id) do
      {:noreply, socket |> assign(notice: "winner recorded") |> load()}
    else
      false -> {:noreply, assign(socket, error: "unknown room")}
      :error -> {:noreply, assign(socket, error: "pick a team")}
      {:error, message} -> {:noreply, assign(socket, error: message)}
    end
  end

  def handle_event("finish_session", _params, socket) do
    with %{event: event, round: round} <- socket.assigns.session,
         {:ok, actor} <- LiveAuth.actor(socket.assigns.current_user),
         :ok <- Clubs.finish_session(actor, event["id"], round) do
      {:noreply, socket |> assign(notice: "session recorded to club history") |> load()}
    else
      nil -> {:noreply, assign(socket, error: "no open session")}
      {:error, message} -> {:noreply, assign(socket, error: message)}
    end
  end

  defp load(%{assigns: %{club: nil}} = socket), do: assign(socket, session: nil, history: [])

  defp load(socket) do
    club = Clubs.get_club(socket.assigns.club.id)
    socket = assign(socket, club: club)

    with org_id when not is_nil(org_id) <- club.engine_organisation_id,
         {:ok, actor} <- LiveAuth.actor(socket.assigns.current_user),
         {:ok, session} <- Clubs.current_session(actor, org_id),
         {:ok, history} <- Clubs.club_history(actor, org_id) do
      assign(socket, session: session, history: history, error: nil)
    else
      nil -> assign(socket, session: nil, history: [])
      {:error, message} -> assign(socket, error: message)
    end
  end

  defp presence(value, default) do
    case String.trim(value) do
      "" -> default
      trimmed -> trimmed
    end
  end

  defp default_session_name do
    "Club night #{Date.utc_today()}"
  end

  defp tonight("speaker"), do: "speaking tonight"
  defp tonight("adjudicator"), do: "judging tonight"

  defp my_signup(nil, _user), do: nil
  defp my_signup(_session, nil), do: nil

  defp my_signup(%{participants: participants}, user) do
    Enum.find(participants, &(&1["user_id"] == user.node_user_id))
  end

  defp speakers(%{participants: participants}),
    do: Enum.filter(participants, &(&1["role"] == "speaker"))

  defp judges(%{participants: participants}),
    do: Enum.filter(participants, &(&1["role"] == "adjudicator"))

  defp stage_items(session) do
    current =
      case session do
        nil -> -1
        %{stage: :signup} -> 0
        %{stage: :running} -> 2
        %{stage: :closing} -> 3
      end

    ["sign-up", "rooms", "debate", "done"]
    |> Enum.with_index()
    |> Enum.map(fn {label, index} ->
      %{label: label, state: stage_state(index, current)}
    end)
  end

  defp stage_state(index, current) when index < current, do: "done"
  defp stage_state(index, current) when index == current, do: "live"
  defp stage_state(_index, _current), do: nil

  defp speakers_of(room_team) do
    Enum.map_join(room_team["RoomSpeakers"] || [], ", ", fn speaker ->
      get_in(speaker, ["EventParticipant", "display_name"])
    end)
  end

  def render(assigns) do
    ~H"""
    <.shell
      current_user={@current_user}
      dev_routes={@dev_routes}
      dev_users={@dev_users}
      context={@club && "#{@club.name} — club session"}
      return_to="/club"
      title="Club session"
      error={@error}
      notice={@notice}
    >
      <:head_tag>
        <span :if={@club} class="tag tag--info">{@club.name}</span>
        <button :if={@club} class="btn btn--soft btn--sm" phx-click="refresh">Refresh</button>
      </:head_tag>

      <.statusline items={stage_items(@session)} />

      <.guide :if={is_nil(@club)}>
        Pick your club below — or create one — then open tonight's session.
      </.guide>
      <.guide :if={@club && is_nil(@session)}>
        No session open at <b>{@club.name}</b>. Open one and let members sign up.
      </.guide>
      <.guide :if={@session && @session.stage == :signup}>
        Sign-ups are open — register yourself with one click. Rooms need speakers in
        multiples of 8 and one judge per room ({length(speakers(@session))} speakers,
        {length(judges(@session))} judges so far).
        <:action>
          <button class="btn btn--cta btn--sm" phx-click="make_rooms">Make rooms</button>
        </:action>
      </.guide>
      <.guide :if={@session && @session.stage == :running}>
        Debate in progress. When a room ends, its judge (or the host) clicks the winning team.
      </.guide>
      <.guide :if={@session && @session.stage == :closing}>
        All winners recorded — close the session.
        <:action>
          <button class="btn btn--cta btn--sm" phx-click="finish_session">Finish session</button>
        </:action>
      </.guide>

      <div :if={is_nil(@club)} class="card">
        <div class="card__head"><b>Your club</b></div>
        <div class="card__pad">
          <div class="f-row">
            <button
              :for={club <- @clubs}
              class="btn btn--soft btn--sm"
              phx-click="select_club"
              phx-value-club-id={club.id}
            >
              {club.name}
            </button>
          </div>
          <form phx-submit="create_club" class="f-row" style="margin-top:10px;">
            <input class="input" type="text" name="name" placeholder="New club name" />
            <button class="btn btn--soft btn--sm" type="submit">Create club</button>
          </form>
        </div>
      </div>

      <div :if={@club && is_nil(@session)} class="card">
        <div class="card__head"><b>Open tonight's session</b></div>
        <div class="card__pad">
          <form phx-submit="open_session">
            <div class="f-row">
              <input
                class="input"
                type="text"
                name="name"
                placeholder={default_session_name()}
                style="flex:1; min-width:200px;"
              />
              <input
                class="input"
                type="text"
                name="motion"
                placeholder="Motion (optional)"
                style="flex:2; min-width:260px;"
              />
              <button class="btn btn--cta" type="submit">Open sign-ups</button>
            </div>
          </form>
        </div>
      </div>

      <div :if={@session && @session.stage == :signup}>
        <div class="f-row" style="margin: 6px 0 12px;">
          <span :if={my_signup(@session, @current_user)} class="tag tag--ok">
            you are in — {my_signup(@session, @current_user)["role"]}
          </span>
          <button
            :if={@current_user && is_nil(my_signup(@session, @current_user))}
            class="btn btn--primary"
            phx-click="signup"
            phx-value-role="speaker"
          >
            I speak tonight
          </button>
          <button
            :if={@current_user && is_nil(my_signup(@session, @current_user))}
            class="btn btn--soft"
            phx-click="signup"
            phx-value-role="adjudicator"
          >
            I judge tonight
          </button>
          <span :if={is_nil(@current_user)} class="f-help">
            sign in (top-right) to register yourself
          </span>
        </div>

        <div class="table-card card scroll-x">
          <table class="tbl">
            <thead>
              <tr>
                <th>Name</th>
                <th>Tonight</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={participant <- @session.participants}>
                <td>{participant["display_name"]}</td>
                <td>{if participant["role"] == "adjudicator", do: "judge", else: "speak"}</td>
              </tr>
              <tr :if={@session.participants == []}>
                <td colspan="2" class="text-muted">Nobody yet — be first.</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <div :if={@session && @session.stage in [:running, :closing]}>
        <div :if={@session.motion} class="motionline">
          <span class="tag tag--gold">motion</span>
          <span class="m">{@session.motion["motion_text"]}</span>
        </div>

        <div :for={room <- @session.rooms} class="table-card card scroll-x">
          <table class="tbl drawtbl">
            <thead>
              <tr>
                <th>Room #{room["id"]}</th>
                <th>Speakers</th>
                <th>
                  Judge: {Enum.map_join(room["RoomAdjudicators"] || [], ", ", fn adjudicator ->
                    get_in(adjudicator, ["EventParticipant", "display_name"])
                  end)}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr :for={room_team <- Enum.sort_by(room["RoomTeams"] || [], & &1["position"])}>
                <td>
                  <b>{get_in(room_team, ["Team", "name"])}</b>
                  <span :if={room_team["rank"] == 1} class="tag tag--gold">winner</span>
                </td>
                <td>{speakers_of(room_team)}</td>
                <td>
                  <button
                    :if={room["status"] not in ["completed", "confirmed"]}
                    class="btn btn--soft btn--sm"
                    phx-click="pick_winner"
                    phx-value-room-id={room["id"]}
                    phx-value-room-team-id={room_team["id"]}
                  >
                    This team won
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <div :if={@club}>
        <div class="section-title">Club history</div>
        <div class="table-card card scroll-x">
          <table class="tbl">
            <thead>
              <tr>
                <th>Session</th>
                <th>Status</th>
                <th>Winner</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={event <- @history}>
                <td><b>{event["name"]}</b></td>
                <td><.status_tag status={event["status"]} /></td>
                <td>
                  <b :if={event["winner"]}>{event["winner"]}</b>
                  <span :if={is_nil(event["winner"])} class="text-muted">—</span>
                </td>
              </tr>
              <tr :if={@history == []}>
                <td colspan="3" class="text-muted">No sessions yet.</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </.shell>
    """
  end
end
