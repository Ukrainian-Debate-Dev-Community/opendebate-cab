defmodule CabWeb.MemberHTML do
  use CabWeb, :html

  def show(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.chrome
        crumbs={[{@club.name, ~p"/c/#{@club.uuid}"}]}
        here="tonight"
        stage={stage_label(@state)}
        stage_kind={stage_kind(@state)}
      >
        <:seg
          :if={@state && @state.stage == :signup}
          href={~p"/c/#{@club.uuid}/member/sessions/#{@current.uuid}/signups?as=judge"}
          method="post"
        >
          I judge
        </:seg>
        <:seg
          :if={@state && @state.stage == :signup}
          href={~p"/c/#{@club.uuid}/member/sessions/#{@current.uuid}/signups?as=speak"}
          method="post"
          primary
        >
          I speak tonight
        </:seg>
      </.chrome>

      <div class="pbody">
        <.flash_banners flash={@flash} />

        <%= if @current && @state do %>
          <.section title="Tonight">
            <.table id="session-signups" rows={@state.signups} empty="Nobody signed up yet.">
              <:col :let={participant} label="Name">{participant["display_name"]}</:col>
              <:col :let={participant} label="Signed up as">{participant["role"]}</:col>
            </.table>
          </.section>

          <.section :if={@state.rooms != []} title="Rooms">
            <.table id="session-rooms" rows={@state.rooms}>
              <:col :let={room} label="Room" code>R{room["id"]}</:col>
              <:col :let={room} label="Status">
                <.tag kind={room_kind(room["status"])}>{room["status"]}</.tag>
              </:col>
              <:col :let={room} label="Motion">
                {(room["Motion"] && room["Motion"]["motion_text"]) || "—"}
              </:col>
              <:col :let={room} label="Teams">
                <%= for rt <- Enum.sort_by(room["RoomTeams"] || [], & &1["position"]) do %>
                  <span>
                    {get_in(rt, ["Team", "name"])}
                    <.tag :if={rt["rank"] == 1} kind={:ok}>won</.tag>
                  </span>
                <% end %>
              </:col>
            </.table>
          </.section>
        <% else %>
          <.section title="Tonight" pad>
            No session is open.
            <p>Your club head opens sessions; sign-up appears here.</p>
          </.section>
        <% end %>

        <.section title="History">
          <.table id="sessions-list" rows={@sessions} empty="No sessions yet.">
            <:col :let={session} label="Opened">
              {Calendar.strftime(session.inserted_at, "%-d %b %Y")}
            </:col>
            <:col :let={session} label="Session" code>{session.uuid}</:col>
          </.table>
        </.section>
      </div>
    </Layouts.app>
    """
  end

  defp stage_label(nil), do: nil
  defp stage_label(%{stage: :signup}), do: "sign-up open"
  defp stage_label(%{stage: :running}), do: "running"
  defp stage_label(%{stage: :done}), do: "done"

  defp stage_kind(nil), do: :off
  defp stage_kind(%{stage: :signup}), do: :ok
  defp stage_kind(%{stage: :running}), do: :warn
  defp stage_kind(%{stage: :done}), do: :off

  defp room_kind(status) when status in ["confirmed", "completed"], do: :ok
  defp room_kind("pending"), do: :mut
  defp room_kind(_status), do: :warn
end
