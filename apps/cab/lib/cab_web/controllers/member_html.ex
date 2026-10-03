defmodule CabWeb.MemberHTML do
  use CabWeb, :html

  def show(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 id="member-club-name">{@club.name} — member</h1>
      <p><.link href={~p"/c/#{@club.uuid}"}>Club page</.link></p>

      <%= if @current && @state do %>
        <h2>Current session</h2>
        <p id="session-stage">stage: {@state.stage}</p>

        <%= if @state.stage == :signup do %>
          <form
            id="signup-speak-form"
            action={~p"/c/#{@club.uuid}/member/sessions/#{@current.uuid}/signups"}
            method="post"
          >
            <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
            <input type="hidden" name="as" value="speak" />
            <button type="submit">Sign up to speak</button>
          </form>
          <form
            id="signup-judge-form"
            action={~p"/c/#{@club.uuid}/member/sessions/#{@current.uuid}/signups"}
            method="post"
          >
            <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
            <input type="hidden" name="as" value="judge" />
            <button type="submit">Sign up to judge</button>
          </form>
        <% end %>

        <h3>Signed up</h3>
        <ul id="session-signups">
          <li :for={participant <- @state.signups}>
            {participant["display_name"]} ({participant["role"]})
          </li>
        </ul>

        <%= if @state.rooms != [] do %>
          <h3>Rooms</h3>
          <div :for={room <- @state.rooms} id={"room-#{room["id"]}"}>
            <p>
              Room {room["id"]} — {room["status"]}
              <span :if={room["Motion"]}>· motion: {room["Motion"]["motion_text"]}</span>
            </p>
            <ul>
              <li :for={rt <- Enum.sort_by(room["RoomTeams"] || [], & &1["position"])}>
                {get_in(rt, ["Team", "name"])}
                <span :if={rt["rank"] == 1}>(winner)</span>
              </li>
            </ul>
          </div>
        <% end %>
      <% else %>
        <p>No session is open.</p>
      <% end %>

      <h2>Sessions</h2>
      <ul id="sessions-list">
        <li :for={session <- @sessions}>
          {session.uuid} — opened {session.inserted_at}
        </li>
      </ul>
    </Layouts.app>
    """
  end
end
