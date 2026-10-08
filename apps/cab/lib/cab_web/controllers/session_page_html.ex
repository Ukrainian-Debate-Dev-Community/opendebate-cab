defmodule CabWeb.SessionPageHTML do
  use CabWeb, :html

  # this view's ballot/1 is the page; the kit component stays qualified
  import CabWeb.Ui, except: [ballot: 1]
  alias CabWeb.Ui

  def show(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      club={@club}
      club_role={@club_role}
      nav_session={@nav_session}
      active="rooms"
    >
      <.chrome
        crumbs={[{@club.name, ~p"/c/#{@club.uuid}"}]}
        here={"#{@state.event["name"]} — #{stage_words(@state.stage)}"}
      >
        <:seg
          :if={@state.stage == :signup && is_nil(@my_signup)}
          href={~p"/r/#{@session.uuid}"}
          primary
        >
          Register
        </:seg>
        <:seg
          :if={@state.stage == :signup && @my_signup}
          href={~p"/c/#{@club.uuid}/s/#{@session.uuid}/signups/#{@my_signup["id"]}/remove"}
          method="post"
          quiet
        >
          Cancel my registration
        </:seg>
        <:seg
          :if={@my_ballot_room}
          href={~p"/c/#{@club.uuid}/s/#{@session.uuid}/rooms/#{@my_ballot_room["id"]}/ballot"}
          primary
        >
          Fill ballot — R{@my_ballot_room["id"]}
        </:seg>
      </.chrome>

      <div class="pbody">
        <.flash_banners flash={@flash} />

        <.banner :if={@state.stage != :done && @my_signup} kind={:good}>
          You are registered to {if @my_signup["role"] == "adjudicator",
            do: "judge",
            else: "speak"} tonight.
        </.banner>
        <.banner :if={@state.stage in [:closed, :running]} kind={:info}>
          Registration is closed for this session.
        </.banner>

        <.section title="Session" pad>
          <b id="session-name">{@state.event["name"]}</b>
          · {session_date(@session)}
          <%= if @winner do %>
            <p>Winner: <b>{@winner}</b></p>
          <% end %>
        </.section>

        <%= case @state.stage do %>
          <% stage when stage in [:signup, :closed] -> %>
            <.section title="Who's registered">
              <.table id="session-signups" rows={@state.signups} empty="Nobody signed up yet.">
                <:col :let={participant} label="Name">{participant["display_name"]}</:col>
                <:col :let={participant} label="Signed up as">{participant["role"]}</:col>
              </.table>
            </.section>
          <% :running -> %>
            <.banner :if={my_room_motion(@state, @my_room_id)} kind={:info}>
              Room {@my_room_id} motion: <b>{my_room_motion(@state, @my_room_id)}</b>
            </.banner>

            <.section title="Rooms">
              <.table
                id="session-rooms"
                rows={@state.rooms}
                row_class={fn room -> room["id"] == @my_room_id && "me" end}
              >
                <:col :let={room} class="rank">
                  <.link href={~p"/c/#{@club.uuid}/s/#{@session.uuid}/rooms/#{room["id"]}"}>
                    R{room["id"]}
                  </.link>
                </:col>
                <:col
                  :let={room}
                  :for={{label, position, side_class} <- sides()}
                  label={label}
                  class={"side #{side_class}"}
                >
                  {team_label(room, position)}
                </:col>
                <:col :let={room} label="Judge">
                  <%= if @current_user && Cab.Sessions.room_chair?(room, @current_user) do %>
                    <b>you</b>
                  <% else %>
                    {judge_name(room, @state.signups)}
                  <% end %>
                </:col>
                <:col :let={room} label="Status" class="st">
                  {room_words(room)}
                </:col>
              </.table>
            </.section>
          <% :done -> %>
            <.section :if={@state.rooms == []} title="Rooms" pad>
              This session finished without rooms.
            </.section>

            <%= for room <- @state.rooms do %>
              <.section title={"Room R#{room["id"]}"}>
                <div class="pad">
                  Motion: <b>{(room["Motion"] && room["Motion"]["motion_text"]) || "—"}</b>
                </div>
                <.table id={"room-#{room["id"]}-teams"} rows={sorted_teams(room)}>
                  <:col :let={room_team} label="Side" code>
                    {side_code(room_team["position"])}
                  </:col>
                  <:col :let={room_team} label="Team">{get_in(room_team, ["Team", "name"])}</:col>
                  <:col :let={room_team} label="Speakers">{speaker_names(room_team)}</:col>
                  <:col :let={room_team} label="Result" class="st">
                    <%= if room["status"] in ["completed", "confirmed"] && room_team["rank"] do %>
                      <%= if room_team["rank"] == 1 do %>
                        <b>won</b>
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
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  # ONE room URL for every viewer — identity picks what renders:
  # everyone sees the draw and the motion once set; the chair or head
  # additionally gets the motion form and the ballot link (@can_act)
  def room(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      club={@club}
      club_role={@club_role}
      nav_session={@nav_session}
      active="rooms"
    >
      <.chrome
        crumbs={[
          {@club.name, ~p"/c/#{@club.uuid}"},
          {@state.event["name"], ~p"/c/#{@club.uuid}/s/#{@session.uuid}"}
        ]}
        here={"room R#{@room["id"]} — #{room_status_words(@room["status"])}"}
      >
        <:seg :if={@can_act && is_nil(@room["Motion"])} form={"room-motion-#{@room["id"]}"} primary>
          Publish motion
        </:seg>
        <:seg
          :if={@can_edit_ballot}
          href={~p"/c/#{@club.uuid}/s/#{@session.uuid}/rooms/#{@room["id"]}/ballot"}
          primary={@room["Motion"] != nil}
        >
          {if @room["status"] in ["completed", "confirmed"],
            do: "Edit ballot",
            else: "Fill ballot"}
        </:seg>
      </.chrome>

      <div class="pbody">
        <.flash_banners flash={@flash} />

        <.section title="Draw">
          <.table id={"room-#{@room["id"]}-draw"} rows={sorted_teams(@room)}>
            <:col :let={room_team} label="Side" code>{side_code(room_team["position"])}</:col>
            <:col :let={room_team} label="Team">{get_in(room_team, ["Team", "name"])}</:col>
            <:col :let={room_team} label="Speakers">{speaker_names(room_team)}</:col>
          </.table>
          <div class="pad">Judge: <b>{judge_name(@room, @state.signups)}</b></div>
        </.section>

        <%= if @room["Motion"] do %>
          <.section title="Motion" pad>
            <b id="room-motion-text">{@room["Motion"]["motion_text"]}</b>
            <p :if={@room["Motion"]["infoslide"]}>{@room["Motion"]["infoslide"]}</p>
            <p :if={@room["Motion"]["keyword"]} class="mut">
              keyword: {@room["Motion"]["keyword"]}
            </p>
            <p :if={prep_deadline(@room)} class="mut">
              <span id="prep-clock" data-prep-deadline={prep_deadline(@room)}>
                15 minutes of prep from publishing
              </span>
            </p>
          </.section>
        <% else %>
          <.section :if={!@can_act} title="Motion" pad>
            Not set yet — the judge sets it when the room begins.
          </.section>
          <.section :if={@can_act} title="Motion">
            <.form_for
              id={"room-motion-#{@room["id"]}"}
              action={~p"/c/#{@club.uuid}/s/#{@session.uuid}/rooms/#{@room["id"]}/motion"}
              title="This room's motion"
              description="Publishing shows it to the room and starts 15 minutes of prep."
            >
              <:block name={:motion_text} type={:text} label="Motion" required />
              <:block
                name={:infoslide}
                type={:longtext}
                label="Infoslide"
                hint="Optional context read before prep."
              />
              <:block
                name={:keyword}
                type={:text}
                label="Keyword"
                hint="Optional tag for finding the motion later."
              />
              <:submit note="Visible to everyone in the room right away.">Publish motion</:submit>
            </.form_for>
          </.section>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  # the prep clock: 15 minutes from the motion's publication — the
  # engine ships created_at (ISO) with the motion; absent = no clock
  defp prep_deadline(room) do
    with %{"created_at" => created} when is_binary(created) <- room["Motion"],
         {:ok, at, _offset} <- DateTime.from_iso8601(created) do
      at |> DateTime.add(15, :minute) |> DateTime.to_iso8601()
    else
      _ -> nil
    end
  end

  def ballot(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      club={@club}
      club_role={@club_role}
      nav_session={@nav_session}
      active="rooms"
    >
      <.chrome
        crumbs={[
          {@club.name, ~p"/c/#{@club.uuid}"},
          {"session", ~p"/c/#{@club.uuid}/s/#{@session.uuid}"}
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
            action={~p"/c/#{@club.uuid}/s/#{@session.uuid}/rooms/#{@room["id"]}/ballot"}
          />
        </.section>
      </div>
    </Layouts.app>
    """
  end

  defp my_room_motion(%{rooms: rooms}, my_room_id) when is_integer(my_room_id) do
    case Enum.find(rooms, &(&1["id"] == my_room_id)) do
      %{"Motion" => %{"motion_text" => motion}} when is_binary(motion) -> motion
      _ -> nil
    end
  end

  defp my_room_motion(_state, _my_room_id), do: nil
end
