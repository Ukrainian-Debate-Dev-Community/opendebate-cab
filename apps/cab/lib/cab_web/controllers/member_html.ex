defmodule CabWeb.MemberHTML do
  use CabWeb, :html

  @doc "Previous sessions — progress; shared by the club and owner pages."
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

  # the roster, member-gated (the owner path adds requests + revoke)
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
end
