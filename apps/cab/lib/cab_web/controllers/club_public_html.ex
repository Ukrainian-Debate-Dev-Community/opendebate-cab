defmodule CabWeb.ClubPublicHTML do
  use CabWeb, :html

  import CabWeb.StandingsHTML, only: [standings_tabs: 1, standings_body: 1]

  # the club page — a profile VIEW (the owner edits the same page in
  # place at /owner)
  def show(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      club={@club}
      club_role={@club_role}
      nav_session={@nav_session}
      active="club"
    >
      <.chrome here={@club.name}>
        <:seg :if={@club_role in [:owner, :admin]} href={~p"/c/#{@club.uuid}/owner"}>
          Edit club
        </:seg>
        <:seg :if={@club_role == :public and is_nil(@current_user)} href={~p"/signin"} primary>
          Request to join
        </:seg>
        <:seg
          :if={@club_role == :public and @current_user}
          href={~p"/c/#{@club.uuid}/join"}
          primary
        >
          Request to join
        </:seg>
      </.chrome>

      <div class="pbody">
        <.flash_banners flash={@flash} />

        <.section title="About" pad>
          <b id="club-name">{@club.name}</b>{if @club.city, do: " · #{@club.city}"}
          <p>
            {length(@members)} member{if length(@members) != 1, do: "s"}{if head_name(@members),
              do: " · head: #{head_name(@members)}"}
          </p>
          <p :if={@club.description}>{@club.description}</p>
          <p :if={@club.meeting_info}>Meetings: {@club.meeting_info}</p>
          <p :if={@club.contacts}>Contacts: {@club.contacts}</p>
        </.section>

        <.section title="Recent sessions">
          <.table id="recent-sessions" rows={@recent} empty="No completed sessions yet.">
            <:col :let={row} label="Date">
              <.link href={~p"/c/#{@club.uuid}/s/#{row.session_uuid}"}>
                {Calendar.strftime(row.date, "%-d %b %Y")}
              </.link>
            </:col>
            <:col :let={row} label="Session">{row.name}</:col>
            <:col :let={row} label="Progress">
              {if row.winner, do: "won by #{row.winner}", else: "finished"}
            </:col>
          </.table>
        </.section>

        <.section title="Standings" pad>
          Per-session engine standings live under
          <.link href={~p"/c/#{@club.uuid}/standings/teams"}>Standings</.link>
          in the sidenav.
        </.section>
      </div>
    </Layouts.app>
    """
  end

  # teams · speakers · judges, scoped to the club (Clubs is global-only)
  def standings(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      club={@club}
      club_role={@club_role}
      nav_session={@nav_session}
      active="standings"
    >
      <.chrome crumbs={[{@club.name, ~p"/c/#{@club.uuid}"}]} here="standings"></.chrome>
      <.standings_tabs base={"/c/#{@club.uuid}/standings"} active={@tab} clubs_tab={false} />

      <div class="pbody">
        <.flash_banners flash={@flash} />
        <.standings_body tab={@tab} scope={@scope} rows={@rows} club={@club} />
      </div>
    </Layouts.app>
    """
  end

  # the join-request FORM: two required answers the head reads in
  # Requests — about me + contact
  def join(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      club={@club}
      club_role={@club_role}
      nav_session={@nav_session}
      active="club"
    >
      <.chrome crumbs={[{@club.name, ~p"/c/#{@club.uuid}"}]} here="join"></.chrome>

      <div class="pbody">
        <.flash_banners flash={@flash} />

        <.section title="Join request">
          <.form_for
            id="join-request-form"
            action={~p"/c/#{@club.uuid}/join"}
            title={"Join #{@club.name}"}
            description="The club head reads your answers before approving."
            errors={@errors}
          >
            <:block
              name={:message}
              type={:longtext}
              label="About me"
              required
              value={@message}
              hint="Who you are and why you want to debate here."
            />
            <:block
              name={:contact}
              type={:text}
              label="Contact"
              required
              value={@contact}
              hint="Telegram, phone or email the head can reach you at."
            />
            <:submit note="Lands in the head's Requests with your answers.">
              Send request
            </:submit>
          </.form_for>
        </.section>
      </div>
    </Layouts.app>
    """
  end

  # list_members/1 orders head first
  defp head_name([%{user: user} | _rest]), do: user.name || user.username
  defp head_name([]), do: nil
end
