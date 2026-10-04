defmodule CabWeb.PageHTML do
  use CabWeb, :html

  def home(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <%= if @current_user do %>
        <.chrome account current_user={@current_user} here="my cabinet" />
        <div class="pbody">
          <.flash_banners flash={@flash} />
          <.banner
            :if={@open_club}
            kind={:info}
            href={~p"/c/#{@open_club.uuid}/member"}
            link="Sign up →"
          >
            {@open_club.name}: a session is open.
          </.banner>

          <.section title="My clubs">
            <.table id="my-clubs" rows={@memberships} empty="You are not in any club yet.">
              <:col :let={m} label="Club">
                {m.club.name}
                <.sub :if={m.club.city}>{m.club.city}</.sub>
              </:col>
              <:col :let={m} label="Role">
                {if m.status == "approved", do: m.role, else: "—"}
              </:col>
              <:col :let={m} label="Status">
                <.tag :if={m.status == "approved"} kind={:ok}>active</.tag>
                <.tag :if={m.status != "approved"} kind={:warn}>request pending</.tag>
              </:col>
              <:col :let={m} label="Members" num>{@member_counts[m.club_id] || 0}</:col>
              <:col :let={m}>
                <.link :if={m.status == "approved"} href={~p"/c/#{m.club.uuid}"}>open</.link>
              </:col>
            </.table>
          </.section>

          <.section title="My sessions">
            <.table id="my-sessions" rows={@history} empty="Past sessions will appear here.">
              <:col :let={row} label="Date">
                {Calendar.strftime(row.date, "%-d %b %Y")}
              </:col>
              <:col :let={row} label="Club">{row.club}</:col>
              <:col :let={row} label="I was">{row.role}</:col>
              <:col :let={row} label="Result">
                <%= if row.won do %>
                  <.tag kind={:ok}>won</.tag>
                <% else %>
                  —
                <% end %>
              </:col>
              <:col :let={row}>
                <.link href={~p"/c/#{row.club_uuid}/s/#{row.session_uuid}"}>view</.link>
              </:col>
            </.table>
          </.section>
        </div>
      <% else %>
        <.chrome account current_user={nil} here="cab" />
        <div class="pbody">
          <.flash_banners flash={@flash} />
          <.banner kind={:info} href={~p"/auth/github"} link="Sign in →">
            The debate club cabinet. Sign in with GitHub to enter.
          </.banner>
        </div>
      <% end %>
    </Layouts.app>
    """
  end
end
