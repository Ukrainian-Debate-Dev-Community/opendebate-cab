defmodule CabWeb.OwnerHTML do
  use CabWeb, :html

  # this view's ballot/1 is the page; the kit component stays qualified
  import CabWeb.Ui, except: [ballot: 1]
  alias Cab.Links
  alias CabWeb.Ui

  @sides [{"OG", 1, "s-og"}, {"OO", 2, "s-oo"}, {"CG", 3, "s-cg"}, {"CO", 4, "s-co"}]

  # P8 — the owner console: stage-driven chrome + section nav; the
  # tab only chooses WHICH section is shown, actions never leave the
  # chrome.
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
          href={~p"/c/#{@club.uuid}/owner/sessions/#{@current.uuid}/close-signups"}
          method="post"
          primary
        >
          Close sign-ups
        </:seg>
        <:seg
          :if={@state && @state.stage == :closed}
          href={~p"/c/#{@club.uuid}/owner/sessions/#{@current.uuid}/compose"}
        >
          Compose rooms
        </:seg>
        <:seg
          :if={@state && @state.stage == :closed}
          href={~p"/c/#{@club.uuid}/owner/sessions/#{@current.uuid}/rooms"}
          method="post"
          primary
        >
          Make rooms
        </:seg>
        <:seg
          :if={@state && @state.stage == :closed}
          href={~p"/c/#{@club.uuid}/owner/sessions/#{@current.uuid}/reopen-signups"}
          method="post"
        >
          Reopen sign-ups
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
          :if={@state && @state.stage in [:signup, :closed, :running]}
          href={~p"/c/#{@club.uuid}/owner/sessions/#{@current.uuid}/cancel"}
          method="post"
          quiet
        >
          Cancel session
        </:seg>
      </.chrome>

      <.subnav
        id="owner-subnav"
        active={@tab}
        tabs={[
          %{
            key: "registration",
            label: "Registration",
            href: ~p"/c/#{@club.uuid}/owner?tab=registration",
            count: length(@links)
          },
          %{
            key: "requests",
            label: "Requests",
            href: ~p"/c/#{@club.uuid}/owner?tab=requests",
            count: length(@join_requests)
          },
          %{key: "tonight", label: "Tonight", href: ~p"/c/#{@club.uuid}/owner?tab=tonight"},
          %{key: "rooms", label: "Rooms", href: ~p"/c/#{@club.uuid}/owner?tab=rooms"},
          %{key: "members", label: "Members", href: ~p"/c/#{@club.uuid}/owner?tab=members"},
          %{key: "settings", label: "Settings", href: ~p"/c/#{@club.uuid}/owner?tab=settings"}
        ]}
      />

      <div class="pbody">
        <.flash_banners flash={@flash} />
        <%= case @tab do %>
          <% "registration" -> %>
            {registration_tab(assigns)}
          <% "requests" -> %>
            {requests_tab(assigns)}
          <% "tonight" -> %>
            {tonight_tab(assigns)}
          <% "rooms" -> %>
            {rooms_tab(assigns)}
          <% "members" -> %>
            {members_tab(assigns)}
          <% "settings" -> %>
            {settings_tab(assigns)}
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  # ---------------------------------------------------------------
  # Registration — guest links + registrations (M6 surface)
  # ---------------------------------------------------------------

  defp registration_tab(%{current: nil} = assigns) do
    ~H"""
    <.section title="Registration" pad>
      No session is open.
      <p>Open a session — guest registration comes with it.</p>
    </.section>
    """
  end

  defp registration_tab(%{state: nil} = assigns) do
    ~H"""
    <.section title="Registration" pad>
      The session is unavailable right now.
      <p>Try again in a moment.</p>
    </.section>
    """
  end

  defp registration_tab(assigns) do
    ~H"""
    <.copy_banner id="shared-registration-url" url={url(~p"/r/#{@current.uuid}")}>
      Share to register without an account
    </.copy_banner>

    <.section title={"Guest registrations · #{length(@links)}"}>
      <div class="pad">
        <p>
          Personal links below are each guest's ONLY access — share one only with its guest.
        </p>
      </div>
      <.table id="guest-links" rows={@links} empty="No guest links issued yet.">
        <:col :let={link} label="Name">
          {link.user.name}
          <.sub>guest · {link.user.username}</.sub>
        </:col>
        <:col :let={link} label="Role">{Links.role_in(link, @state.signups) || "—"}</:col>
        <:col :let={link} label="Personal link" code>
          {url(~p"/l/#{link.code}")}
        </:col>
        <:col :let={link}>
          <.copy text={url(~p"/l/#{link.code}")} />
        </:col>
        <:col :let={link}>
          <.link href={~p"/c/#{@club.uuid}/owner/links/#{link.id}/revoke"} method="post">
            revoke
          </.link>
        </:col>
      </.table>
    </.section>

    <.section :if={@state.stage == :signup} title="Issue a link by hand">
      <.form_for
        id="issue-link-form"
        action={~p"/c/#{@club.uuid}/owner/sessions/#{@current.uuid}/links"}
        description="Register a guest by hand — their personal link lands in the banner above."
      >
        <:block name={:name} type={:text} label="Guest name" required />
        <:block
          name={:as}
          type={:select}
          label="Signs up to"
          value="speak"
          options={[{"speak", "speak"}, {"judge", "judge"}]}
        />
        <:submit note="The guest appears in tonight's list right away.">Create link</:submit>
      </.form_for>
    </.section>
    """
  end

  # ---------------------------------------------------------------
  # Requests — join approvals
  # ---------------------------------------------------------------

  defp requests_tab(assigns) do
    ~H"""
    <.section title="Join requests">
      <.table
        id="join-requests"
        rows={@join_requests}
        row_id={&"join-request-#{&1.id}"}
        empty="No pending requests."
      >
        <:col :let={request} label="Who">
          {request.user.username}
          <.sub>signed-in user{if request.user.name, do: " · #{request.user.name}"}</.sub>
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
    """
  end

  # ---------------------------------------------------------------
  # Tonight — attendance (guests cross-reference Registration)
  # ---------------------------------------------------------------

  defp tonight_tab(%{current: current, state: state} = assigns)
       when is_nil(current) or is_nil(state) do
    ~H"""
    <.section title="Open a session">
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
        <:block
          names={[:date, :time]}
          type={:datetime}
          label="Date and start time"
          hint="Optional — when the session is planned to start (UTC)."
        />
        <:submit note="Members get the sign-up right away.">Open session</:submit>
      </.form_for>
    </.section>
    """
  end

  defp tonight_tab(assigns) do
    assigns = Map.put(assigns, :guest_user_ids, guest_user_ids(assigns.links))

    ~H"""
    <.section title={"Signed up · #{signed_up_counts(@state.signups)}"}>
      <.table id="session-signups" rows={@state.signups} empty="Nobody signed up yet.">
        <:col :let={participant} label="Who">
          {participant["display_name"]}
          <.sub :if={participant["user_id"] in @guest_user_ids}>
            guest — see Registration
          </.sub>
        </:col>
        <:col :let={participant} label="Role">{participant["role"]}</:col>
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
        <:submit note="They appear in tonight's list right away.">Add</:submit>
      </.form_for>
    </.section>
    """
  end

  # ---------------------------------------------------------------
  # Rooms — composition, the draw, ballots, motions
  # ---------------------------------------------------------------

  defp rooms_tab(%{current: current, state: state} = assigns)
       when is_nil(current) or is_nil(state) do
    ~H"""
    <.section title="Rooms" pad>
      No session is open.
      <p>Rooms appear once a session runs.</p>
    </.section>
    """
  end

  defp rooms_tab(%{state: %{stage: :signup}} = assigns) do
    ~H"""
    <.section title="Rooms" pad>
      Rooms are composed after sign-ups close.
      <p>Close sign-ups from the chrome — composition works from the final attendance.</p>
    </.section>
    """
  end

  defp rooms_tab(%{state: %{stage: :closed}} = assigns) do
    ~H"""
    <.banner
      kind={:info}
      href={~p"/c/#{@club.uuid}/owner/sessions/#{@current.uuid}/compose"}
      link="Compose rooms →"
    >
      {attendance_line(@state.signups)}
    </.banner>

    <.section title="Rooms" pad>
      No rooms yet.
      <p>
        <b>Make rooms</b> pairs automatically; <b>Compose rooms</b> opens the drag-and-drop table.
      </p>
    </.section>
    """
  end

  defp rooms_tab(assigns) do
    assigns = Map.put(assigns, :sides, @sides)

    ~H"""
    <.section title="Rooms">
      <.table id="session-rooms" rows={@state.rooms}>
        <:col :let={room} class="rank">R{room["id"]}</:col>
        <:col
          :let={room}
          :for={{label, position, side_class} <- @sides}
          label={label}
          class={"side #{side_class}"}
        >
          {team_label(room, position)}
        </:col>
        <:col :let={room} label="Judge">{judge_name(room, @state.signups)}</:col>
        <:col :let={room} label="Ballot">
          <.tag kind={room_kind(room["status"])}>{room_status_label(room["status"])}</.tag>
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
    """
  end

  # ---------------------------------------------------------------
  # Members / Settings
  # ---------------------------------------------------------------

  defp members_tab(assigns) do
    ~H"""
    <.section title={"Members · #{length(@members)}"}>
      <.table id="members-list" rows={@members} empty="No members yet.">
        <:col :let={membership} label="Member">
          {membership.user.username}
          <.sub :if={membership.user.name}>{membership.user.name}</.sub>
        </:col>
        <:col :let={membership} label="Role">
          <%= if membership.role == "head" do %>
            <.tag kind={:ok}>head</.tag>
          <% else %>
            {membership.role}
          <% end %>
        </:col>
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
    """
  end

  defp settings_tab(assigns) do
    ~H"""
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
    """
  end

  # GET .../owner/sessions/:session_uuid/compose — the drag-and-drop
  # allocation page: tray of signed-up chips over droppable room
  # slots; the submit segment lives in the chrome (the ballot
  # precedent) and "+ room" reloads with ?rooms=N (plain REST)
  def compose(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.chrome
        crumbs={[
          {@club.name, ~p"/c/#{@club.uuid}"},
          {"owner", ~p"/c/#{@club.uuid}/owner?tab=rooms"}
        ]}
        here="compose rooms"
        stage="sign-ups closed"
        stage_kind={:warn}
      >
        <:seg
          :if={@rooms < @max_rooms}
          href={~p"/c/#{@club.uuid}/owner/sessions/#{@session.uuid}/compose?rooms=#{@rooms + 1}"}
        >
          + room
        </:seg>
        <:seg form="compose-rooms-form" primary>Make these rooms</:seg>
      </.chrome>

      <div class="pbody">
        <.flash_banners flash={@flash} />

        <.section title="Room composition">
          <.dnd_table
            id="compose-rooms-form"
            action={~p"/c/#{@club.uuid}/owner/sessions/#{@session.uuid}/rooms"}
            rooms={@rooms}
            tray={dnd_tray(@state.signups)}
          />
        </.section>
      </div>
    </Layouts.app>
    """
  end

  def ballot(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.chrome
        crumbs={[
          {@club.name, ~p"/c/#{@club.uuid}"},
          {"owner", ~p"/c/#{@club.uuid}/owner?tab=rooms"}
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

  # ---------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------

  # tray chips from tonight's signups: speakers first, judges last
  defp dnd_tray(signups) do
    for participant <- Enum.sort_by(signups, &(&1["role"] == "adjudicator")) do
      %{
        id: participant["id"],
        name: participant["display_name"],
        kind: if(participant["role"] == "adjudicator", do: "judge", else: "spk")
      }
    end
  end

  # approved members not signed up tonight, as form options
  defp addable_members(members, signups) do
    signed = MapSet.new(signups, & &1["user_id"])

    for membership <- members,
        not MapSet.member?(signed, membership.user.node_user_id) do
      {membership.user.username, membership.user.username}
    end
  end

  defp guest_user_ids(links) do
    for link <- links, is_integer(link.user.node_user_id), into: MapSet.new() do
      link.user.node_user_id
    end
  end

  defp signed_up_counts(signups) do
    speakers = Enum.count(signups, &(&1["role"] == "speaker"))
    judges = Enum.count(signups, &(&1["role"] == "adjudicator"))
    "#{speakers} speaker#{if speakers != 1, do: "s"} · #{judges} judge#{if judges != 1, do: "s"}"
  end

  defp attendance_line(signups) do
    speakers = Enum.count(signups, &(&1["role"] == "speaker"))
    judges = Enum.count(signups, &(&1["role"] == "adjudicator"))
    rooms = max(div(speakers, 8), 1)

    "#{speakers} speakers + #{judges} judge#{if judges != 1, do: "s"} checked in → #{rooms} room#{if rooms != 1, do: "s"}."
  end

  # the team at a side position; a 1-speaker team is marked (iron)
  defp team_label(room, position) do
    case Enum.find(room["RoomTeams"] || [], &(&1["position"] == position)) do
      nil ->
        "—"

      room_team ->
        name = get_in(room_team, ["Team", "name"]) || "—"
        if iron_team?(room_team), do: "#{name} (iron)", else: name
    end
  end

  defp iron_team?(room_team) do
    (room_team["RoomSpeakers"] || [])
    |> Enum.map(&get_in(&1, ["EventParticipant", "id"]))
    |> Enum.uniq()
    |> length() == 1
  end

  defp judge_name(room, signups) do
    chair = Enum.find(room["RoomAdjudicators"] || [], &(&1["role"] == "chair"))

    with %{} <- chair,
         participant_id when not is_nil(participant_id) <-
           get_in(chair, ["EventParticipant", "id"]) do
      get_in(chair, ["EventParticipant", "display_name"]) ||
        Enum.find_value(signups, &(&1["id"] == participant_id && &1["display_name"])) || "—"
    else
      _ -> "—"
    end
  end

  defp deletable_rooms?(%{stage: :running, rooms: rooms}) when rooms != [],
    do: Enum.all?(rooms, &(&1["status"] == "pending"))

  defp deletable_rooms?(_state), do: false

  defp no_open_session?(state), do: state == nil or state.stage == :done

  defp open_rooms(%{stage: :running, rooms: rooms}),
    do: Enum.reject(rooms, &(&1["status"] in ["confirmed", "completed"]))

  defp open_rooms(_state), do: []

  defp stage_label(nil), do: "no session"
  defp stage_label(%{stage: :signup}), do: "sign-up open"
  defp stage_label(%{stage: :closed}), do: "sign-ups closed"
  defp stage_label(%{stage: :running}), do: "running"
  defp stage_label(%{stage: :done}), do: "no session"

  defp stage_kind(nil), do: :off
  defp stage_kind(%{stage: :signup}), do: :ok
  defp stage_kind(%{stage: :closed}), do: :warn
  defp stage_kind(%{stage: :running}), do: :warn
  defp stage_kind(%{stage: :done}), do: :off

  defp room_kind(status) when status in ["confirmed", "completed"], do: :ok
  defp room_kind("pending"), do: :mut
  defp room_kind(_status), do: :warn

  defp room_status_label("confirmed"), do: "confirmed"
  defp room_status_label("completed"), do: "completed"
  defp room_status_label("judging"), do: "waiting"
  defp room_status_label("pending"), do: "waiting"
  defp room_status_label(status), do: status
end
