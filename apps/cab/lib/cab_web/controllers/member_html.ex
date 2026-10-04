defmodule CabWeb.MemberHTML do
  use CabWeb, :html

  # this view's ballot/1 is the page; the kit component stays qualified
  import CabWeb.Ui, except: [ballot: 1]
  alias CabWeb.Ui

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
          :if={@state && @state.stage == :signup && is_nil(@my_signup)}
          href={~p"/c/#{@club.uuid}/member/sessions/#{@current.uuid}/register"}
          primary
        >
          Register
        </:seg>
        <:seg
          :if={@state && @state.stage == :signup && @my_signup}
          href={
            ~p"/c/#{@club.uuid}/member/sessions/#{@current.uuid}/signups/#{@my_signup["id"]}/remove"
          }
          method="post"
          quiet
        >
          Cancel my registration
        </:seg>
        <:seg
          :if={@my_ballot_room}
          href={~p"/c/#{@club.uuid}/member/rooms/#{@my_ballot_room["id"]}/ballot"}
          primary
        >
          Fill ballot
        </:seg>
      </.chrome>

      <div class="pbody">
        <.flash_banners flash={@flash} />

        <.banner :if={@state && @my_signup} kind={:good}>
          You are registered to {if @my_signup["role"] == "adjudicator",
            do: "judge",
            else: "speak"} tonight.
        </.banner>
        <.banner :if={@state && @state.stage in [:closed, :running]} kind={:info}>
          Registration is closed for this session.
        </.banner>

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
            <:col :let={session}>
              <.link href={~p"/c/#{@club.uuid}/s/#{session.uuid}"}>view</.link>
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
    <Layouts.app flash={@flash}>
      <.chrome
        crumbs={[
          {@club.name, ~p"/c/#{@club.uuid}"},
          {"tonight", ~p"/c/#{@club.uuid}/member"}
        ]}
        here="register"
        stage="sign-up open"
        stage_kind={:ok}
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

  def ballot(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.chrome
        crumbs={[
          {@club.name, ~p"/c/#{@club.uuid}"},
          {"tonight", ~p"/c/#{@club.uuid}/member"}
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
            action={~p"/c/#{@club.uuid}/member/rooms/#{@room["id"]}/ballot"}
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
