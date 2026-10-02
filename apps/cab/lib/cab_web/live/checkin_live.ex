defmodule CabWeb.CheckinLive do
  @moduledoc "Per-round team check-in and room generation."

  use CabWeb, :live_view

  import CabWeb.Ui

  alias Cab.{EngineApi, Tournaments}
  alias CabWeb.LiveAuth

  def mount(%{"id" => id, "n" => n}, _session, socket) do
    socket =
      assign(socket,
        page_title: "Check-in R#{n}",
        event_id: id,
        sequence: String.to_integer(n),
        rounds: [],
        round: nil,
        teams: [],
        judges: [],
        rooms: [],
        notice: nil,
        privileged: false
      )

    {:ok, load(socket)}
  end

  defp load(socket) do
    %{event_id: event_id, sequence: sequence} = socket.assigns

    with {:ok, actor} <- LiveAuth.actor(socket.assigns.current_user),
         {:ok, rounds} <- EngineApi.list_rounds(actor, event_id),
         {:ok, round} <- Tournaments.round_by_sequence(actor, event_id, sequence),
         {:ok, teams} <- Tournaments.teams_with_checkin(actor, event_id),
         {:ok, participants} <- EngineApi.list_participants(actor, event_id),
         {:ok, rooms} <- EngineApi.list_rooms(actor, round["id"]) do
      judges =
        participants
        |> Enum.filter(&(&1["role"] == "adjudicator"))
        |> Enum.reject(& &1["is_eliminated"])

      assign(socket,
        rounds: rounds,
        round: round,
        teams: teams,
        judges: judges,
        rooms: rooms,
        privileged: LiveAuth.privileged?(socket.assigns.current_user, event_id),
        error: nil
      )
    else
      {:error, message} -> assign(socket, error: message)
    end
  end

  def handle_event("toggle", %{"team-id" => team_id}, socket) do
    team = Enum.find(socket.assigns.teams, &(to_string(&1["id"]) == team_id))

    with true <- team != nil,
         {:ok, actor} <- LiveAuth.actor(socket.assigns.current_user),
         {:ok, _} <-
           Tournaments.set_team_checkin(actor, socket.assigns.event_id, team, !team["checked_in"]) do
      {:noreply, load(socket)}
    else
      false -> {:noreply, assign(socket, error: "unknown team")}
      {:error, message} -> {:noreply, assign(socket, error: message)}
    end
  end

  def handle_event("toggle_judge", %{"participant-id" => participant_id}, socket) do
    judge = Enum.find(socket.assigns.judges, &(to_string(&1["id"]) == participant_id))

    with true <- judge != nil,
         {:ok, actor} <- LiveAuth.actor(socket.assigns.current_user),
         {:ok, _} <-
           Tournaments.set_participant_checkin(
             actor,
             socket.assigns.event_id,
             judge["id"],
             !judge["checked_in"]
           ) do
      {:noreply, load(socket)}
    else
      false -> {:noreply, assign(socket, error: "unknown judge")}
      {:error, message} -> {:noreply, assign(socket, error: message)}
    end
  end

  def handle_event("check_in_all", _params, socket) do
    with {:ok, actor} <- LiveAuth.actor(socket.assigns.current_user),
         {:ok, _} <- Tournaments.check_in_everyone(actor, socket.assigns.event_id) do
      {:noreply, socket |> assign(notice: "everyone checked in") |> load()}
    else
      {:error, message} -> {:noreply, assign(socket, error: message)}
    end
  end

  def handle_event("generate_rooms", _params, socket) do
    with {:ok, actor} <- LiveAuth.actor(socket.assigns.current_user),
         {:ok, _count} <-
           Tournaments.generate_rooms(actor, socket.assigns.event_id, socket.assigns.round) do
      {:noreply,
       push_navigate(socket,
         to: ~p"/t/#{socket.assigns.event_id}/r/#{socket.assigns.sequence}/draw"
       )}
    else
      {:error, message} -> {:noreply, assign(socket, error: message)}
    end
  end

  def render(assigns) do
    checked_count = Enum.count(assigns.teams, & &1["checked_in"])

    assigns =
      assigns
      |> assign(:checked_count, checked_count)
      |> assign(:judges_checked, Enum.count(assigns.judges, & &1["checked_in"]))
      |> assign(:rooms_needed, div(checked_count, Cab.Tournaments.teams_per_room()))

    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      dev_routes={@dev_routes}
      dev_users={@dev_users}
      context={"Tournament ##{@event_id}"}
      return_to={"/t/#{@event_id}/r/#{@sequence}/checkin"}
      title={"Round #{@sequence} — check-in"}
      error={@error}
      notice={@notice}
    >
      <:head_tag>
        <.link class="btn btn--soft btn--sm" navigate={~p"/t/#{@event_id}"}>Overview</.link>
      </:head_tag>

      <.td_flow
        event_id={@event_id}
        rounds={@rounds}
        seq={@sequence}
        steps_done={if @rooms != [], do: 1, else: 0}
        active="checkin"
      />

      <.guide :if={@rooms != []}>
        Rooms for this round are made — continue to the draw and motion.
        <:action>
          <.link class="btn btn--cta btn--sm" navigate={~p"/t/#{@event_id}/r/#{@sequence}/draw"}>
            Go to draw
          </.link>
        </:action>
      </.guide>
      <.guide :if={@privileged && @rooms == [] && @teams == []}>
        No teams yet — add them on the Setup page first.
        <:action>
          <.link class="btn btn--cta btn--sm" navigate={~p"/t/#{@event_id}/setup"}>Setup</.link>
        </:action>
      </.guide>
      <.guide :if={
        @privileged && @rooms == [] && @teams != [] &&
          (@checked_count < length(@teams) or @judges_checked < length(@judges))
      }>
        Tick everyone present — teams {@checked_count}/{length(@teams)}, judges {@judges_checked}/{length(
          @judges
        )} — then press <b>Make rooms</b>.
        Rooms hold {Cab.Tournaments.teams_per_room()} teams, 1 checked-in judge each.
        <:action>
          <button class="btn btn--primary btn--sm" phx-click="check_in_all">
            Everyone is here
          </button>
          <button class="btn btn--cta btn--sm" phx-click="generate_rooms">Make rooms</button>
        </:action>
      </.guide>
      <.guide :if={
        @privileged && @rooms == [] && @teams != [] &&
          @checked_count == length(@teams) && @judges_checked == length(@judges)
      }>
        Everyone is checked in — make the rooms.
        <:action>
          <button class="btn btn--cta btn--sm" phx-click="generate_rooms">Make rooms</button>
        </:action>
      </.guide>
      <.guide :if={@privileged && @rooms == [] && @judges_checked < @rooms_needed}>
        ⚠ Only {@judges_checked} judge(s) checked in for {@rooms_needed} room(s) — the draw
        needs one checked-in judge per room.
      </.guide>
      <.guide :if={!@privileged && @rooms == []}>
        Check-in is managed by the organisers — the draw appears here once rooms are made.
      </.guide>

      <div class="section-title">Teams present ({@checked_count} / {length(@teams)})</div>
      <div class="table-card card scroll-x">
        <table class="tbl">
          <thead>
            <tr>
              <th>Present?</th>
              <th>Team</th>
              <th>Speakers</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={team <- @teams}>
              <td style="text-align:center;">
                <input
                  type="checkbox"
                  checked={team["checked_in"]}
                  phx-click="toggle"
                  disabled={!@privileged}
                  phx-value-team-id={team["id"]}
                  style="width:18px;height:18px;accent-color:#66347E;cursor:pointer;"
                />
              </td>
              <td><b>{team["name"]}</b></td>
              <td>{Enum.map_join(team["speakers"], ", ", & &1["name"])}</td>
            </tr>
            <tr :if={@teams == []}>
              <td colspan="3" class="text-muted">No teams yet.</td>
            </tr>
          </tbody>
        </table>
      </div>

      <div class="section-title">Judges present ({@judges_checked} / {length(@judges)})</div>
      <div class="table-card card scroll-x">
        <table class="tbl">
          <thead>
            <tr>
              <th>Present?</th>
              <th>Judge</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={judge <- @judges}>
              <td style="text-align:center;">
                <input
                  type="checkbox"
                  checked={judge["checked_in"]}
                  phx-click="toggle_judge"
                  disabled={!@privileged}
                  phx-value-participant-id={judge["id"]}
                  style="width:18px;height:18px;accent-color:#66347E;cursor:pointer;"
                />
              </td>
              <td><b>{judge["display_name"]}</b></td>
            </tr>
            <tr :if={@judges == []}>
              <td colspan="2" class="text-muted">No judges yet.</td>
            </tr>
          </tbody>
        </table>
      </div>
    </Layouts.app>
    """
  end
end
