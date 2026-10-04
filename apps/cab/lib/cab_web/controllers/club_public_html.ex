defmodule CabWeb.ClubPublicHTML do
  use CabWeb, :html

  def show(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.chrome
        account
        current_user={@current_user}
        crumbs={[{@club.name, ~p"/c/#{@club.uuid}"}]}
        here="about"
        stage="recruiting"
        stage_kind={:ok}
      >
        <:seg
          :if={@club_role == :public and is_nil(@current_user)}
          href={~p"/auth/github"}
          primary
        >
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
        <:seg :if={@club_role in [:member, :owner]} href={~p"/c/#{@club.uuid}/member"}>
          Member area
        </:seg>
        <:seg :if={@club_role == :owner} href={~p"/c/#{@club.uuid}/owner"}>
          Owner area
        </:seg>
      </.chrome>

      <div class="pbody">
        <.flash_banners flash={@flash} />

        <.section title="Club" pad>
          <b id="club-name">{@club.name}</b>{if @club.city, do: " · #{@club.city}"}
        </.section>

        <.section title="History">
          <.table id="club-history" rows={@history} empty="No completed sessions yet.">
            <:col :let={event} label="Session">{event["name"]}</:col>
            <:col :let={event} label="Winner">
              <%= if event["winner"] do %>
                {event["winner"]}
                <.tag kind={:ok}>won</.tag>
              <% else %>
                —
              <% end %>
            </:col>
            <:col :let={event}>
              <.link
                :if={@session_uuids[event["id"]]}
                href={~p"/c/#{@club.uuid}/s/#{@session_uuids[event["id"]]}"}
              >
                view
              </.link>
            </:col>
          </.table>
        </.section>

        <.section title="Members" pad>
          {length(@members)} member{if length(@members) != 1, do: "s"}{if head_name(@members),
            do: " · head: #{head_name(@members)}"}
          <p>Full roster is visible to members.</p>
        </.section>
      </div>
    </Layouts.app>
    """
  end

  # list_members/1 orders head first
  defp head_name([%{user: user} | _rest]), do: user.name || user.username
  defp head_name([]), do: nil

  # GET /c/:club_uuid/s/:session_uuid — the public session detail
  # page: name/date, stage, rooms with teams/speakers, motions,
  # confirmed results (ranks), winner
  def session(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.chrome
        account
        current_user={@current_user}
        crumbs={[{@club.name, ~p"/c/#{@club.uuid}"}]}
        here={@state.event["name"]}
        stage={stage_label(@state)}
        stage_kind={stage_kind(@state)}
      >
      </.chrome>

      <div class="pbody">
        <.flash_banners flash={@flash} />

        <.section title="Session" pad>
          <b id="session-name">{@state.event["name"]}</b>
          · {session_date(@session)}
          <%= if @winner do %>
            <p>
              Winner: <b>{@winner}</b>
              <.tag kind={:ok}>won</.tag>
            </p>
          <% end %>
        </.section>

        <.section :if={@state.rooms == []} title="Rooms" pad>
          No rooms yet.
          <p>Rooms appear here once the head composes them from the attendance.</p>
        </.section>

        <%= for room <- @state.rooms do %>
          <.section title={"Room R#{room["id"]}"}>
            <div class="pad">
              Motion: <b>{(room["Motion"] && room["Motion"]["motion_text"]) || "—"}</b>
            </div>
            <.table id={"room-#{room["id"]}-teams"} rows={sorted_teams(room)}>
              <:col :let={room_team} label="Side" code>{side_code(room_team["position"])}</:col>
              <:col :let={room_team} label="Team">{get_in(room_team, ["Team", "name"])}</:col>
              <:col :let={room_team} label="Speakers">{speaker_names(room_team)}</:col>
              <:col :let={room_team} label="Result">
                <%= if room["status"] in ["completed", "confirmed"] && room_team["rank"] do %>
                  <%= if room_team["rank"] == 1 do %>
                    <.tag kind={:ok}>won</.tag>
                  <% else %>
                    {ordinal(room_team["rank"])}
                  <% end %>
                <% else %>
                  —
                <% end %>
              </:col>
            </.table>
          </.section>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp sorted_teams(room), do: Enum.sort_by(room["RoomTeams"] || [], & &1["position"])

  defp side_code(position), do: Enum.at(~w(OG OO CG CO), (position || 1) - 1)

  # iron teams carry the same participant on both slots — show once
  defp speaker_names(room_team) do
    (room_team["RoomSpeakers"] || [])
    |> Enum.map(&get_in(&1, ["EventParticipant", "display_name"]))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.join(" & ")
  end

  defp ordinal(1), do: "1st"
  defp ordinal(2), do: "2nd"
  defp ordinal(3), do: "3rd"
  defp ordinal(rank), do: "#{rank}th"

  defp session_date(%{scheduled_at: %DateTime{} = scheduled_at}),
    do: Calendar.strftime(scheduled_at, "%-d %b %Y · %H:%M")

  defp session_date(session), do: Calendar.strftime(session.inserted_at, "%-d %b %Y")

  defp stage_label(%{stage: :signup}), do: "sign-up open"
  defp stage_label(%{stage: :closed}), do: "sign-ups closed"
  defp stage_label(%{stage: :running}), do: "running"
  defp stage_label(%{stage: :done}), do: "done"

  defp stage_kind(%{stage: :signup}), do: :ok
  defp stage_kind(%{stage: :closed}), do: :warn
  defp stage_kind(%{stage: :running}), do: :warn
  defp stage_kind(%{stage: :done}), do: :off
end
