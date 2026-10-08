defmodule CabWeb.PageHTML do
  use CabWeb, :html

  def home(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active="clubs">
      <%= if @current_user do %>
        <.chrome here="my cab"></.chrome>
        <div class="pbody">
          <.flash_banners flash={@flash} />
          <.banner
            :if={@open_club}
            kind={:info}
            href={~p"/c/#{@open_club.uuid}"}
            link="Open →"
          >
            {@open_club.name}: a session is open.
          </.banner>

          <.section title="My clubs">
            <.table id="my-clubs" rows={@memberships} empty="You are not in any club yet.">
              <:col :let={m} label="Club">
                <.link href={~p"/c/#{m.club.uuid}"}>{m.club.name}</.link>
                <.sub>
                  {if m.status == "approved", do: m.role, else: "request pending"}{if m.club.city,
                    do: " · #{m.club.city}"}
                </.sub>
              </:col>
              <:col :let={m} label="Tonight" class="st">
                {if m.status == "approved", do: tonight_words(@tonight[m.club_id]), else: "—"}
              </:col>
            </.table>
          </.section>

          <.section :if={@schedule != []} title="My schedule">
            <.table id="my-schedule" rows={@schedule}>
              <:col :let={row} label="Session">
                <.link href={~p"/c/#{row.club.uuid}/s/#{row.session.uuid}"}>
                  {row.club.name}
                </.link>
                <.sub :if={row.session.scheduled_at}>
                  {Calendar.strftime(row.session.scheduled_at, "%-d %b %H:%M")}
                </.sub>
              </:col>
              <:col :let={row} label="Signed up as">{row.role}</:col>
            </.table>
          </.section>

          <.section title="My sessions">
            <.table id="my-sessions" rows={@history} empty="Past sessions will appear here.">
              <:col :let={row} label="Session">
                <.link href={~p"/c/#{row.club_uuid}/s/#{row.session_uuid}"}>
                  {Calendar.strftime(row.date, "%-d %b %Y")}
                </.link>
                <.sub>{row.club} · {row.role}</.sub>
              </:col>
              <:col :let={row} label="Result" class="st">
                <%= cond do %>
                  <% row.won -> %>
                    <b>won</b>
                  <% row.role == "judge" -> %>
                    judged
                  <% true -> %>
                    played
                <% end %>
              </:col>
            </.table>
          </.section>
        </div>
      <% else %>
        <.chrome here="debate clubs of Ukraine"></.chrome>
        <div class="pbody">
          <.flash_banners flash={@flash} />

          <div class="welcome" id="welcome">
            <h2>Welcome to <span class="brand-script">cab</span></h2>
            <p>
              The home of Ukrainian debate clubs: find a club, register for a
              session, debate — and follow standings and your own results in
              one place. Free for every Ukrainian club, run by the Debate
              Federation of Ukraine.
            </p>
            <p class="mut">
              Registering for a session needs no account — the club shares one
              link. <.link href={~p"/signin"}>Sign in</.link>
              to keep your history, schedule and personal stats.
            </p>
          </div>

          <.section title="Clubs">
            <.table id="clubs-directory" rows={@clubs} empty="No clubs here yet.">
              <:col :let={club} label="Club">
                <.link href={~p"/c/#{club.uuid}"}>{club.name}</.link>
              </:col>
              <:col :let={club} label="City">{club.city}</:col>
              <:col :let={club} label="Members" num>{@member_counts[club.id] || 0}</:col>
              <:col :let={club} label="Tonight" class="st">
                {tonight_words(@tonight[club.id])}
              </:col>
            </.table>
          </.section>
        </div>
      <% end %>
    </Layouts.app>
    """
  end

  # the Tonight column, written out as words — no pills anywhere
  defp tonight_words(nil), do: "quiet"

  defp tonight_words({session, :signup, _rooms}) do
    case session.scheduled_at do
      %DateTime{} = at -> "sign-ups open, #{Calendar.strftime(at, "%a %H:%M")}"
      _ -> "sign-ups open"
    end
  end

  defp tonight_words({_session, :closed, _rooms}), do: "sign-ups closed"

  defp tonight_words({_session, :running, rooms}),
    do: "session running, #{rooms} room#{if rooms != 1, do: "s"}"
end
