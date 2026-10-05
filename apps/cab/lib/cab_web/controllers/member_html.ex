defmodule CabWeb.MemberHTML do
  use CabWeb, :html

  # the sessions archive, member path: previous progress only; rows
  # open the session page (the live session lives under Rooms)
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
      <.chrome crumbs={[{@club.name, ~p"/c/#{@club.uuid}"}]} here="sessions"></.chrome>

      <div class="pbody">
        <.flash_banners flash={@flash} />
        <.archive_section club={@club} archive={@archive} />
      </div>
    </Layouts.app>
    """
  end

  @doc "Previous sessions — progress; shared by the member and owner paths."
  attr :club, :any, required: true
  attr :archive, :list, required: true

  def archive_section(assigns) do
    ~H"""
    <.section title="Previous sessions — progress">
      <.table id="sessions-archive" rows={@archive} empty="No finished sessions yet.">
        <:col :let={row} label="Session">
          <.link href={~p"/c/#{@club.uuid}/s/#{row.session_uuid}"}>{row.name}</.link>
          <.sub>{Calendar.strftime(row.date, "%-d %b %Y")}</.sub>
        </:col>
        <:col :let={row} label="Progress">
          {if row.winner, do: "won by #{row.winner}", else: "finished"}
        </:col>
      </.table>
    </.section>
    """
  end

  # the roster, member path (the owner path adds requests + revoke)
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
          </.table>
        </.section>
      </div>
    </Layouts.app>
    """
  end

  # GET .../member/sessions/:session_uuid/register — the ONE
  # registration entry: role pills, POSTing to the signups action
  def register(assigns) do
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
        crumbs={[{@club.name, ~p"/c/#{@club.uuid}"}]}
        here="register — sign-ups open"
      >
      </.chrome>

      <div class="pbody">
        <.flash_banners flash={@flash} />

        <.section title="Registration">
          <.form_for
            id="register-form"
            action={~p"/c/#{@club.uuid}/member/sessions/#{@session.uuid}/signups"}
            title="Register for tonight"
            description="One registration per member — pick your role."
          >
            <:block
              name={:as}
              type={:select}
              label="I am tonight"
              required
              value="speak"
              options={[{"Speaker", "speak"}, {"Judge", "judge"}]}
            />
            <:submit note="You appear in tonight's list right away.">Register</:submit>
          </.form_for>
        </.section>
      </div>
    </Layouts.app>
    """
  end
end
