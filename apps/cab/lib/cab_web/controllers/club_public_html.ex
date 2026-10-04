defmodule CabWeb.ClubPublicHTML do
  use CabWeb, :html

  # P4 — the club's public face
  def show(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.chrome
        account
        current_user={@current_user}
        crumbs={[{@club.name, ~p"/c/#{@club.uuid}"}]}
        stage="recruiting"
        stage_kind={:ok}
      >
        <:seg href={~p"/c/#{@club.uuid}/standings"}>Standings</:seg>
        <:seg :if={@club_role in [:member, :owner]} href={~p"/c/#{@club.uuid}/member"}>
          Member area
        </:seg>
        <:seg :if={@club_role == :owner} href={~p"/c/#{@club.uuid}/owner"}>
          Owner console
        </:seg>
        <:seg :if={@club_role == :public and is_nil(@current_user)} href={~p"/signin"} primary>
          Request to join
        </:seg>
        <:seg
          :if={@club_role == :public and @current_user}
          href={~p"/c/#{@club.uuid}/join"}
          method="post"
          primary
        >
          Request to join
        </:seg>
      </.chrome>

      <div class="pbody">
        <.flash_banners flash={@flash} />

        <.section title="Club" pad>
          <b id="club-name">{@club.name}</b>{if @club.city, do: " · #{@club.city}"}
          <p>
            {length(@members)} member{if length(@members) != 1, do: "s"}{if head_name(@members),
              do: " · head: #{head_name(@members)}"}
          </p>
        </.section>

        <.section title="Recent sessions">
          <.table id="recent-sessions" rows={@recent} empty="No completed sessions yet.">
            <:col :let={row} label="Date">
              <.link href={~p"/c/#{@club.uuid}/s/#{row.session_uuid}"}>
                {Calendar.strftime(row.date, "%-d %b %Y")}
              </.link>
            </:col>
            <:col :let={row} label="Session">{row.name}</:col>
            <:col :let={row} label="Winner">{row.winner || "—"}</:col>
          </.table>
        </.section>

        <.section title="Top members">
          <.table id="top-members" rows={@top_members} rank empty="No results yet.">
            <:col :let={row} label="Member">{row.name}</:col>
            <:col :let={row} label="Wins" num>{row.wins}</:col>
          </.table>
          <div class="pad">
            <.link href={~p"/c/#{@club.uuid}/standings"}>Full standings →</.link>
          </div>
        </.section>
      </div>
    </Layouts.app>
    """
  end

  # P7 — the club standings
  def standings(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.chrome
        account
        current_user={@current_user}
        crumbs={[{@club.name, ~p"/c/#{@club.uuid}"}]}
        here="standings"
      >
      </.chrome>

      <div class="pbody">
        <.flash_banners flash={@flash} />

        <.section title="Members">
          <.table id="standings-members" rows={@members} rank empty="No results yet.">
            <:col :let={row} label="Member">{row.name}</:col>
            <:col :let={row} label="Played" num>{row.played}</:col>
            <:col :let={row} label="Wins" num>{row.wins}</:col>
            <:col :let={row} label="Win rate" num>{row.win_rate}%</:col>
          </.table>
        </.section>

        <.section title="Session winners">
          <.table id="session-winners" rows={@winners} empty="No completed sessions yet.">
            <:col :let={row} label="Date">
              <.link href={~p"/c/#{@club.uuid}/s/#{row.session_uuid}"}>
                {Calendar.strftime(row.date, "%-d %b %Y")}
              </.link>
            </:col>
            <:col :let={row} label="Session">{row.name}</:col>
            <:col :let={row} label="Winner">{row.winner || "—"}</:col>
          </.table>
        </.section>
      </div>
    </Layouts.app>
    """
  end

  # list_members/1 orders head first
  defp head_name([%{user: user} | _rest]), do: user.name || user.username
  defp head_name([]), do: nil
end
