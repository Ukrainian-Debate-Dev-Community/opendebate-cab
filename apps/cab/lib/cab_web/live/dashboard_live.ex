defmodule CabWeb.DashboardLive do
  @moduledoc "Dashboard: engine event cards, create tournament, dev user switcher."

  use CabWeb, :live_view

  alias Cab.EngineApi
  alias CabWeb.LiveAuth

  def mount(_params, _session, socket) do
    {events, error} =
      case EngineApi.list_public_events() do
        {:ok, events} -> {events, nil}
        {:error, message} -> {[], message}
      end

    {:ok, assign(socket, page_title: "Dashboard", events: events, error: error)}
  end

  def handle_event("create_tournament", %{"name" => name}, socket) do
    name = String.trim(name)

    with :ok <- validate_name(name),
         {:ok, actor} <- LiveAuth.actor(socket.assigns.current_user),
         {:ok, %{"event" => event}} <- EngineApi.create_tournament(actor, name),
         {:ok, _} <- create_prelim_rounds(actor, event["id"]) do
      {:noreply, push_navigate(socket, to: ~p"/t/#{event["id"]}/setup")}
    else
      {:error, message} -> {:noreply, assign(socket, error: message)}
    end
  end

  defp validate_name(""), do: {:error, "tournament name required"}
  defp validate_name(_), do: :ok

  defp create_prelim_rounds(actor, event_id) do
    Enum.reduce_while(1..3, {:ok, 0}, fn n, {:ok, count} ->
      case EngineApi.create_round(actor, event_id, "Round #{n}", n) do
        {:ok, _} -> {:cont, {:ok, count + 1}}
        {:error, message} -> {:halt, {:error, "creating round #{n}: #{message}"}}
      end
    end)
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      dev_routes={@dev_routes}
      dev_users={@dev_users}
      title="My events"
      subtitle="Create a tournament and run it end to end, or run a quick club session."
      error={@error}
    >
      <.guide :if={is_nil(@current_user) && @dev_routes}>
        <b>Start here:</b>&nbsp; open the user menu in the top-right corner and pick who you
        are — every action is done as that user.
      </.guide>
      <.guide :if={@current_user}>
        Create a tournament below (you become its organiser, rounds 1–3 are made for you),
        or open an existing event.
      </.guide>

      <div class="cardgrid">
        <div class="card">
          <div class="card__head"><b>New tournament</b><span class="tag tag--gold">start</span></div>
          <div class="card__pad">
            <div class="kv"><span>format</span><b>BP — 4 teams per room</b></div>
            <div class="kv"><span>rounds</span><b>3 + final</b></div>
            <div class="kv"><span>you need</span><b>8 teams, 2 judges</b></div>
            <form
              phx-submit="create_tournament"
              id="create-tournament-form"
              class="f-row"
              style="margin-top:10px;"
            >
              <input class="input" type="text" name="name" placeholder="e.g. Friday Night Open" />
              <button class="btn btn--cta btn--sm" type="submit">Create</button>
            </form>
          </div>
        </div>

        <div class="card">
          <div class="card__head"><b>Club session</b><span class="tag tag--info">casual</span></div>
          <div class="card__pad">
            <div class="kv"><span>one room</span><b>4 teams × 2 speakers</b></div>
            <div class="kv"><span>result</span><b>winner pick, saved to history</b></div>
            <div class="f-row" style="margin-top:10px;">
              <.link class="btn btn--primary btn--sm" navigate={~p"/club"}>Open</.link>
            </div>
          </div>
        </div>
      </div>

      <div class="section-title">All events</div>
      <div class="table-card card scroll-x">
        <table class="tbl">
          <thead>
            <tr>
              <th>Name</th>
              <th>Status</th>
              <th>Organisation</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={event <- @events}>
              <td><b>{event["name"]}</b></td>
              <td><.status_tag status={event["status"]} /></td>
              <td>{get_in(event, ["Organisation", "name"])}</td>
              <td>
                <.link class="btn btn--primary btn--sm" navigate={~p"/t/#{event["id"]}"}>Open</.link>
              </td>
            </tr>
            <tr :if={@events == []}>
              <td colspan="4" class="text-muted">No events yet — create the first one above.</td>
            </tr>
          </tbody>
        </table>
      </div>
    </Layouts.app>
    """
  end
end
