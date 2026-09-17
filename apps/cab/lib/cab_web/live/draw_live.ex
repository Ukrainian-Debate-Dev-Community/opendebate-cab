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
        notice: nil
      )

    {:ok, load(socket)}
  end

  defp load(socket) do
    %{event_id: event_id, sequence: sequence} = socket.assigns

    with {:ok, actor} <- LiveAuth.actor(socket.assigns.current_user),
         {:ok, rounds} <- EngineApi.list_rounds(actor, event_id),
         {:ok, round} <- Tournaments.round_by_sequence(actor, event_id, sequence),
         {:ok, rooms} <- EngineApi.list_rooms(actor, round["id"]),
         {:ok, motion} <- Tournaments.round_motion(actor, event_id, sequence) do
      assign(socket, rounds: rounds, round: round, rooms: rooms, motion: motion, error: nil)
    else
      {:error, message} -> assign(socket, error: message)
    end
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
           Tournaments.set_round_motion(actor, socket.assigns.event_id, socket.assigns.sequence, text) do
      {:noreply, socket |> assign(notice: "motion saved") |> load()}
    else
      {:error, message} -> {:noreply, assign(socket, error: message)}
    end
  end

  def handle_event("release_motion", _params, socket) do
    with {:ok, actor} <- LiveAuth.actor(socket.assigns.current_user),
         {:ok, _} <-
           Tournaments.release_round_motion(actor, socket.assigns.event_id, socket.assigns.sequence) do
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

  defp team_cell(room, position) do
    case Enum.find(room["RoomTeams"] || [], &(&1["position"] == position)) do
      nil -> "—"
      room_team -> get_in(room_team, ["Team", "name"])
    end
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
    assigns = assign(assigns, slots: slot_options(assigns.rooms))

    ~H"""
    <.shell
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
        <a class="btn btn--soft btn--sm" href={~p"/t/#{@event_id}"}>Overview</a>
      </:head_tag>

      <.td_flow
        event_id={@event_id}
        rounds={@rounds}
        seq={@sequence}
        steps_done={steps_done(@rooms, @motion)}
        active="draw"
      />

      <.guide :if={@rooms == []}>
        No rooms yet — make them on the check-in page first.
        <:action>
          <a class="btn btn--cta btn--sm" href={~p"/t/#{@event_id}/r/#{@sequence}/checkin"}>
            Check-in
          </a>
        </:action>
      </.guide>
      <.guide :if={@rooms != [] && is_nil(@motion)}>
        Rooms are set. Write the motion below and save it, then release it to the speakers.
      </.guide>
      <.guide :if={@rooms != [] && @motion && !@motion["is_released"]}>
        Motion saved but still hidden. Release it when the teams are seated.
        <:action>
          <button class="btn btn--cta btn--sm" phx-click="release_motion">Release motion</button>
        </:action>
      </.guide>
      <.guide :if={@rooms != [] && @motion && @motion["is_released"]}>
        Motion is out — the debate is on. Enter results when it ends.
        <:action>
          <a class="btn btn--cta btn--sm" href={~p"/t/#{@event_id}/r/#{@sequence}/ballots"}>
            Ballots
          </a>
        </:action>
      </.guide>

      <div class="motionline">
        <span class="tag tag--gold">R{@sequence} motion</span>
        <form phx-submit="save_motion" class="f-row" style="flex:1;">
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

      <div class="section-title">Draw</div>
      <div class="table-card card scroll-x">
        <table class="tbl drawtbl">
          <thead>
            <tr>
              <th>Room</th>
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
              <td>{team_cell(room, 1)}</td>
              <td>{team_cell(room, 2)}</td>
              <td>{team_cell(room, 3)}</td>
              <td>{team_cell(room, 4)}</td>
              <td>{judges_cell(room)}</td>
              <td><.status_tag status={room["status"]} /></td>
            </tr>
            <tr :if={@rooms == []}>
              <td colspan="7" class="text-muted">Waiting for rooms.</td>
            </tr>
          </tbody>
        </table>
      </div>

      <div :if={length(@slots) > 1} class="card">
        <div class="card__head"><b>Fix the draw — swap two team slots</b></div>
        <div class="card__pad">
          <form phx-submit="swap" class="f-row">
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
    </.shell>
    """
  end
end
