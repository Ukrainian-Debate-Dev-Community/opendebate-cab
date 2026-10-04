defmodule CabWeb.OwnerHTML do
  use CabWeb, :html

  def show(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.chrome
        crumbs={[{@club.name, ~p"/c/#{@club.uuid}"}]}
        here="owner"
        stage={stage_label(@state)}
        stage_kind={stage_kind(@state)}
      >
        <:seg
          :if={no_open_session?(@state)}
          href={~p"/c/#{@club.uuid}/owner/sessions"}
          method="post"
          primary
        >
          Open session
        </:seg>
        <:seg
          :if={@state && @state.stage == :signup}
          href={~p"/c/#{@club.uuid}/owner/sessions/#{@current.uuid}/rooms"}
          method="post"
          primary
        >
          Make rooms
        </:seg>
        <:seg
          :if={@state && @state.stage == :running}
          href={~p"/c/#{@club.uuid}/owner/sessions/#{@current.uuid}/finish"}
          method="post"
          primary
        >
          Finish session
        </:seg>
      </.chrome>

      <div class="pbody">
        <.flash_banners flash={@flash} />

        <.section title="Join requests">
          <.table
            id="join-requests"
            rows={@join_requests}
            row_id={&"join-request-#{&1.id}"}
            empty="No pending requests."
          >
            <:col :let={request} label="User">
              {request.user.username}
              <.sub :if={request.user.name}>{request.user.name}</.sub>
            </:col>
            <:col :let={request} label="Requested">
              {Calendar.strftime(request.inserted_at, "%-d %b %Y")}
            </:col>
            <:col :let={request}>
              <.link
                href={~p"/c/#{@club.uuid}/owner/join-requests/#{request.id}/approve"}
                method="post"
              >
                approve
              </.link>
            </:col>
            <:col :let={request}>
              <.link
                href={~p"/c/#{@club.uuid}/owner/join-requests/#{request.id}/decline"}
                method="post"
              >
                decline
              </.link>
            </:col>
          </.table>
        </.section>

        <.section :if={no_open_session?(@state)} title="Open a session">
          <.form_for
            id="open-session-form"
            action={~p"/c/#{@club.uuid}/owner/sessions"}
            title="Open a session"
            description="Members can sign up as soon as you open it."
          >
            <:block
              name={:name}
              type={:text}
              label="Session name"
              hint="Shown to members on the club page; defaults to the date."
            />
            <:submit note="Members get the sign-up right away.">Open session</:submit>
          </.form_for>
        </.section>

        <%= if @current && @state do %>
          <.section title="Tonight">
            <.table id="session-signups" rows={@state.signups} empty="Nobody signed up yet.">
              <:col :let={participant} label="Name">{participant["display_name"]}</:col>
              <:col :let={participant} label="Signed up as">{participant["role"]}</:col>
            </.table>
          </.section>

          <.section :if={@state.rooms != []} title="Rooms">
            <.table id="session-rooms" rows={@state.rooms}>
              <:col :let={room} label="Room" code>R{room["id"]}</:col>
              <:col :let={room} label="Status">
                <.tag kind={room_kind(room["status"])}>{room["status"]}</.tag>
              </:col>
              <:col :let={room} label="Motion">
                {(room["Motion"] && room["Motion"]["motion_text"]) || "—"}
              </:col>
              <:col :let={room} label="Teams">
                <%= for rt <- Enum.sort_by(room["RoomTeams"] || [], & &1["position"]) do %>
                  <span>
                    {get_in(rt, ["Team", "name"])}
                    <.tag :if={rt["rank"] == 1} kind={:ok}>won</.tag>
                  </span>
                <% end %>
              </:col>
            </.table>
          </.section>

          <%= for room <- open_rooms(@state) do %>
            <.section title={"Room R#{room["id"]} · motion"}>
              <.form_for
                id={"motion-form-#{room["id"]}"}
                action={~p"/c/#{@club.uuid}/owner/rooms/#{room["id"]}/motion"}
              >
                <:block
                  name={:motion_text}
                  type={:text}
                  label="Motion"
                  required
                  value={room["Motion"] && room["Motion"]["motion_text"]}
                  hint="This room's judge announces it; rooms may debate different motions."
                />
                <:submit note="Visible to the room right away.">Set motion</:submit>
              </.form_for>
            </.section>

            <.section title={"Room R#{room["id"]} · winner"}>
              <.form_for
                id={"winner-form-#{room["id"]}"}
                action={~p"/c/#{@club.uuid}/owner/rooms/#{room["id"]}/winner"}
                hidden={[{"session_uuid", @current.uuid}]}
              >
                <:block
                  name={:room_team_id}
                  type={:select}
                  label="Winning team"
                  required
                  options={team_options(room)}
                />
                <:submit note="Recorded to the room's ballot and confirmed.">
                  Record winner
                </:submit>
              </.form_for>
            </.section>
          <% end %>
        <% end %>

        <.section title="Members">
          <.table id="members-list" rows={@members} empty="No members yet.">
            <:col :let={membership} label="Member">
              {membership.user.username}
              <.sub :if={membership.user.name}>{membership.user.name}</.sub>
            </:col>
            <:col :let={membership} label="Role">{membership.role}</:col>
            <:col :let={membership} label="Since">
              {Calendar.strftime(membership.inserted_at, "%-d %b %Y")}
            </:col>
          </.table>
        </.section>
      </div>
    </Layouts.app>
    """
  end

  defp no_open_session?(state), do: state == nil or state.stage == :done

  defp open_rooms(%{stage: :running, rooms: rooms}),
    do: Enum.reject(rooms, &(&1["status"] in ["confirmed", "completed"]))

  defp open_rooms(_state), do: []

  defp team_options(room) do
    room["RoomTeams"]
    |> List.wrap()
    |> Enum.sort_by(& &1["position"])
    |> Enum.map(fn rt -> {get_in(rt, ["Team", "name"]), rt["id"]} end)
  end

  defp stage_label(nil), do: nil
  defp stage_label(%{stage: :signup}), do: "sign-up open"
  defp stage_label(%{stage: :running}), do: "running"
  defp stage_label(%{stage: :done}), do: "done"

  defp stage_kind(nil), do: :off
  defp stage_kind(%{stage: :signup}), do: :ok
  defp stage_kind(%{stage: :running}), do: :warn
  defp stage_kind(%{stage: :done}), do: :off

  defp room_kind(status) when status in ["confirmed", "completed"], do: :ok
  defp room_kind("pending"), do: :mut
  defp room_kind(_status), do: :warn
end
