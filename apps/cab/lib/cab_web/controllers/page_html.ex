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
            link="Register →"
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
                <%= if m.status == "approved" do %>
                  {m.role}
                <% else %>
                  <.tag kind={:warn}>request pending</.tag>
                <% end %>
              </:col>
              <:col :let={m} label="Tonight">
                <%= if m.status == "approved" do %>
                  <.tag kind={tonight_kind(@tonight[m.club_id])}>
                    {tonight_label(@tonight[m.club_id])}
                  </.tag>
                <% else %>
                  —
                <% end %>
              </:col>
              <:col :let={m}>
                <%= cond do %>
                  <% m.status != "approved" -> %>
                    <.link href={~p"/c/#{m.club.uuid}"}>open</.link>
                  <% m.role == "head" -> %>
                    <.link href={~p"/c/#{m.club.uuid}/owner"}>owner console</.link>
                  <% true -> %>
                    <.link href={~p"/c/#{m.club.uuid}/member"}>my club page</.link>
                <% end %>
              </:col>
            </.table>
          </.section>

          <.section title="My sessions">
            <.table id="my-sessions" rows={@history} empty="Past sessions will appear here.">
              <:col :let={row} label="Date">
                <.link href={~p"/c/#{row.club_uuid}/s/#{row.session_uuid}"}>
                  {Calendar.strftime(row.date, "%-d %b %Y")}
                </.link>
              </:col>
              <:col :let={row} label="Club">{row.club}</:col>
              <:col :let={row} label="I was">{row.role}</:col>
              <:col :let={row} label="Result">
                <%= cond do %>
                  <% row.won -> %>
                    <.tag kind={:ok}>won</.tag>
                  <% row.role == "judge" -> %>
                    <.tag kind={:mut}>judged</.tag>
                  <% true -> %>
                    —
                <% end %>
              </:col>
            </.table>
          </.section>
        </div>
      <% else %>
        <.chrome account current_user={nil} here="debate clubs of Ukraine" />
        <div class="pbody">
          <.flash_banners flash={@flash} />
          <.banner kind={:info} href={~p"/signin"} link="Sign in →">
            Play, judge and run debate sessions — free for every Ukrainian club.
          </.banner>

          <.section title="Clubs">
            <.table id="clubs-directory" rows={@clubs} empty="No clubs here yet.">
              <:col :let={club} label="Club">{club.name}</:col>
              <:col :let={club} label="City">{club.city}</:col>
              <:col :let={club} label="Members" num>{@member_counts[club.id] || 0}</:col>
              <:col :let={club} label="Sessions" num>{@session_counts[club.id] || 0}</:col>
              <:col :let={club}>
                <.link href={~p"/c/#{club.uuid}"}>open</.link>
              </:col>
            </.table>
          </.section>
        </div>
      <% end %>
    </Layouts.app>
    """
  end

  defp tonight_label(nil), do: "no session"
  defp tonight_label({_session, :signup}), do: "sign-ups open"
  defp tonight_label({_session, :closed}), do: "sign-ups closed"
  defp tonight_label({_session, :running}), do: "running"

  defp tonight_kind(nil), do: :mut
  defp tonight_kind({_session, :signup}), do: :ok
  defp tonight_kind({_session, _stage}), do: :warn
end
