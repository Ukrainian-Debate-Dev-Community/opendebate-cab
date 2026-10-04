defmodule CabWeb.GuestLinkHTML do
  use CabWeb, :html

  # this view's ballot/1 is the page; the kit component stays qualified
  import CabWeb.Ui, except: [ballot: 1]
  alias CabWeb.Ui

  # GET /l/:code — the guest view of their one session
  def show(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.chrome
        crumbs={[{@club.name, ~p"/c/#{@club.uuid}"}]}
        here="my session"
        stage={stage_label(@state)}
        stage_kind={stage_kind(@state)}
      >
        <:seg
          :if={@state && @state.stage == :signup && @my_signup}
          href={~p"/l/#{@link.code}/signups/#{@my_signup["id"]}/remove"}
          method="post"
          quiet
        >
          Cancel my registration
        </:seg>
        <:seg
          :if={@my_ballot_room}
          href={~p"/l/#{@link.code}/rooms/#{@my_ballot_room["id"]}/ballot"}
          primary
        >
          Fill ballot
        </:seg>
      </.chrome>

      <div class="pbody">
        <.flash_banners flash={@flash} />

        <.banner kind={:info}>
          You are here through your personal link, {@link.user.name}.
          Keep it — anyone with it acts as you.
        </.banner>

        <.banner :if={@state && @my_signup} kind={:good}>
          You are registered to {if @my_signup["role"] == "adjudicator",
            do: "judge",
            else: "speak"} tonight.
        </.banner>
        <.banner :if={@state && is_nil(@my_signup)} kind={:info}>
          You are not registered for this session any more.
        </.banner>
        <.banner :if={@state && @state.stage in [:closed, :running]} kind={:info}>
          Registration is closed for this session.
        </.banner>

        <%= if @state do %>
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
            The session is unavailable right now.
            <p>Try again in a moment — your link stays valid.</p>
          </.section>
        <% end %>

        <.section title="Your personal link">
          <div class="pad">
            <.copy_banner id="personal-link" url={@personal_url}>Your link</.copy_banner>
            <p>This link is your only access — keep it; anyone with it acts as you.</p>
          </div>
        </.section>
      </div>
    </Layouts.app>
    """
  end

  def ballot(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.chrome
        crumbs={[
          {@club.name, ~p"/c/#{@club.uuid}"},
          {"my session", ~p"/l/#{@link.code}"}
        ]}
        here={"ballot R#{@room["id"]}"}
      >
        <:seg form={"ballot-#{@room["id"]}"} primary>Submit ballot</:seg>
      </.chrome>

      <div class="pbody">
        <.flash_banners flash={@flash} />

        <.section title={"Room R#{@room["id"]} · ballot"}>
          <Ui.ballot
            id={"ballot-#{@room["id"]}"}
            room={"R#{@room["id"]}"}
            motion={@room["Motion"] && @room["Motion"]["motion_text"]}
            teams={@teams}
            error={@error}
            action={~p"/l/#{@link.code}/rooms/#{@room["id"]}/ballot"}
          />
        </.section>
      </div>
    </Layouts.app>
    """
  end

  defp stage_label(nil), do: nil
  defp stage_label(%{stage: :signup}), do: "sign-up open"
  defp stage_label(%{stage: :closed}), do: "sign-ups closed"
  defp stage_label(%{stage: :running}), do: "running"
  defp stage_label(%{stage: :done}), do: "done"

  defp stage_kind(nil), do: :off
  defp stage_kind(%{stage: :signup}), do: :ok
  defp stage_kind(%{stage: :closed}), do: :warn
  defp stage_kind(%{stage: :running}), do: :warn
  defp stage_kind(%{stage: :done}), do: :off

  defp room_kind(status) when status in ["confirmed", "completed"], do: :ok
  defp room_kind("pending"), do: :mut
  defp room_kind(_status), do: :warn
end
