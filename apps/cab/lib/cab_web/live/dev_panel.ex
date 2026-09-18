defmodule CabWeb.DevPanel do
  @moduledoc """
  DEV ONLY always-on left debug panel, rendered by `Layouts.app` when
  :dev_routes is enabled (never in prod builds). A LiveComponent by
  deliberate choice: it is a self-contained stateful widget embedded
  on every page — its events target itself, so host LiveViews need no
  debug code at all.

  Contents: the fixed three-role cast switcher (organiser / judge /
  speaker) and the bot generators (seed a tournament, fill a club
  session's sign-ups).
  """

  use CabWeb, :live_component

  alias Cab.{Clubs, DevSeeds}
  alias CabWeb.LiveAuth

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(clubs: Clubs.list_clubs())
     |> assign_new(:result, fn -> nil end)
     |> assign_new(:failed, fn -> false end)}
  end

  def handle_event(
        "seed_tournament",
        %{"event_id" => event_id, "teams" => teams, "judges" => judges},
        socket
      ) do
    result =
      with {:ok, event_id} <- int(event_id, "event id"),
           {:ok, teams} <- int(teams, "teams"),
           {:ok, judges} <- int(judges, "judges"),
           {:ok, actor} <- LiveAuth.actor(socket.assigns.current_user),
           {:ok, seeded} <- DevSeeds.seed_tournament(actor, event_id, teams, judges) do
        {:ok,
         "event ##{event_id}: +#{seeded.teams} bot teams, +#{seeded.judges} bot judges. " <>
           "Refresh the page to see them."}
      end

    {:noreply, put_result(socket, result)}
  end

  def handle_event(
        "seed_club",
        %{"club_id" => club_id, "speakers" => speakers, "judges" => judges},
        socket
      ) do
    result =
      with {:ok, club_id} <- int(club_id, "club"),
           {:ok, speakers} <- int(speakers, "speakers"),
           {:ok, judges} <- int(judges, "judges"),
           {:ok, seeded} <- DevSeeds.seed_club_signups(club_id, speakers, judges) do
        {:ok,
         "#{seeded.club}: +#{seeded.speakers} bot speakers, +#{seeded.judges} bot judges " <>
           "signed up. Refresh the page to see them."}
      end

    {:noreply, put_result(socket, result)}
  end

  defp put_result(socket, {:ok, message}), do: assign(socket, result: message, failed: false)
  defp put_result(socket, {:error, message}), do: assign(socket, result: message, failed: true)

  defp int(value, label) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> {:ok, int}
      _ -> {:error, "#{label} must be a number"}
    end
  end

  defp role_icon("organiser"), do: "🛠"
  defp role_icon("judge"), do: "⚖"
  defp role_icon("speaker"), do: "🗣"

  def render(assigns) do
    ~H"""
    <aside class="devpanel" id="dev-panel-aside">
      <h3>Act as (dev)</h3>
      <a
        :for={role <- LiveAuth.dev_cast()}
        class={[
          "rolebtn",
          @current_user && @current_user.username == role && "on"
        ]}
        href={"/dev/switch-user?username=#{role}&return_to=#{@return_to}"}
        id={"switch-#{role}"}
      >
        <span>{role_icon(role)}</span> {role}
      </a>

      <h3>Seed tournament</h3>
      <form phx-submit="seed_tournament" phx-target={@myself} id="seed-tournament-form">
        <input
          class="input"
          type="number"
          name="event_id"
          placeholder="event id (from URL)"
          required
        />
        <div class="f-row" style="gap:6px;">
          <input class="input num" type="number" name="teams" value="8" min="1" max="64" />
          <span class="f-help">teams</span>
          <input class="input num" type="number" name="judges" value="2" min="0" max="16" />
          <span class="f-help">judges</span>
        </div>
        <button class="btn btn--soft btn--sm" type="submit" style="margin-top:6px;">
          Generate bots
        </button>
        <span class="f-help" style="display:block;">acts as you — organiser only</span>
      </form>

      <h3>Fill club sign-ups</h3>
      <form phx-submit="seed_club" phx-target={@myself} id="seed-club-form">
        <select name="club_id">
          <option :for={club <- @clubs} value={club.id}>{club.name}</option>
        </select>
        <div class="f-row" style="gap:6px;">
          <input class="input num" type="number" name="speakers" value="8" min="0" max="64" />
          <span class="f-help">speak</span>
          <input class="input num" type="number" name="judges" value="1" min="0" max="16" />
          <span class="f-help">judge</span>
        </div>
        <button class="btn btn--soft btn--sm" type="submit" style="margin-top:6px;">
          Sign bots up
        </button>
        <span class="f-help" style="display:block;">needs an open session</span>
      </form>

      <p
        :if={@result}
        class={["result", (@failed && "alert--warn") || "alert--ok"]}
        id="dev-panel-result"
      >
        {@result}
      </p>
    </aside>
    """
  end
end
