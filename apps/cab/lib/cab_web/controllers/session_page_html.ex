defmodule CabWeb.SessionPageHTML do
  use CabWeb, :html

  # this view's ballot/1 is the page; the kit component stays qualified
  import CabWeb.Ui, except: [ballot: 1]
  alias CabWeb.Ui

  @sides [{"OG", 1, "s-og"}, {"OO", 2, "s-oo"}, {"CG", 3, "s-cg"}, {"CO", 4, "s-co"}]

  def show(assigns) do
    assigns = Map.put(assigns, :sides, @sides)

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
        here={"#{@state.event["name"]} — #{stage_label(@state)}"}
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

            <.section title="Draw">
              <.table
                id="session-draw"
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
                  :for={{label, position, side_class} <- @sides}
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
        <:seg
          :if={@can_act && @room["status"] in ["pending", "judging", "completed"]}
          href={~p"/c/#{@club.uuid}/s/#{@session.uuid}/rooms/#{@room["id"]}/ballot"}
          primary
        >
          {if @room["status"] == "completed", do: "Edit ballot", else: "Fill ballot"}
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
          </.section>
        <% else %>
          <.section :if={!@can_act} title="Motion" pad>
            Not set yet — the judge sets it when the room begins.
          </.section>
          <.section :if={@can_act} title="Motion">
            <.form_for
              id={"room-motion-#{@room["id"]}"}
              action={~p"/c/#{@club.uuid}/s/#{@session.uuid}/rooms/#{@room["id"]}/motion"}
              title="Set this room's motion"
              description="Setting it shows it to the room and starts 15 minutes of prep."
            >
              <:block name={:motion_text} type={:text} label="Motion" required />
              <:submit note="Visible to everyone in the room right away.">Set motion</:submit>
            </.form_for>
          </.section>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp room_status_words("pending"), do: "waiting to start"
  defp room_status_words("judging"), do: "debating — waiting for the ballot"
  defp room_status_words("completed"), do: "ballot in"
  defp room_status_words("confirmed"), do: "ballot in"
  defp room_status_words("void"), do: "void"
  defp room_status_words(other), do: other

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

  # ---------------------------------------------------------------
  # Draw helpers
  # ---------------------------------------------------------------

  # the team at a side position; a 1-speaker team is marked (iron)
  defp team_label(room, position) do
    case Enum.find(room["RoomTeams"] || [], &(&1["position"] == position)) do
      nil ->
        "—"

      room_team ->
        name = get_in(room_team, ["Team", "name"]) || "—"
        if iron_team?(room_team), do: "#{name} (iron)", else: name
    end
  end

  defp iron_team?(room_team) do
    (room_team["RoomSpeakers"] || [])
    |> Enum.map(&get_in(&1, ["EventParticipant", "id"]))
    |> Enum.uniq()
    |> length() == 1
  end

  # the chair's display name, resolved through the signups list
  defp judge_name(room, signups) do
    chair =
      Enum.find(room["RoomAdjudicators"] || [], &(&1["role"] == "chair"))

    with %{} <- chair,
         participant_id when not is_nil(participant_id) <-
           get_in(chair, ["EventParticipant", "id"]) do
      get_in(chair, ["EventParticipant", "display_name"]) ||
        Enum.find_value(signups, &(&1["id"] == participant_id && &1["display_name"])) || "—"
    else
      _ -> "—"
    end
  end

  defp my_room_motion(%{rooms: rooms}, my_room_id) when is_integer(my_room_id) do
    case Enum.find(rooms, &(&1["id"] == my_room_id)) do
      %{"Motion" => %{"motion_text" => motion}} when is_binary(motion) -> motion
      _ -> nil
    end
  end

  defp my_room_motion(_state, _my_room_id), do: nil

  # ---------------------------------------------------------------
  # Results helpers (done stage)
  # ---------------------------------------------------------------

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
end
