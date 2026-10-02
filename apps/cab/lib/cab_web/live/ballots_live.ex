defmodule CabWeb.BallotsLive do
  @moduledoc """
  Per-room ballots for a round: 8 speaker score inputs (team ranks are
  derived from team score sums), submit/reopen/confirm, and completing
  the round once every room is confirmed.
  """

  use CabWeb, :live_view

  import CabWeb.Ui

  alias Cab.{EngineApi, Tournaments}
  alias CabWeb.LiveAuth

  @position_names %{
    1 => "Opening Government",
    2 => "Opening Opposition",
    3 => "Closing Government",
    4 => "Closing Opposition"
  }

  def mount(%{"id" => id, "n" => n}, _session, socket) do
    socket =
      assign(socket,
        page_title: "Ballots R#{n}",
        event_id: id,
        sequence: String.to_integer(n),
        rounds: [],
        round: nil,
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
         {:ok, rooms} <- EngineApi.list_rooms(actor, round["id"]) do
      assign(socket,
        rounds: rounds,
        round: round,
        rooms: rooms,
        privileged: LiveAuth.privileged?(socket.assigns.current_user, event_id),
        error: nil
      )
    else
      {:error, message} -> assign(socket, error: message)
    end
  end

  def handle_event("submit_ballot", %{"room_id" => room_id, "scores" => scores}, socket) do
    room = Enum.find(socket.assigns.rooms, &(to_string(&1["id"]) == room_id))

    with true <- room != nil,
         {:ok, parsed} <- parse_scores(scores),
         {:ok, team_rankings, speaker_scores} <- Tournaments.ballot_payload(room, parsed),
         {:ok, actor} <- LiveAuth.actor(socket.assigns.current_user),
         {:ok, _} <- EngineApi.submit_scores(actor, room["id"], team_rankings, speaker_scores) do
      {:noreply, socket |> assign(notice: "ballot submitted for room ##{room_id}") |> load()}
    else
      false -> {:noreply, assign(socket, error: "unknown room")}
      {:error, message} -> {:noreply, assign(socket, error: message)}
    end
  end

  def handle_event("submit_elim_ballot", %{"room_id" => room_id, "ranks" => ranks}, socket) do
    room = Enum.find(socket.assigns.rooms, &(to_string(&1["id"]) == room_id))

    with true <- room != nil,
         {:ok, parsed} <- parse_ranks(ranks),
         {:ok, team_rankings, speaker_scores} <- Tournaments.elim_ballot_payload(room, parsed),
         {:ok, actor} <- LiveAuth.actor(socket.assigns.current_user),
         {:ok, _} <- EngineApi.submit_scores(actor, room["id"], team_rankings, speaker_scores) do
      {:noreply, socket |> assign(notice: "result submitted for room ##{room_id}") |> load()}
    else
      false -> {:noreply, assign(socket, error: "unknown room")}
      {:error, message} -> {:noreply, assign(socket, error: message)}
    end
  end

  def handle_event("confirm", %{"room-id" => room_id}, socket) do
    room_action(socket, room_id, &EngineApi.confirm_room/2, "ballot confirmed")
  end

  def handle_event("unconfirm", %{"room-id" => room_id}, socket) do
    room_action(socket, room_id, &EngineApi.unconfirm_room/2, "ballot unconfirmed")
  end

  def handle_event("reopen", %{"room-id" => room_id}, socket) do
    room_action(socket, room_id, &EngineApi.reopen_room/2, "room reopened, ballot cleared")
  end

  def handle_event("complete_round", _params, socket) do
    with {:ok, actor} <- LiveAuth.actor(socket.assigns.current_user),
         {:ok, _} <-
           EngineApi.update_round(actor, socket.assigns.round["id"], %{status: "completed"}) do
      {:noreply, socket |> assign(notice: "round completed") |> load()}
    else
      {:error, message} -> {:noreply, assign(socket, error: message)}
    end
  end

  defp room_action(socket, room_id, fun, notice) do
    with {:ok, actor} <- LiveAuth.actor(socket.assigns.current_user),
         {:ok, _} <- fun.(actor, room_id) do
      {:noreply, socket |> assign(notice: notice) |> load()}
    else
      {:error, message} -> {:noreply, assign(socket, error: message)}
    end
  end

  defp parse_ranks(ranks) do
    Enum.reduce_while(ranks, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      with {team_id, ""} <- Integer.parse(key),
           {rank, ""} <- Integer.parse(String.trim(value)) do
        {:cont, {:ok, Map.put(acc, team_id, rank)}}
      else
        _ -> {:halt, {:error, "pick a place for every team"}}
      end
    end)
  end

  defp elim?(round), do: round != nil and Tournaments.elim_round?(round)

  defp parse_scores(scores) do
    Enum.reduce_while(scores, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      with {speaker_id, ""} <- Integer.parse(key),
           {score, ""} <- Float.parse(String.trim(value)) do
        {:cont, {:ok, Map.put(acc, speaker_id, score)}}
      else
        _ -> {:halt, {:error, "scores must be numbers (got #{inspect(value)})"}}
      end
    end)
  end

  defp all_confirmed?(rooms), do: rooms != [] and Enum.all?(rooms, &(&1["status"] == "confirmed"))

  defp round_completed?(round), do: round && round["status"] == "completed"

  defp confirmed_count(rooms), do: Enum.count(rooms, &(&1["status"] == "confirmed"))

  defp position_name(position), do: Map.get(@position_names, position, "Position #{position}")

  defp next_round(rounds, sequence), do: Enum.find(rounds, &(&1["sequence"] == sequence + 1))

  defp steps_done(rooms, round) do
    cond do
      round_completed?(round) -> 4
      all_confirmed?(rooms) -> 3
      rooms != [] -> 2
      true -> 0
    end
  end

  def render(assigns) do
    draft_hidden = !assigns.privileged && Tournaments.draw_draft?(assigns.round)

    assigns =
      assigns
      |> assign(:next_round, next_round(assigns.rounds, assigns.sequence))
      |> assign(:draft_hidden, draft_hidden)
      |> assign(:visible_rooms, if(draft_hidden, do: [], else: assigns.rooms))

    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      dev_routes={@dev_routes}
      dev_users={@dev_users}
      context={"Tournament ##{@event_id}"}
      return_to={"/t/#{@event_id}/r/#{@sequence}/ballots"}
      title={"Round #{@sequence} — ballots"}
      error={@error}
      notice={@notice}
    >
      <:head_tag>
        <span :if={@visible_rooms != []} class="tag tag--info">
          {confirmed_count(@visible_rooms)}/{length(@visible_rooms)} confirmed
        </span>
        <.link class="btn btn--soft btn--sm" navigate={~p"/t/#{@event_id}"}>Overview</.link>
      </:head_tag>

      <.td_flow
        event_id={@event_id}
        rounds={@rounds}
        seq={@sequence}
        steps_done={steps_done(@rooms, @round)}
        active="ballots"
      />

      <.guide :if={@privileged && @rooms == []}>
        No rooms in this round yet — make them on the check-in page.
        <:action>
          <.link class="btn btn--cta btn--sm" navigate={~p"/t/#{@event_id}/r/#{@sequence}/checkin"}>
            Check-in
          </.link>
        </:action>
      </.guide>
      <.guide :if={@privileged && @rooms != [] && !all_confirmed?(@rooms) && !elim?(@round)}>
        Enter 8 speaker scores per room (50–100) and submit — team places are computed from
        the totals. Then <b>confirm</b> each ballot to lock it.
      </.guide>
      <.guide :if={@privileged && @rooms != [] && !all_confirmed?(@rooms) && elim?(@round)}>
        Elimination round: order the four teams per room — no speaker scores. {if Tournaments.advance_count(
                                                                                    @round
                                                                                  ) == 1,
                                                                                  do:
                                                                                    "The 1st place wins the tournament.",
                                                                                  else:
                                                                                    "The top 2 advance."} Then
        <b>confirm</b>
        each result to lock it.
      </.guide>
      <.guide :if={@privileged && all_confirmed?(@rooms) && !round_completed?(@round)}>
        All ballots confirmed — complete the round.
        <:action>
          <button class="btn btn--cta btn--sm" phx-click="complete_round">Complete round</button>
        </:action>
      </.guide>
      <.guide :if={@privileged && round_completed?(@round) && @next_round}>
        Round {@sequence} is done.
        <:action>
          <.link
            class="btn btn--cta btn--sm"
            navigate={
              if Tournaments.elim_round?(@next_round),
                do: ~p"/t/#{@event_id}/r/#{@next_round["sequence"]}/draw",
                else: ~p"/t/#{@event_id}/r/#{@next_round["sequence"]}/checkin"
            }
          >
            {if Tournaments.elim_round?(@next_round),
              do: @next_round["name"],
              else: "Start #{@next_round["name"]}"}
          </.link>
        </:action>
      </.guide>
      <.guide :if={@privileged && round_completed?(@round) && is_nil(@next_round)}>
        Round {@sequence} is done — back to the overview to break or see standings.
        <:action>
          <.link class="btn btn--cta btn--sm" navigate={~p"/t/#{@event_id}"}>Overview</.link>
        </:action>
      </.guide>

      <.guide :if={@draft_hidden}>
        The organisers are preparing the draw — rooms and ballots appear here once it is
        released.
      </.guide>

      <div :for={room <- @visible_rooms} class="card" style="max-width:680px;">
        <div class="card__head">
          <b>Room #{room["id"]}</b>
          <.status_tag status={room["status"]} />
        </div>

        <form
          :if={@privileged && !elim?(@round) && room["status"] in ["pending", "judging"]}
          phx-submit="submit_ballot"
          id={"ballot-form-#{room["id"]}"}
        >
          <input type="hidden" name="room_id" value={room["id"]} />
          <div
            :for={room_team <- Enum.sort_by(room["RoomTeams"] || [], & &1["position"])}
            class="ballot-team"
          >
            <div>
              <h4>{get_in(room_team, ["Team", "name"])}</h4>
              <div class="f-help">{position_name(room_team["position"])}</div>
            </div>
            <span class="tag tag--info">{position_name(room_team["position"]) |> abbrev()}</span>
            <div class="spk-row">
              <div :for={speaker <- room_team["RoomSpeakers"] || []} class="spk">
                <span class="nm">{get_in(speaker, ["EventParticipant", "display_name"])}</span>
                <input
                  type="number"
                  name={"scores[#{speaker["id"]}]"}
                  min="50"
                  max="100"
                  step="0.5"
                  value="75"
                  required
                />
              </div>
            </div>
          </div>
          <div class="f-row" style="padding:14px 18px;">
            <button class="btn btn--cta" type="submit">Submit ballot</button>
            <span class="f-help">places are derived from team totals</span>
          </div>
        </form>

        <form
          :if={@privileged && elim?(@round) && room["status"] in ["pending", "judging"]}
          phx-submit="submit_elim_ballot"
          id={"elim-ballot-form-#{room["id"]}"}
        >
          <input type="hidden" name="room_id" value={room["id"]} />
          <div
            :for={room_team <- Enum.sort_by(room["RoomTeams"] || [], & &1["position"])}
            class="ballot-team"
          >
            <div>
              <h4>{get_in(room_team, ["Team", "name"])}</h4>
              <div class="f-help">{position_name(room_team["position"])}</div>
            </div>
            <span class="tag tag--info">{position_name(room_team["position"]) |> abbrev()}</span>
            <select name={"ranks[#{room_team["id"]}]"} required>
              <option value="">place…</option>
              <option value="1">1st</option>
              <option value="2">2nd</option>
              <option value="3">3rd</option>
              <option value="4">4th</option>
            </select>
          </div>
          <div class="f-row" style="padding:14px 18px;">
            <button class="btn btn--cta" type="submit">Submit result</button>
            <span class="f-help">
              no speaker scores in elimination rounds — the order decides who advances
            </span>
          </div>
        </form>

        <div
          :if={!@privileged && room["status"] in ["pending", "judging"]}
          class="card__pad f-help"
        >
          Ballot pending — results appear here once submitted and confirmed.
        </div>

        <div :if={room["status"] in ["completed", "confirmed"]} class="card__pad">
          <div
            :for={room_team <- Enum.sort_by(room["RoomTeams"] || [], & &1["rank"])}
            class="kv"
          >
            <span>{ordinal(room_team["rank"])}</span>
            <b>{get_in(room_team, ["Team", "name"])}</b>
            <span
              :if={elim?(@round) && room_team["rank"] <= Tournaments.advance_count(@round)}
              class="tag tag--ok"
            >
              {if Tournaments.advance_count(@round) == 1, do: "champion", else: "advancing"}
            </span>
            <span
              :if={elim?(@round) && room_team["rank"] > Tournaments.advance_count(@round)}
              class="tag tag--muted"
            >
              eliminated
            </span>
          </div>
          <div class="f-row" style="margin-top:10px;">
            <button
              :if={@privileged && room["status"] == "completed"}
              class="btn btn--primary btn--sm"
              phx-click="confirm"
              phx-value-room-id={room["id"]}
            >
              Confirm ballot
            </button>
            <button
              :if={@privileged && room["status"] == "completed"}
              class="btn btn--soft btn--sm"
              phx-click="reopen"
              phx-value-room-id={room["id"]}
            >
              Reopen (edit scores)
            </button>
            <button
              :if={@privileged && room["status"] == "confirmed"}
              class="btn btn--soft btn--sm"
              phx-click="unconfirm"
              phx-value-room-id={room["id"]}
            >
              Unconfirm
            </button>
          </div>
        </div>
      </div>

      <div class="f-row" style="margin-top:6px;">
        <button
          :if={@privileged}
          class="btn btn--primary"
          phx-click="complete_round"
          disabled={not all_confirmed?(@rooms) or round_completed?(@round)}
        >
          Complete round
        </button>
        <span :if={round_completed?(@round)} class="tag tag--ok">round completed</span>
      </div>
    </Layouts.app>
    """
  end

  defp abbrev("Opening Government"), do: "OG"
  defp abbrev("Opening Opposition"), do: "OO"
  defp abbrev("Closing Government"), do: "CG"
  defp abbrev("Closing Opposition"), do: "CO"
  defp abbrev(other), do: other

  defp ordinal(1), do: "1st"
  defp ordinal(2), do: "2nd"
  defp ordinal(3), do: "3rd"
  defp ordinal(rank), do: "#{rank}th"
end
