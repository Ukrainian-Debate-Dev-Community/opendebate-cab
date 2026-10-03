defmodule CabWeb.OwnerHTML do
  use CabWeb, :html

  def show(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 id="owner-club-name">{@club.name} — owner</h1>
      <p><.link href={~p"/c/#{@club.uuid}"}>Club page</.link></p>

      <h2>Pending join requests</h2>
      <p :if={@join_requests == []}>None.</p>
      <div :for={request <- @join_requests} id={"join-request-#{request.id}"}>
        <span>{request.user.username}</span>
        <form
          action={~p"/c/#{@club.uuid}/owner/join-requests/#{request.id}/approve"}
          method="post"
          style="display: inline"
        >
          <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
          <button type="submit">Approve</button>
        </form>
        <form
          action={~p"/c/#{@club.uuid}/owner/join-requests/#{request.id}/decline"}
          method="post"
          style="display: inline"
        >
          <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
          <button type="submit">Decline</button>
        </form>
      </div>

      <h2>Members</h2>
      <ul id="members-list">
        <li :for={membership <- @members}>
          {membership.user.username} ({membership.role})
        </li>
      </ul>

      <h2>Open a session</h2>
      <form id="open-session-form" action={~p"/c/#{@club.uuid}/owner/sessions"} method="post">
        <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
        <input type="text" name="name" placeholder="Session name (optional)" />
        <button type="submit">Open session</button>
      </form>

      <%= if @current && @state do %>
        <h2>Current session</h2>
        <p id="session-stage">stage: {@state.stage}</p>

        <h3>Signed up</h3>
        <ul id="session-signups">
          <li :for={participant <- @state.signups}>
            {participant["display_name"]} ({participant["role"]})
          </li>
        </ul>

        <%= if @state.stage == :signup do %>
          <form
            id="make-rooms-form"
            action={~p"/c/#{@club.uuid}/owner/sessions/#{@current.uuid}/rooms"}
            method="post"
          >
            <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
            <button type="submit">Make rooms</button>
          </form>
        <% end %>

        <%= if @state.rooms != [] do %>
          <h3>Rooms</h3>
          <div :for={room <- @state.rooms} id={"room-#{room["id"]}"}>
            <p>
              Room {room["id"]} — {room["status"]}
              <span :if={room["Motion"]}>· motion: {room["Motion"]["motion_text"]}</span>
            </p>

            <form
              id={"motion-form-#{room["id"]}"}
              action={~p"/c/#{@club.uuid}/owner/rooms/#{room["id"]}/motion"}
              method="post"
            >
              <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
              <input type="hidden" name="session_uuid" value={@current.uuid} />
              <input type="text" name="motion_text" placeholder="Motion" />
              <button type="submit">Set motion</button>
            </form>

            <form
              id={"winner-form-#{room["id"]}"}
              action={~p"/c/#{@club.uuid}/owner/rooms/#{room["id"]}/winner"}
              method="post"
            >
              <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
              <input type="hidden" name="session_uuid" value={@current.uuid} />
              <select name="room_team_id">
                <option
                  :for={rt <- Enum.sort_by(room["RoomTeams"] || [], & &1["position"])}
                  value={rt["id"]}
                >
                  {get_in(rt, ["Team", "name"])}
                </option>
              </select>
              <button type="submit">Record winner</button>
            </form>
          </div>

          <form
            id="finish-session-form"
            action={~p"/c/#{@club.uuid}/owner/sessions/#{@current.uuid}/finish"}
            method="post"
          >
            <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
            <button type="submit">Finish session</button>
          </form>
        <% end %>
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
