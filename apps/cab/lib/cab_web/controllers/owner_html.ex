defmodule CabWeb.OwnerHTML do
  use CabWeb, :html

  # this view's ballot/1 is the page; the kit component stays qualified
  import CabWeb.Ui, except: [ballot: 1]
  import CabWeb.MemberHTML, only: [archive_section: 1]
  alias Cab.Links
  alias CabWeb.Ui

  @sides [{"OG", 1, "s-og"}, {"OO", 2, "s-oo"}, {"CG", 3, "s-cg"}, {"CO", 4, "s-co"}]

  # ---------------------------------------------------------------
  # The club page, owner path: edit-in-place (Save in the chrome)
  # ---------------------------------------------------------------

  def club(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      club={@club}
      club_role={@club_role}
      nav_session={@nav_session}
      active="club"
    >
      <.chrome crumbs={[{@club.name, ~p"/c/#{@club.uuid}"}]} here="edit">
        <:seg href={~p"/c/#{@club.uuid}"} quiet>View as public</:seg>
        <:seg form="club-profile-form" primary>Save</:seg>
      </.chrome>

      <div class="pbody">
        <.flash_banners flash={@flash} />

        <.section title="Club profile">
          <.form_for
            id="club-profile-form"
            action={~p"/c/#{@club.uuid}/owner/club"}
            description="Exactly what visitors read on the club page."
          >
            <:block name={:name} type={:text} label="Club name" required value={@club.name} />
            <:block name={:city} type={:text} label="City" value={@club.city} />
            <:block
              name={:meeting_info}
              type={:text}
              label="Meetings"
              value={@club.meeting_info}
              hint="When and where the club meets, e.g. Thursdays 18:30, Hrushevskoho 4."
            />
            <:block
              name={:description}
              type={:longtext}
              label="About the club"
              value={@club.description}
            />
            <:block
              name={:contacts}
              type={:text}
              label="Contacts"
              value={@club.contacts}
              hint="Telegram, email — how newcomers reach the club."
            />
          </.form_for>
        </.section>
      </div>
    </Layouts.app>
    """
  end

  # ---------------------------------------------------------------
  # Sessions archive, owner path: previous progress + Open new
  # session (the chrome's gold segment submits the form below)
  # ---------------------------------------------------------------

  def sessions(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      club={@club}
      club_role={@club_role}
      nav_session={@nav_session}
      active="sessions"
    >
      <.chrome crumbs={[{@club.name, ~p"/c/#{@club.uuid}"}]} here="sessions">
        <:seg form="open-session-form" primary>Open new session</:seg>
      </.chrome>

      <div class="pbody">
        <.flash_banners flash={@flash} />

        <.banner
          :if={@live}
          kind={:info}
          href={~p"/c/#{@club.uuid}/owner/s/#{@live.uuid}"}
          link="Open →"
        >
          The current session lives under Rooms.
        </.banner>

        <.archive_section club={@club} archive={@archive} />

        <.section title="Open a session">
          <.form_for
            id="open-session-form"
            action={~p"/c/#{@club.uuid}/owner/sessions"}
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
          </.form_for>
        </.section>
      </div>
    </Layouts.app>
    """
  end

  # ---------------------------------------------------------------
  # Members page, owner path: requests (the join form's answers) +
  # roster with revoke
  # ---------------------------------------------------------------

  def members(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      club={@club}
      club_role={@club_role}
      nav_session={@nav_session}
      active="members"
    >
      <.chrome crumbs={[{@club.name, ~p"/c/#{@club.uuid}"}]} here="members"></.chrome>

      <div class="pbody">
        <.flash_banners flash={@flash} />

        <.section title={"Join requests · #{length(@join_requests)}"}>
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
            <:col :let={request} label="About them">
              {request.message || "—"}
              <.sub :if={request.contact}>contact: {request.contact}</.sub>
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

        <.section title={"Members · #{length(@members)}"}>
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
      </div>
    </Layouts.app>
    """
  end

  # ---------------------------------------------------------------
  # The interim owner session surface (M8a): the M7 Registration +
  # Tonight + Rooms content on one page, stage-driven chrome. M8b
  # re-behaves this into the owner play flow.
  # ---------------------------------------------------------------

  def session(assigns) do
    assigns = Map.put(assigns, :sides, @sides)

    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      club={@club}
      club_role={@club_role}
      nav_session={@nav_session}
      active="rooms"
    >
      <.chrome
        crumbs={[
          {@club.name, ~p"/c/#{@club.uuid}"},
          {"sessions", ~p"/c/#{@club.uuid}/owner/sessions"}
        ]}
        here={"#{@state.event["name"]} — #{stage_words(@state)}"}
      >
        <:seg
          :if={@state.stage == :signup}
          href={~p"/c/#{@club.uuid}/owner/sessions/#{@current.uuid}/close-signups"}
          method="post"
          primary
        >
          Close sign-ups
        </:seg>
        <:seg
          :if={@state.stage == :closed}
          href={~p"/c/#{@club.uuid}/owner/sessions/#{@current.uuid}/compose"}
        >
          Compose rooms
        </:seg>
        <:seg
          :if={@state.stage == :closed}
          href={~p"/c/#{@club.uuid}/owner/sessions/#{@current.uuid}/rooms"}
          method="post"
          primary
        >
          Make rooms
        </:seg>
        <:seg
          :if={@state.stage == :closed}
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
          :if={@state.stage == :running}
          href={~p"/c/#{@club.uuid}/owner/sessions/#{@current.uuid}/finish"}
          method="post"
          primary
        >
          Finish session
        </:seg>
        <:seg
          :if={@state.stage in [:signup, :closed, :running]}
          href={~p"/c/#{@club.uuid}/owner/sessions/#{@current.uuid}/cancel"}
          method="post"
          quiet
        >
          Cancel session
        </:seg>
      </.chrome>

      <div class="pbody">
        <.flash_banners flash={@flash} />

        <%= if @state.stage == :done do %>
          <.section title="Session" pad>
            This session is finished — results live on the <.link href={
              ~p"/c/#{@club.uuid}/s/#{@current.uuid}"
            }>session page</.link>.
            <p>
              Previous sessions live under <.link href={~p"/c/#{@club.uuid}/owner/sessions"}>Sessions</.link>.
            </p>
          </.section>
        <% else %>
          {registration_block(assigns)}
          {signups_block(assigns)}
          {rooms_block(assigns)}
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  # --- registration (guest links), the M7 Registration tab content

  defp registration_block(%{state: %{stage: :signup}} = assigns) do
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

    <.section title="Issue a link by hand">
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

  defp registration_block(%{links: links} = assigns) when links != [] do
    ~H"""
    <.section title={"Guest registrations · #{length(@links)}"}>
      <.table id="guest-links" rows={@links}>
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
    """
  end

  defp registration_block(assigns), do: ~H""

  # --- signed up, the M7 Tonight tab content

  defp signups_block(assigns) do
    assigns = Map.put(assigns, :guest_user_ids, guest_user_ids(assigns.links))

    ~H"""
    <.section title={"Signed up · #{signed_up_counts(@state.signups)}"}>
      <.table id="session-signups" rows={@state.signups} empty="Nobody signed up yet.">
        <:col :let={participant} label="Who">
          {participant["display_name"]}
          <.sub :if={participant["user_id"] in @guest_user_ids}>
            guest — personal link above
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

  # --- rooms, the M7 Rooms tab content

  defp rooms_block(%{state: %{stage: :signup}} = assigns) do
    ~H"""
    <.section title="Rooms" pad>
      Rooms are composed after sign-ups close.
      <p>Close sign-ups from the chrome — composition works from the final attendance.</p>
    </.section>
    """
  end

  defp rooms_block(%{state: %{stage: :closed}} = assigns) do
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

  defp rooms_block(assigns) do
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
        <:col :let={room} label="Ballot" class="st">
          {room_status_words(room["status"])}
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

  # GET .../owner/sessions/:session_uuid/compose — the drag-and-drop
  # allocation page: tray of signed-up chips over droppable room
  # slots; the submit segment lives in the chrome (the ballot
  # precedent) and "+ room" reloads with ?rooms=N (plain REST)
  def compose(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      club={@club}
      club_role={@club_role}
      nav_session={@nav_session}
      active="rooms"
    >
      <.chrome
        crumbs={[
          {@club.name, ~p"/c/#{@club.uuid}"},
          {@state.event["name"], ~p"/c/#{@club.uuid}/owner/s/#{@session.uuid}"}
        ]}
        here="compose rooms — sign-ups closed"
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
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      club={@club}
      club_role={@club_role}
      nav_session={@nav_session}
      active="rooms"
    >
      <.chrome
        crumbs={[
          {@club.name, ~p"/c/#{@club.uuid}"},
          {"session", ~p"/c/#{@club.uuid}/owner/s/#{@session.uuid}"}
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

  defp open_rooms(%{stage: :running, rooms: rooms}),
    do: Enum.reject(rooms, &(&1["status"] in ["confirmed", "completed"]))

  defp open_rooms(_state), do: []

  # status written out as words — no pills anywhere
  defp stage_words(%{stage: :signup}), do: "sign-ups open"
  defp stage_words(%{stage: :closed}), do: "sign-ups closed"
  defp stage_words(%{stage: :running}), do: "running"
  defp stage_words(%{stage: :done}), do: "finished"

  defp room_status_words("confirmed"), do: "ballot in"
  defp room_status_words("completed"), do: "ballot in"
  defp room_status_words("judging"), do: "waiting for the ballot"
  defp room_status_words("pending"), do: "waiting for the ballot"
  defp room_status_words(status), do: status
end
