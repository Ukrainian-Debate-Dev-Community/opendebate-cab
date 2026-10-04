defmodule CabWeb.OwnerHTML do
  use CabWeb, :html

  # this view's ballot/1 is the page; the kit component stays qualified
  import CabWeb.Ui, except: [ballot: 1]
  alias CabWeb.Ui

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
          href={~p"/c/#{@club.uuid}/owner/sessions/#{@current.uuid}/compose"}
        >
          Compose rooms
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
          :if={deletable_rooms?(@state)}
          href={~p"/c/#{@club.uuid}/owner/sessions/#{@current.uuid}/rooms/delete"}
          method="post"
          quiet
        >
          Delete rooms
        </:seg>
        <:seg
          :if={@state && @state.stage == :running}
          href={~p"/c/#{@club.uuid}/owner/sessions/#{@current.uuid}/finish"}
          method="post"
          primary
        >
          Finish session
        </:seg>
        <:seg
          :if={@state && @state.stage in [:signup, :running]}
          href={~p"/c/#{@club.uuid}/owner/sessions/#{@current.uuid}/cancel"}
          method="post"
          quiet
        >
          Cancel session
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
              <:col :let={participant} :if={@state.stage == :signup}>
                <.link
                  href={
                    ~p"/c/#{@club.uuid}/owner/sessions/#{@current.uuid}/signups/#{participant["id"]}/remove"
                  }
                  method="post"
                >
                  remove
                </.link>
              </:col>
            </.table>
          </.section>

          <.section
            :if={@state.stage == :signup && addable_members(@members, @state.signups) != []}
            title="Add a participant"
          >
            <.form_for
              id="add-signup-form"
              action={~p"/c/#{@club.uuid}/owner/sessions/#{@current.uuid}/signups"}
              description="Sign an approved member up on their behalf."
            >
              <:block
                name={:username}
                type={:select}
                label="Member"
                options={addable_members(@members, @state.signups)}
              />
              <:block
                name={:as}
                type={:select}
                label="Signs up to"
                value="speak"
                options={[{"speak", "speak"}, {"judge", "judge"}]}
              />
              <:submit note="They appear in tonight's list right away.">Add participant</:submit>
            </.form_for>
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
              <:col :let={room}>
                <.link
                  :if={room["status"] in ["pending", "judging"]}
                  href={~p"/c/#{@club.uuid}/owner/rooms/#{room["id"]}/ballot"}
                >
                  ballot
                </.link>
                <.link
                  :if={room["status"] in ["confirmed", "completed"] && @state.stage == :running}
                  href={~p"/c/#{@club.uuid}/owner/rooms/#{room["id"]}/reopen"}
                  method="post"
                >
                  reopen
                </.link>
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
            <:col :let={membership}>
              <.link
                :if={membership.role != "head"}
                href={~p"/c/#{@club.uuid}/owner/members/#{membership.user_id}/remove"}
                method="post"
              >
                remove
              </.link>
            </:col>
          </.table>
        </.section>

        <.section title="Club settings">
          <.form_for
            id="club-settings-form"
            action={~p"/c/#{@club.uuid}/owner/club"}
            description="Shown on the public club page."
          >
            <:block name={:name} type={:text} label="Club name" required value={@club.name} />
            <:block name={:city} type={:text} label="City" value={@club.city} />
            <:submit note="Takes effect immediately.">Save settings</:submit>
          </.form_for>
        </.section>
      </div>
    </Layouts.app>
    """
  end

  # GET .../owner/sessions/:session_uuid/compose — one form, one
  # dropdown per slot, PREFILLED from the auto-pair proposal; the
  # submit segment lives in the chrome (the ballot precedent)
  def compose(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.chrome
        crumbs={[
          {@club.name, ~p"/c/#{@club.uuid}"},
          {"owner", ~p"/c/#{@club.uuid}/owner"}
        ]}
        here="compose rooms"
        stage="sign-up open"
        stage_kind={:ok}
      >
      </.chrome>

      <div class="pbody">
        <.flash_banners flash={@flash} />

        <.section title="Room composition">
          <.form_for
            id="compose-rooms-form"
            action={~p"/c/#{@club.uuid}/owner/sessions/#{@session.uuid}/rooms"}
            title="Compose rooms"
            description="Prefilled with the auto-pair proposal — move anyone anywhere. Every speaker speaks exactly once; every room gets its own judge."
          >
            <:block
              :for={block <- compose_blocks(@proposal, @state.signups)}
              name={block.name}
              type={:select}
              label={block.label}
              options={block.options}
              value={block.value}
            />
            <:submit note="Rooms are created exactly as laid out here.">Make these rooms</:submit>
          </.form_for>
        </.section>
      </div>
    </Layouts.app>
    """
  end

  @sides ~w(OG OO CG CO)

  # one dropdown per slot: a judge + 8 speakers per room, prefilled
  # from the proposal; options are tonight's signups by role
  defp compose_blocks(proposal, signups) do
    speaker_options =
      for participant <- signups, participant["role"] == "speaker" do
        {participant["display_name"], participant["id"]}
      end

    judge_options =
      for participant <- signups, participant["role"] == "adjudicator" do
        {participant["display_name"], participant["id"]}
      end

    proposal
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {room, index} ->
      judge = %{
        name: "rooms[#{index}][judge]",
        label: "Room #{index} · judge",
        options: judge_options,
        value: room.judge_participant_id
      }

      speakers =
        room.teams
        |> Enum.with_index(1)
        |> Enum.flat_map(fn {[first, second], position} ->
          side = Enum.at(@sides, position - 1)

          [
            %{
              name: "rooms[#{index}][t#{position}a]",
              label: "Room #{index} · #{side} · first speaker",
              options: speaker_options,
              value: first
            },
            %{
              name: "rooms[#{index}][t#{position}b]",
              label: "Room #{index} · #{side} · second speaker",
              options: speaker_options,
              value: second
            }
          ]
        end)

      [judge | speakers]
    end)
  end

  # approved members not signed up tonight, as form options
  defp addable_members(members, signups) do
    signed = MapSet.new(signups, & &1["user_id"])

    for membership <- members,
        not MapSet.member?(signed, membership.user.node_user_id) do
      {membership.user.username, membership.user.username}
    end
  end

  defp deletable_rooms?(%{stage: :running, rooms: rooms}) when rooms != [],
    do: Enum.all?(rooms, &(&1["status"] == "pending"))

  defp deletable_rooms?(_state), do: false

  def ballot(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.chrome
        crumbs={[
          {@club.name, ~p"/c/#{@club.uuid}"},
          {"owner", ~p"/c/#{@club.uuid}/owner"}
        ]}
        here={"ballot R#{@room["id"]}"}
      >
        <:seg form={"ballot-#{@room["id"]}"} primary>Submit ballot</:seg>
      </.chrome>

      <div class="pbody">
        <.flash_banners flash={@flash} />

        <.section title={"Room R#{@room["id"]} · ballot"}>
          <Ui.ballot
            id={"ballot-#{@room["id"]}"}
            room={"R#{@room["id"]}"}
            motion={@room["Motion"] && @room["Motion"]["motion_text"]}
            teams={@teams}
            error={@error}
            action={~p"/c/#{@club.uuid}/owner/rooms/#{@room["id"]}/ballot"}
          />
        </.section>
      </div>
    </Layouts.app>
    """
  end

  defp no_open_session?(state), do: state == nil or state.stage == :done

  defp open_rooms(%{stage: :running, rooms: rooms}),
    do: Enum.reject(rooms, &(&1["status"] in ["confirmed", "completed"]))

  defp open_rooms(_state), do: []

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
