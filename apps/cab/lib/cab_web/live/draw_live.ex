defmodule CabWeb.DrawLive do
  @moduledoc "Round draw: rooms table (OG/OO/CG/CO), team-slot swaps, motion set/release."

  use CabWeb, :live_view

  import CabWeb.Ui

  alias Cab.{EngineApi, Tournaments}
  alias CabWeb.LiveAuth

  @positions %{1 => "OG", 2 => "OO", 3 => "CG", 4 => "CO"}

  def mount(%{"id" => id, "n" => n}, _session, socket) do
    socket =
      assign(socket,
        page_title: "Draw R#{n}",
        event_id: id,
        sequence: String.to_integer(n),
        rounds: [],
        round: nil,
        rooms: [],
        motion: nil,
        annotations: %{},
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
         {:ok, rooms} <- EngineApi.list_rooms(actor, round["id"]),
         {:ok, motion} <- Tournaments.round_motion(actor, event_id, sequence),
         {:ok, entries} <- Tournaments.standings(actor, event_id) do
      assign(socket,
        rounds: rounds,
        round: round,
        rooms: rooms,
        motion: motion,
        annotations: annotate(rooms, entries, sequence),
        privileged: LiveAuth.privileged?(socket.assigns.current_user, event_id),
        error: nil
      )
    else
      {:error, message} -> assign(socket, error: message)
    end
  end

  # Draw-transparency metadata per room (organiser view): the bracket
  # point level, each team's points before this round, its pullup flag
  # (fewer points than the room's bracket) and prior side history.
  defp annotate(rooms, entries, sequence) do
    by_id = Map.new(entries, &{&1.id, &1})

    Map.new(rooms, fn room ->
      infos =
        Map.new(room["RoomTeams"] || [], fn room_team ->
          team_id = get_in(room_team, ["Team", "id"])

          info =
            case by_id[team_id] do
              nil ->
                nil

              entry ->
                %{
                  points: Tournaments.points_before(entry, sequence),
                  history: Tournaments.side_history(entry, sequence)
                }
            end

          {team_id, info}
        end)

      level =
        infos
        |> Map.values()
        |> Enum.reject(&is_nil/1)
        |> Enum.map(& &1.points)
        |> Enum.max(fn -> 0 end)

      infos =
        Map.new(infos, fn
          {id, nil} -> {id, nil}
          {id, info} -> {id, Map.put(info, :pullup, info.points < level)}
        end)

      {room["id"], %{level: level, teams: infos}}
    end)
  end

  def handle_event("swap", %{"slot_a" => a, "slot_b" => b}, socket) do
    with {:ok, actor} <- LiveAuth.actor(socket.assigns.current_user),
         {:ok, _} <- EngineApi.swap_teams(actor, socket.assigns.round["id"], a, b) do
      {:noreply, socket |> assign(notice: "teams swapped") |> load()}
    else
      {:error, message} -> {:noreply, assign(socket, error: message)}
    end
  end

  def handle_event("save_motion", %{"text" => text}, socket) do
    with {:ok, actor} <- LiveAuth.actor(socket.assigns.current_user),
         {:ok, _} <-
           Tournaments.set_round_motion(
             actor,
             socket.assigns.event_id,
             socket.assigns.sequence,
             text
           ) do
      {:noreply, socket |> assign(notice: "motion saved") |> load()}
    else
      {:error, message} -> {:noreply, assign(socket, error: message)}
    end
  end

  def handle_event("release_motion", _params, socket) do
    with {:ok, actor} <- LiveAuth.actor(socket.assigns.current_user),
         {:ok, _} <-
           Tournaments.release_round_motion(
             actor,
             socket.assigns.event_id,
             socket.assigns.sequence
           ) do
      {:noreply, socket |> assign(notice: "motion released") |> load()}
    else
      {:error, message} -> {:noreply, assign(socket, error: message)}
    end
  end

  defp slot_options(rooms) do
    for room <- rooms,
        room_team <- Enum.sort_by(room["RoomTeams"] || [], & &1["position"]) do
      label =
        "Room #{room["id"]} #{@positions[room_team["position"]] || room_team["position"]}: " <>
          "#{get_in(room_team, ["Team", "name"])}"

      {room_team["id"], label}
    end
  end

  defp room_team_at(room, position),
    do: Enum.find(room["RoomTeams"] || [], &(&1["position"] == position))

  attr :room, :map, required: true
  attr :position, :integer, required: true
  attr :annotations, :map, required: true
  attr :transparent, :boolean, required: true

  # One team slot: the name, plus (organiser, prelim rounds) the
  # transparency line — points coming in, pullup mark, side history.
  defp team_slot(assigns) do
    room_team = room_team_at(assigns.room, assigns.position)

    info =
      assigns.transparent && room_team &&
        get_in(assigns.annotations, [
          assigns.room["id"],
          :teams,
          get_in(room_team, ["Team", "id"])
        ])

    assigns = assign(assigns, room_team: room_team, info: info)

    ~H"""
    <span :if={is_nil(@room_team)}>—</span>
    <span :if={@room_team}>
      {get_in(@room_team, ["Team", "name"])}
      <span :if={@info && @info.pullup} class="tag tag--warn" title="pulled up from a lower bracket">
        PU
      </span>
      <span :if={@info} class="f-help" style="display:block;">
        {@info.points} pts{if @info.history != [], do: " · " <> Enum.join(@info.history, " ")}
      </span>
    </span>
    """
  end

  defp judges_cell(room) do
    Enum.map_join(room["RoomAdjudicators"] || [], ", ", fn adjudicator ->
      get_in(adjudicator, ["EventParticipant", "display_name"])
    end)
  end

  defp steps_done(rooms, motion) do
    cond do
      rooms == [] -> 0
      motion && motion["is_released"] -> 2
      true -> 1
    end
  end

  def render(assigns) do
    assigns =
      assigns
      |> assign(slots: slot_options(assigns.rooms))
      |> assign(
        transparent:
          assigns.privileged and assigns.round != nil and
            not Tournaments.elim_round?(assigns.round)
      )

    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      dev_routes={@dev_routes}
      dev_users={@dev_users}
      context={"Tournament ##{@event_id}"}
      return_to={"/t/#{@event_id}/r/#{@sequence}/draw"}
      title={"Round #{@sequence} — draw + motion"}
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
        steps_done={steps_done(@rooms, @motion)}
        active="draw"
      />

      <.guide :if={@privileged && @rooms == []}>
        No rooms yet — make them on the check-in page first.
        <:action>
          <.link class="btn btn--cta btn--sm" navigate={~p"/t/#{@event_id}/r/#{@sequence}/checkin"}>
            Check-in
          </.link>
        </:action>
      </.guide>
      <.guide :if={@privileged && @rooms != [] && is_nil(@motion)}>
        Rooms are set. Write the motion below and save it, then release it to the speakers.
      </.guide>
      <.guide :if={@privileged && @rooms != [] && @motion && !@motion["is_released"]}>
        Motion saved but still hidden. Release it when the teams are seated.
        <:action>
          <button class="btn btn--cta btn--sm" phx-click="release_motion">Release motion</button>
        </:action>
      </.guide>
      <.guide :if={@rooms != [] && @motion && @motion["is_released"]}>
        Motion is out — the debate is on. Enter results when it ends.
        <:action>
          <.link class="btn btn--cta btn--sm" navigate={~p"/t/#{@event_id}/r/#{@sequence}/ballots"}>
            Ballots
          </.link>
        </:action>
      </.guide>

      <div :if={@privileged} class="motionline">
        <span class="tag tag--gold">R{@sequence} motion</span>
        <form phx-submit="save_motion" id="motion-form" class="f-row" style="flex:1;">
          <input
            class="input"
            type="text"
            name="text"
            value={@motion && @motion["motion_text"]}
            placeholder="This House would…"
            style="flex:1; min-width:260px;"
          />
          <button class="btn btn--primary btn--sm" type="submit">Save</button>
          <button
            :if={@motion && !@motion["is_released"]}
            class="btn btn--cta btn--sm"
            type="button"
            phx-click="release_motion"
          >
            Release
          </button>
          <span :if={@motion && @motion["is_released"]} class="tag tag--ok">released</span>
        </form>
        <span class="f-help" style="flex-basis:100%;">
          Tournament practice: one motion per round, shared by all its rooms and released to
          everyone at once. (Per-room motions exist too — club sessions use them, set by each
          room's judge.)
        </span>
      </div>

      <div :if={!@privileged} class="motionline">
        <span class="tag tag--gold">R{@sequence} motion</span>
        <span :if={@motion && @motion["is_released"]} class="m">{@motion["motion_text"]}</span>
        <span :if={!(@motion && @motion["is_released"])} class="f-help">
          not released yet — the organisers announce it when the round starts
        </span>
      </div>

      <div class="section-title">Draw</div>
      <div class="table-card card scroll-x">
        <table class="tbl drawtbl">
          <thead>
            <tr>
              <th>Room</th>
              <th :if={@transparent}>Bracket</th>
              <th>OG</th>
              <th>OO</th>
              <th>CG</th>
              <th>CO</th>
              <th>Judge</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={room <- @rooms}>
              <td class="room"><b>#{room["id"]}</b></td>
              <td :if={@transparent}>
                <span class="tag tag--info">{get_in(@annotations, [room["id"], :level])} pts</span>
              </td>
              <td :for={position <- 1..4}>
                <.team_slot
                  room={room}
                  position={position}
                  annotations={@annotations}
                  transparent={@transparent}
                />
              </td>
              <td>{judges_cell(room)}</td>
              <td><.status_tag status={room["status"]} /></td>
            </tr>
            <tr :if={@rooms == []}>
              <td colspan={if @transparent, do: 8, else: 7} class="text-muted">
                Waiting for rooms.
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div :if={@privileged && length(@slots) > 1} class="card">
        <div class="card__head"><b>Fix the draw — swap two team slots</b></div>
        <div class="card__pad">
          <form phx-submit="swap" id="swap-form" class="f-row">
            <select name="slot_a">
              <option :for={{id, label} <- @slots} value={id}>{label}</option>
            </select>
            <span class="text-muted">⇄</span>
            <select name="slot_b">
              <option :for={{id, label} <- @slots} value={id}>{label}</option>
            </select>
            <button class="btn btn--soft btn--sm" type="submit">Swap</button>
            <span class="f-help">only while both rooms are still pending</span>
          </form>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
