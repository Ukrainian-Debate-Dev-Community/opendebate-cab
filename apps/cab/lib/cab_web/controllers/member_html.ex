defmodule CabWeb.MemberHTML do
  use CabWeb, :html

  # P5 — my club page: tonight + my registration, my role, my results
  def show(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.chrome
        crumbs={[{@club.name, ~p"/c/#{@club.uuid}"}]}
        here="me"
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
      </.chrome>

      <div class="pbody">
        <.flash_banners flash={@flash} />

        <.banner :if={@state && @my_signup} kind={:good}>
          You are registered to {if @my_signup["role"] == "adjudicator",
            do: "judge",
            else: "speak"} tonight.
        </.banner>
        <.banner
          :if={@state && @state.stage in [:closed, :running]}
          kind={:info}
          href={~p"/c/#{@club.uuid}/s/#{@current.uuid}"}
          link="Open the session page →"
        >
          Registration is closed for this session.
        </.banner>

        <.section title="Tonight" pad>
          <%= if @current && @state do %>
            <b>
              <.link id="tonight-session" href={~p"/c/#{@club.uuid}/s/#{@current.uuid}"}>
                {@state.event["name"]}
              </.link>
            </b>
            {tonight_meta(@current, @state)}
            <p>{my_state_line(@state, @my_signup)}</p>
            <p>You are a {role_name(@club_role)} of this club.</p>
          <% else %>
            No session is open.
            <p>Your club head opens sessions; sign-up appears here.</p>
            <p>You are a {role_name(@club_role)} of this club.</p>
          <% end %>
        </.section>

        <.section title="My results in this club">
          <.table id="my-results" rows={@my_results} empty="Your results will appear here.">
            <:col :let={row} label="Date">
              <.link href={~p"/c/#{@club.uuid}/s/#{row.session_uuid}"}>
                {Calendar.strftime(row.date, "%-d %b %Y")}
              </.link>
            </:col>
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
          {"me", ~p"/c/#{@club.uuid}/member"}
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

  defp tonight_meta(current, state) do
    date =
      case current.scheduled_at do
        %DateTime{} = at -> Calendar.strftime(at, "%-d %b · %H:%M")
        _ -> Calendar.strftime(current.inserted_at, "%-d %b")
      end

    "· #{date} · #{length(state.signups)} registered"
  end

  defp my_state_line(%{stage: :signup}, nil),
    do: "You are not registered yet. Registration closes when the head makes rooms."

  defp my_state_line(%{stage: :signup}, _my_signup),
    do: "Cancel from the chrome if your plans change."

  defp my_state_line(_state, nil), do: "You are not registered for this session."
  defp my_state_line(_state, _my_signup), do: "See the session page for your room."

  defp role_name(:owner), do: "head"
  defp role_name(_role), do: "member"

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
end
