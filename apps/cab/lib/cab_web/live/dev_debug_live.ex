defmodule CabWeb.DevDebugLive do
  @moduledoc """
  DEV ONLY debug panel (route exists only under the :dev_routes
  compile guard): auto-generates participants so flows can be tested
  without hand-registering a cast — bot teams + judges for a
  tournament, bot sign-ups for a club session.
  """

  use CabWeb, :live_view

  alias Cab.{Clubs, DevSeeds, EngineApi}
  alias CabWeb.LiveAuth

  def mount(_params, _session, socket) do
    {events, error} =
      case EngineApi.list_public_events() do
        {:ok, events} -> {events, nil}
        {:error, message} -> {[], message}
      end

    {:ok,
     assign(socket,
       page_title: "Debug panel",
       events: events,
       clubs: Clubs.list_clubs(),
       notice: nil,
       error: error
     )}
  end

  def handle_event(
        "seed_tournament",
        %{"event_id" => event_id, "teams" => teams, "judges" => judges},
        socket
      ) do
    with {:ok, event_id} <- int(event_id, "event"),
         {:ok, teams} <- int(teams, "teams"),
         {:ok, judges} <- int(judges, "judges"),
         {:ok, actor} <- LiveAuth.actor(socket.assigns.current_user),
         {:ok, result} <- DevSeeds.seed_tournament(actor, event_id, teams, judges) do
      {:noreply,
       assign(socket,
         notice:
           "event ##{event_id}: created #{result.teams} bot team(s) " <>
             "and #{result.judges} bot judge(s)",
         error: nil
       )}
    else
      {:error, message} -> {:noreply, assign(socket, error: message)}
    end
  end

  def handle_event(
        "seed_club",
        %{"club_id" => club_id, "speakers" => speakers, "judges" => judges},
        socket
      ) do
    with {:ok, club_id} <- int(club_id, "club"),
         {:ok, speakers} <- int(speakers, "speakers"),
         {:ok, judges} <- int(judges, "judges"),
         {:ok, result} <- DevSeeds.seed_club_signups(club_id, speakers, judges) do
      {:noreply,
       assign(socket,
         notice:
           "#{result.club}: #{result.speakers} bot speaker(s) and " <>
             "#{result.judges} bot judge(s) signed up",
         error: nil
       )}
    else
      {:error, message} -> {:noreply, assign(socket, error: message)}
    end
  end

  defp int(value, label) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> {:ok, int}
      _ -> {:error, "#{label} must be a number"}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      dev_routes={@dev_routes}
      dev_users={@dev_users}
      context="debug panel"
      return_to="/dev/debug"
      title="Debug panel"
      subtitle="DEV ONLY — auto-generate participants. Bots are real gateway users with engine counterparts; everything runs through the normal code paths."
      error={@error}
      notice={@notice}
    >
      <div class="cardgrid">
        <div class="card">
          <div class="card__head">
            <b>Seed a tournament</b><span class="tag tag--warn">acts as you</span>
          </div>
          <div class="card__pad">
            <p class="f-help" style="margin-top:0;">
              Creates bot teams (2 shadow speakers each) and bot judges in the chosen event.
              You must be an organiser of that event.
            </p>
            <form phx-submit="seed_tournament" id="seed-tournament-form">
              <div class="f-row">
                <select name="event_id">
                  <option :for={event <- @events} value={event["id"]}>
                    #{event["id"]} — {event["name"]} ({event["status"]})
                  </option>
                </select>
                <input
                  class="input"
                  type="number"
                  name="teams"
                  value="8"
                  min="1"
                  max="64"
                  style="width:5em;"
                />
                <span class="f-help">teams</span>
                <input
                  class="input"
                  type="number"
                  name="judges"
                  value="2"
                  min="0"
                  max="16"
                  style="width:5em;"
                />
                <span class="f-help">judges</span>
              </div>
              <div class="f-row" style="margin-top:10px;">
                <button class="btn btn--cta btn--sm" type="submit">Generate</button>
              </div>
            </form>
          </div>
        </div>

        <div class="card">
          <div class="card__head">
            <b>Fill club sign-ups</b><span class="tag tag--info">bots register themselves</span>
          </div>
          <div class="card__pad">
            <p class="f-help" style="margin-top:0;">
              Signs bot members up for the club's OPEN session (speak/judge), through the same
              1-click registration real members use. Open a session on /club first.
            </p>
            <form phx-submit="seed_club" id="seed-club-form">
              <div class="f-row">
                <select name="club_id">
                  <option :for={club <- @clubs} value={club.id}>{club.name}</option>
                </select>
                <input
                  class="input"
                  type="number"
                  name="speakers"
                  value="8"
                  min="0"
                  max="64"
                  style="width:5em;"
                />
                <span class="f-help">speakers</span>
                <input
                  class="input"
                  type="number"
                  name="judges"
                  value="1"
                  min="0"
                  max="16"
                  style="width:5em;"
                />
                <span class="f-help">judges</span>
              </div>
              <div class="f-row" style="margin-top:10px;">
                <button class="btn btn--cta btn--sm" type="submit">Sign bots up</button>
              </div>
            </form>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
