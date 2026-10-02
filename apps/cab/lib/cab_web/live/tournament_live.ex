defmodule CabWeb.TournamentLive do
  @moduledoc "Tournament overview: round flow, standings, break to final, champion."

  use CabWeb, :live_view

  import CabWeb.Ui

  alias Cab.{EngineApi, Tournaments}
  alias CabWeb.LiveAuth

  def mount(%{"id" => id}, _session, socket) do
    socket =
      assign(socket,
        event_id: id,
        event: nil,
        rounds: [],
        team_standings: [],
        speaker_standings: [],
        champion: nil,
        privileged: false
      )

    {:ok, load(socket)}
  end

  defp load(socket) do
    with {:ok, actor} <- LiveAuth.actor(socket.assigns.current_user),
         {:ok, event} <- EngineApi.get_event(actor, socket.assigns.event_id),
         {:ok, rounds} <- EngineApi.list_rounds(actor, socket.assigns.event_id),
         {:ok, team_standings} <- Tournaments.standings(actor, socket.assigns.event_id),
         {:ok, speaker_standings} <- EngineApi.speaker_standings(actor, socket.assigns.event_id),
         {:ok, champion} <- Tournaments.champion(actor, socket.assigns.event_id) do
      assign(socket,
        page_title: event["name"],
        event: event,
        rounds: rounds,
        team_standings: team_standings,
        speaker_standings: speaker_standings,
        champion: champion,
        privileged: LiveAuth.privileged?(socket.assigns.current_user, socket.assigns.event_id),
        error: nil
      )
    else
      {:error, message} -> assign(socket, error: message)
    end
  end

  def handle_event("break_semis", _params, socket) do
    with {:ok, actor} <- LiveAuth.actor(socket.assigns.current_user),
         {:ok, %{round: round}} <- Tournaments.break_to_semis(actor, socket.assigns.event_id) do
      {:noreply,
       push_navigate(socket,
         to: ~p"/t/#{socket.assigns.event_id}/r/#{round["sequence"]}/draw"
       )}
    else
      {:error, message} -> {:noreply, assign(socket, error: message)}
    end
  end

  def handle_event("make_gf", _params, socket) do
    with {:ok, actor} <- LiveAuth.actor(socket.assigns.current_user),
         {:ok, round} <- Tournaments.make_grand_final(actor, socket.assigns.event_id) do
      {:noreply,
       push_navigate(socket,
         to: ~p"/t/#{socket.assigns.event_id}/r/#{round["sequence"]}/draw"
       )}
    else
      {:error, message} -> {:noreply, assign(socket, error: message)}
    end
  end

  def handle_event("break_final", _params, socket) do
    with {:ok, actor} <- LiveAuth.actor(socket.assigns.current_user),
         {:ok, round} <- Tournaments.break_to_final(actor, socket.assigns.event_id) do
      {:noreply,
       push_navigate(socket,
         to: ~p"/t/#{socket.assigns.event_id}/r/#{round["sequence"]}/ballots"
       )}
    else
      {:error, message} -> {:noreply, assign(socket, error: message)}
    end
  end

  def handle_event("refresh", _params, socket) do
    {:noreply, load(socket)}
  end

  defp current_round(rounds), do: Enum.find(rounds, &(&1["status"] != "completed"))

  # A break only makes sense for multi-round tournaments; one-round
  # events (club sessions) never see break chrome.
  defp breakable?(rounds), do: length(prelims(rounds)) >= 2

  defp prelims_done?(rounds) do
    breakable?(rounds) and Enum.all?(prelims(rounds), &(&1["status"] == "completed"))
  end

  defp prelims(rounds), do: Enum.reject(rounds, &Tournaments.elim_round?/1)

  defp has_elim?(rounds), do: Enum.any?(rounds, &Tournaments.elim_round?/1)

  defp semi(rounds), do: Enum.find(rounds, &(&1["name"] == Tournaments.semi_name()))

  defp has_gf?(rounds) do
    Enum.any?(rounds, &(&1["name"] in [Tournaments.grand_final_name(), "Final"]))
  end

  defp semis_done?(rounds) do
    case semi(rounds) do
      nil -> false
      round -> round["status"] == "completed"
    end
  end

  # "2 (2nd)" cell for one prelim round of a standings entry.
  defp round_cell(entry, sequence) do
    case entry.rounds[sequence] do
      %{rank: rank, points: points} when is_integer(rank) -> "#{points} (#{ordinal(rank)})"
      _ -> "—"
    end
  end

  defp ordinal(1), do: "1st"
  defp ordinal(2), do: "2nd"
  defp ordinal(3), do: "3rd"
  defp ordinal(rank), do: "#{rank}th"

  defp prelim_sequences(rounds) do
    rounds
    |> Enum.reject(&Tournaments.elim_round?/1)
    |> Enum.map(& &1["sequence"])
    |> Enum.sort()
  end

  def render(assigns) do
    assigns =
      assigns
      |> assign(:current_round, current_round(assigns.rounds))
      |> assign(:prelim_sequences, prelim_sequences(assigns.rounds))

    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      dev_routes={@dev_routes}
      dev_users={@dev_users}
      context={@event && @event["name"]}
      return_to={"/t/#{@event_id}"}
      title={(@event && @event["name"]) || "Tournament ##{@event_id}"}
      error={@error}
    >
      <:head_tag>
        <.status_tag :if={@event} status={@event["status"]} />
        <span :if={@privileged} class="tag tag--info">organiser</span>
        <.link :if={@privileged} class="btn btn--soft btn--sm" navigate={~p"/t/#{@event_id}/setup"}>
          Setup
        </.link>
        <button class="btn btn--soft btn--sm" phx-click="refresh">Refresh</button>
      </:head_tag>

      <.td_flow event_id={@event_id} rounds={@rounds} />

      <div :if={@champion} class="alert alert--ok" style="font-size:1rem;">
        <b>🏆</b> Champion: <b>{@champion}</b>
      </div>

      <.guide :if={
        @privileged && is_nil(@champion) && @current_round &&
          @current_round["name"] in [Tournaments.grand_final_name(), "Final"]
      }>
        The grand final room is set — enter and confirm its ballot to crown the champion.
        <:action>
          <.link
            class="btn btn--cta btn--sm"
            navigate={~p"/t/#{@event_id}/r/#{@current_round["sequence"]}/ballots"}
          >
            Final ballot
          </.link>
        </:action>
      </.guide>

      <.guide :if={
        @privileged && is_nil(@champion) && @current_round &&
          @current_round["name"] == Tournaments.semi_name()
      }>
        Semifinals are on — run the draw and motion, enter and confirm both ballots,
        complete the round, then seed the grand final from here.
        <:action>
          <.link
            class="btn btn--cta btn--sm"
            navigate={~p"/t/#{@event_id}/r/#{@current_round["sequence"]}/draw"}
          >
            Semifinal draw
          </.link>
        </:action>
      </.guide>

      <.guide :if={
        @privileged && is_nil(@champion) && @current_round &&
          !Tournaments.elim_round?(@current_round)
      }>
        Next: run <b>{@current_round["name"]}</b>
        — check-in → draw + motion → ballots.
        First time here? Add teams and judges in
        <.link navigate={~p"/t/#{@event_id}/setup"}>Setup</.link>
        first.
        <:action>
          <.link
            class="btn btn--cta btn--sm"
            navigate={~p"/t/#{@event_id}/r/#{@current_round["sequence"]}/checkin"}
          >
            Run {@current_round["name"]}
          </.link>
        </:action>
      </.guide>

      <.guide :if={!@privileged && is_nil(@champion)}>
        You are viewing as a participant — the draw, motions and standings below update as
        the organisers run the event.
      </.guide>

      <.guide :if={@privileged && is_nil(@champion) && prelims_done?(@rounds) && !has_elim?(@rounds)}>
        All preliminary rounds are done — break. {if length(@team_standings) >=
                                                       Tournaments.break_size(),
                                                     do: "Top 8 → two semifinals → grand final,",
                                                     else: "Fewer than 8 ranked teams:"} or seat the top 4 straight into a final.
        <:action>
          <button
            :if={length(@team_standings) >= Tournaments.break_size()}
            class="btn btn--cta btn--sm"
            phx-click="break_semis"
          >
            Break top 8 → semifinals
          </button>
          <button class="btn btn--soft btn--sm" phx-click="break_final">
            Break top 4 → final
          </button>
        </:action>
      </.guide>

      <.guide :if={@privileged && semis_done?(@rounds) && !has_gf?(@rounds)}>
        Semifinals are complete — seed the grand final from their results
        (top 2 of each room advance).
        <:action>
          <button class="btn btn--cta btn--sm" phx-click="make_gf">Create grand final</button>
        </:action>
      </.guide>

      <div :if={semi(@rounds)}>
        <div class="section-title">Break — top {Tournaments.break_size()}</div>
        <div class="table-card card scroll-x">
          <table class="tbl">
            <thead>
              <tr>
                <th>Break rank</th>
                <th>Team</th>
                <th>Pts</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={
                {team, index} <-
                  Enum.with_index(Enum.take(@team_standings, Tournaments.break_size()), 1)
              }>
                <td class="rank">{index}</td>
                <td><b>{team.name}</b></td>
                <td>{team.points}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <div class="section-title">Rounds</div>
      <div class="table-card card scroll-x">
        <table class="tbl">
          <thead>
            <tr>
              <th>Round</th>
              <th>Status</th>
              <th>Steps</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={round <- @rounds}>
              <td><b>{round["name"]}</b></td>
              <td><.status_tag status={round["status"]} /></td>
              <td>
                <.link
                  class="btn btn--soft btn--sm"
                  navigate={~p"/t/#{@event_id}/r/#{round["sequence"]}/checkin"}
                >
                  Check-in
                </.link>
                <.link
                  class="btn btn--soft btn--sm"
                  navigate={~p"/t/#{@event_id}/r/#{round["sequence"]}/draw"}
                >
                  Draw
                </.link>
                <.link
                  class="btn btn--soft btn--sm"
                  navigate={~p"/t/#{@event_id}/r/#{round["sequence"]}/ballots"}
                >
                  Ballots
                </.link>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div class="section-title">Team standings</div>
      <div class="table-card card scroll-x">
        <table class="tbl">
          <thead>
            <tr>
              <th>#</th>
              <th>Team</th>
              <th>Pts</th>
              <th>1sts</th>
              <th>2nds</th>
              <th :for={seq <- @prelim_sequences}>R{seq}</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={{team, index} <- Enum.with_index(@team_standings, 1)}>
              <td class="rank">{index}</td>
              <td>
                <b>{team.name}</b>
                <span :if={team.eliminated} class="tag tag--muted">out</span>
              </td>
              <td><b>{team.points}</b></td>
              <td>{team.firsts}</td>
              <td>{team.seconds}</td>
              <td :for={seq <- @prelim_sequences} class="text-muted">
                {round_cell(team, seq)}
              </td>
            </tr>
            <tr :if={@team_standings == []}>
              <td colspan={5 + length(@prelim_sequences)} class="text-muted">
                Standings appear once ballots are in.
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div class="section-title">Speaker standings</div>
      <div class="table-card card scroll-x">
        <table class="tbl">
          <thead>
            <tr>
              <th>#</th>
              <th>Speaker</th>
              <th>Pts</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={{speaker, index} <- Enum.with_index(@speaker_standings, 1)}>
              <td class="rank">{index}</td>
              <td>{speaker["name"]}</td>
              <td>{speaker["total_points"]}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </Layouts.app>
    """
  end
end
