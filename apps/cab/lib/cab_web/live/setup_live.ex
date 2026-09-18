defmodule CabWeb.SetupLive do
  @moduledoc """
  Full-control setup: bulk-create teams from "Team: Speaker1, Speaker2"
  lines (each speaker becomes a gateway-provisioned shadow engine
  user), add judges by name, appoint organizer roles.
  """

  use CabWeb, :live_view

  import CabWeb.Ui

  alias Cab.{EngineApi, Tournaments}
  alias CabWeb.LiveAuth

  @example_teams "Alpha: Alice, Aaron\nBravo: Bella, Bruno\nCharlie: Cara, Carl\nDelta: Dana, Dino\nEcho: Elle, Enzo\nFoxtrot: Fay, Finn\nGolf: Gia, Gus\nHotel: Hana, Hugo"
  @example_judges "Judge One\nJudge Two"

  def mount(%{"id" => id}, _session, socket) do
    socket =
      assign(socket,
        page_title: "Setup",
        event_id: id,
        rounds: [],
        teams: [],
        participants: [],
        organizers: [],
        notice: nil,
        privileged: false
      )

    {:ok, load(socket)}
  end

  defp load(socket) do
    with {:ok, actor} <- LiveAuth.actor(socket.assigns.current_user),
         {:ok, rounds} <- EngineApi.list_rounds(actor, socket.assigns.event_id),
         {:ok, teams} <- EngineApi.list_teams(actor, socket.assigns.event_id),
         {:ok, participants} <- EngineApi.list_participants(actor, socket.assigns.event_id),
         {:ok, organizers} <- EngineApi.list_organizers(actor, socket.assigns.event_id) do
      assign(socket,
        rounds: rounds,
        teams: teams,
        participants: participants,
        organizers: organizers,
        privileged: LiveAuth.privileged?(socket.assigns.current_user, socket.assigns.event_id),
        error: nil
      )
    else
      {:error, message} -> assign(socket, error: message)
    end
  end

  def handle_event("create_teams", %{"lines" => lines}, socket) do
    with {:ok, actor} <- LiveAuth.actor(socket.assigns.current_user),
         {:ok, count} <-
           Tournaments.create_teams_from_lines(actor, socket.assigns.event_id, lines) do
      {:noreply, socket |> assign(notice: "created #{count} team(s)") |> load()}
    else
      {:error, message} -> {:noreply, assign(socket, error: message)}
    end
  end

  def handle_event("add_judges", %{"names" => names}, socket) do
    judge_names =
      names |> String.split(~r/\R/) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

    with {:ok, actor} <- LiveAuth.actor(socket.assigns.current_user),
         {:ok, count} <- add_judges(actor, socket.assigns.event_id, judge_names) do
      {:noreply, socket |> assign(notice: "added #{count} judge(s)") |> load()}
    else
      {:error, message} -> {:noreply, assign(socket, error: message)}
    end
  end

  def handle_event("add_organizer", %{"user_id" => user_id, "role" => role}, socket) do
    with {:ok, target} <- parse_int(user_id, "engine user id"),
         {:ok, actor} <- LiveAuth.actor(socket.assigns.current_user),
         {:ok, _} <- EngineApi.add_organizer(actor, socket.assigns.event_id, target, role) do
      {:noreply, socket |> assign(notice: "organizer role granted") |> load()}
    else
      {:error, message} -> {:noreply, assign(socket, error: message)}
    end
  end

  defp add_judges(actor, event_id, names) do
    Enum.reduce_while(names, {:ok, 0}, fn name, {:ok, count} ->
      case EngineApi.provision_participant(actor, event_id, name, "adjudicator") do
        {:ok, _} -> {:cont, {:ok, count + 1}}
        {:error, message} -> {:halt, {:error, "#{name}: #{message}"}}
      end
    end)
  end

  defp parse_int(value, label) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> {:ok, int}
      _ -> {:error, "#{label} must be an integer"}
    end
  end

  defp judges(participants), do: Enum.filter(participants, &(&1["role"] == "adjudicator"))

  defp ready?(teams, participants) do
    n = length(teams)
    n >= 4 and rem(n, 4) == 0 and length(judges(participants)) >= div(n, 4)
  end

  def render(assigns) do
    assigns =
      assign(assigns,
        example_teams: @example_teams,
        example_judges: @example_judges,
        judge_count: length(judges(assigns.participants)),
        ready: ready?(assigns.teams, assigns.participants)
      )

    ~H"""
    <.shell
      current_user={@current_user}
      dev_routes={@dev_routes}
      dev_users={@dev_users}
      context={"Tournament ##{@event_id}"}
      return_to={"/t/#{@event_id}/setup"}
      title="Setup — teams, judges, roles"
      subtitle="Add everyone once, then run the rounds. Rooms hold 4 teams and need 1 judge each — for the full flow use 8 teams and 2 judges."
      error={@error}
      notice={@notice}
    >
      <:head_tag>
        <a class="btn btn--soft btn--sm" href={~p"/t/#{@event_id}"}>Overview</a>
      </:head_tag>

      <.td_flow event_id={@event_id} rounds={@rounds} />

      <.guide :if={@privileged && @ready}>
        You have <b>{length(@teams)} teams</b>
        and <b>{@judge_count} judge(s)</b>
        — enough to
        start Round 1.
        <:action>
          <a class="btn btn--cta btn--sm" href={~p"/t/#{@event_id}/r/1/checkin"}>
            Round 1 check-in
          </a>
        </:action>
      </.guide>
      <.guide :if={@privileged && !@ready}>
        Add teams and judges below. So far: <b>{length(@teams)}</b> teams (need a multiple
        of 4) and <b>{@judge_count}</b> judge(s) (need 1 per room).
      </.guide>

      <.guide :if={!@privileged}>
        Setup is for the event organisers — you are viewing the rosters read-only.
      </.guide>

      <div :if={@privileged} class="cardgrid">
        <div class="card">
          <div class="card__head">
            <b>1 · Teams</b><span class="tag tag--info">{length(@teams)} so far</span>
          </div>
          <div class="card__pad">
            <span class="f-label">One team per line — Team name: Speaker1, Speaker2</span>
            <p class="f-help" style="margin:0 0 8px;">
              Speakers are created automatically. Prefilled with 8 examples — edit or submit as-is.
            </p>
            <form phx-submit="create_teams">
              <textarea name="lines" rows="9" style="width:100%;">{@example_teams}</textarea>
              <div class="f-row" style="margin-top:8px;">
                <button class="btn btn--primary btn--sm" type="submit">Create these teams</button>
              </div>
            </form>
          </div>
        </div>

        <div class="card">
          <div class="card__head">
            <b>2 · Judges</b><span class="tag tag--info">{@judge_count} so far</span>
          </div>
          <div class="card__pad">
            <span class="f-label">One judge name per line</span>
            <form phx-submit="add_judges">
              <textarea name="names" rows="3" style="width:100%;">{@example_judges}</textarea>
              <div class="f-row" style="margin-top:8px;">
                <button class="btn btn--primary btn--sm" type="submit">Add these judges</button>
              </div>
            </form>
            <div style="margin-top:14px;">
              <span class="f-label">3 · Optional: co-organizer role</span>
              <form phx-submit="add_organizer" class="f-row">
                <input
                  class="input"
                  type="text"
                  name="user_id"
                  placeholder="engine user id"
                  style="width:130px;"
                />
                <select name="role">
                  <option value="organiser">organiser</option>
                  <option value="tab">tab</option>
                  <option value="adjcore">adjcore</option>
                </select>
                <button class="btn btn--soft btn--sm" type="submit">Grant</button>
              </form>
              <p :if={@organizers != []} class="f-help" style="margin-top:8px;">
                Current: {Enum.map_join(@organizers, ", ", fn organizer ->
                  "#{get_in(organizer, ["User", "username"]) || "user #{organizer["user_id"]}"} (#{organizer["role"]})"
                end)}
              </p>
            </div>
          </div>
        </div>
      </div>

      <div class="section-title">Teams</div>
      <div class="table-card card scroll-x">
        <table class="tbl">
          <thead>
            <tr>
              <th>Team</th>
              <th>Speakers</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={team <- @teams}>
              <td><b>{team["name"]}</b></td>
              <td>{Enum.map_join(team["speakers"], ", ", & &1["name"])}</td>
              <td>
                <span :if={team["is_swing"]} class="tag tag--muted">swing</span>
                <span :if={team["is_eliminated"]} class="tag tag--warn">eliminated</span>
              </td>
            </tr>
            <tr :if={@teams == []}>
              <td colspan="3" class="text-muted">No teams yet.</td>
            </tr>
          </tbody>
        </table>
      </div>

      <div class="section-title">All participants ({length(@participants)})</div>
      <div class="table-card card scroll-x">
        <table class="tbl">
          <thead>
            <tr>
              <th>Name</th>
              <th>Role</th>
              <th>Checked in</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={participant <- @participants}>
              <td>{participant["display_name"]}</td>
              <td>{participant["role"]}</td>
              <td>
                <span :if={participant["checked_in"]} class="tag tag--ok">yes</span>
                <span :if={!participant["checked_in"]} class="tag tag--muted">—</span>
              </td>
            </tr>
            <tr :if={@participants == []}>
              <td colspan="3" class="text-muted">No participants yet.</td>
            </tr>
          </tbody>
        </table>
      </div>
    </.shell>
    """
  end
end
