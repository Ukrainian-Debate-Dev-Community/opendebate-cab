defmodule CabWeb.OwnerHTML do
  use CabWeb, :html

  # this view's ballot/1 is the page; the kit component stays qualified
  import CabWeb.Ui, except: [ballot: 1]
  import CabWeb.MemberHTML, only: [archive_section: 1]
  alias Cab.Links

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
        <:seg form="open-session-form" primary={is_nil(@live)}>Open new session</:seg>
        <:seg form="club-profile-form" primary={not is_nil(@live)}>Save</:seg>
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
            <:block
              name={:is_private}
              type={:select}
              label="Standings"
              value={if @club.is_private, do: "true", else: "false"}
              options={[{"public", "false"}, {"members only", "true"}]}
              hint="Members only also keeps the club out of the global standings. Everything else stays public."
            />
          </.form_for>
        </.section>

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
          {"club", ~p"/c/#{@club.uuid}/owner"}
        ]}
        here={"#{@state.event["name"]} — #{stage_words(@state.stage)}"}
      >
        <:seg :if={@state.stage == :signup} form="allocator-form" primary>
          Start session
        </:seg>
        <:seg :if={@state.stage == :closed} form="allocator-form" primary>
          Make these rooms
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
          :if={@state.stage == :running && deletable_rooms?(@state)}
          href={~p"/c/#{@club.uuid}/owner/sessions/#{@current.uuid}/reopen-registration"}
          method="post"
        >
          Reopen registration
        </:seg>
        <:seg
          :if={@state.stage == :running}
          href={~p"/c/#{@club.uuid}/owner/sessions/#{@current.uuid}/finish"}
          method="post"
          primary
        >
          Finish session
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
              Previous sessions live on the <.link href={~p"/c/#{@club.uuid}/owner"}>club page</.link>.
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
    <.section title={"Allocation — #{Cab.Sessions.room_count(@state.signups)} room(s), count automatic"}>
      <div class="pad">
        <p>
          The room count follows the speaker count; <b>nobody is placed
          automatically</b>
          — drag people from the tray into the slots, then <b>Start session</b>
          closes registration and opens these rooms.
        </p>
      </div>
      <.dnd_table
        id="allocator-form"
        action={~p"/c/#{@club.uuid}/owner/sessions/#{@current.uuid}/start"}
        rooms={Cab.Sessions.room_count(@state.signups)}
        tray={dnd_tray(@state.signups)}
      />
    </.section>
    """
  end

  defp rooms_block(%{state: %{stage: :closed}} = assigns) do
    ~H"""
    <.section title={"Allocation — #{Cab.Sessions.room_count(@state.signups)} room(s), count automatic"}>
      <div class="pad">
        <p>
          {attendance_line(@state.signups)} <b>Nobody is placed automatically</b> —
          drag people from the tray into the slots.
        </p>
      </div>
      <.dnd_table
        id="allocator-form"
        action={~p"/c/#{@club.uuid}/owner/sessions/#{@current.uuid}/rooms"}
        rooms={Cab.Sessions.room_count(@state.signups)}
        tray={dnd_tray(@state.signups)}
      />
    </.section>
    """
  end

  defp rooms_block(assigns) do
    ~H"""
    <.section title="Rooms">
      <.table id="session-rooms" rows={@state.rooms}>
        <:col :let={room} class="rank">
          <.link href={~p"/c/#{@club.uuid}/s/#{@current.uuid}/rooms/#{room["id"]}"}>
            R{room["id"]}
          </.link>
        </:col>
        <:col
          :let={room}
          :for={{label, position, side_class} <- sides()}
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
            href={~p"/c/#{@club.uuid}/s/#{@current.uuid}/rooms/#{room["id"]}/ballot"}
          >
            ballot
          </.link>
          <.link
            :if={room["status"] in ["completed", "confirmed"] && @state.stage == :running}
            href={~p"/c/#{@club.uuid}/s/#{@current.uuid}/rooms/#{room["id"]}/ballot"}
          >
            edit ballot
          </.link>
        </:col>
      </.table>
    </.section>

    <.section :if={open_rooms(@state) != []} title="Motions" pad>
      Each room's motion is set on its page — open a room (R#) in the
      table above to publish the motion, infoslide and keyword.
    </.section>
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
    rooms = Cab.Sessions.room_count(signups)

    "#{speakers} speakers + #{judges} judge#{if judges != 1, do: "s"} checked in → #{rooms} room#{if rooms != 1, do: "s"}."
  end

  defp deletable_rooms?(%{stage: :running, rooms: rooms}) when rooms != [],
    do: Enum.all?(rooms, &(&1["status"] == "pending"))

  defp deletable_rooms?(_state), do: false

  defp open_rooms(%{stage: :running, rooms: rooms}),
    do: Enum.reject(rooms, &(&1["status"] in ["confirmed", "completed"]))

  defp open_rooms(_state), do: []
end
