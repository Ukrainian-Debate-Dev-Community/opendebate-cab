defmodule CabWeb.GuestRegistrationHTML do
  use CabWeb, :html

  # GET /r/:session_uuid while :signup — the guest registration form:
  # name required + the kit's role pills (Speaker | Judge)
  def new(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={assigns[:current_user]}
      club={@club}
      nav_session={@session}
      active="rooms"
    >
      <.chrome crumbs={[{@club.name, ~p"/c/#{@club.uuid}"}]} here="register — sign-ups open">
      </.chrome>

      <div class="pbody">
        <.flash_banners flash={@flash} />

        <.section title="Registration">
          <.form_for
            id="guest-register-form"
            action={~p"/r/#{@session.uuid}"}
            title={"Register for #{@state.event["name"]}"}
            description="No account needed — you'll get a personal link that is your access to this session."
            errors={@errors}
          >
            <:block name={:name} type={:text} label="Your name" required value={@name} />
            <:block
              name={:as}
              type={:select}
              label="I am tonight"
              required
              value={@as}
              options={[{"Speaker", "speak"}, {"Judge", "judge"}]}
            />
            <:submit note="You appear in tonight's list right away.">Register</:submit>
          </.form_for>
        </.section>
      </div>
    </Layouts.app>
    """
  end

  # the personal-link page the guest lands on after registering: the
  # full /l/:code URL with the copy affordance + the keep-it warning
  def created(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={assigns[:current_user]}
      club={@club}
      nav_session={@session}
      active="rooms"
    >
      <.chrome crumbs={[{@club.name, ~p"/c/#{@club.uuid}"}]} here="registered">
        <:seg href={~p"/l/#{@link.code}"} primary>Open my session page</:seg>
      </.chrome>

      <div class="pbody">
        <.flash_banners flash={@flash} />

        <.banner kind={:good}>
          You are registered to {if @role == "judge", do: "judge", else: "speak"} as {@link.user.name}.
        </.banner>

        <.section title="Your personal link">
          <div class="pad">
            <.copy_banner id="personal-link" url={@personal_url}>Your link</.copy_banner>
            <p>
              Keep this link — it IS your access: anyone with it acts as you.
              It opens your view of this session: your registration, the rooms,
              and (if you judge) the ballot.
            </p>
          </div>
        </.section>
      </div>
    </Layouts.app>
    """
  end

  # any stage but :signup — the registration-closed notice
  def closed(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={assigns[:current_user]}
      club={@club}
      nav_session={@session}
      active="rooms"
    >
      <.chrome
        crumbs={[{@club.name, ~p"/c/#{@club.uuid}"}]}
        here={"register — #{stage_label(@state)}"}
      >
      </.chrome>

      <div class="pbody">
        <.flash_banners flash={@flash} />

        <.banner kind={:info}>Registration is closed for this session.</.banner>

        <.section title="Registration" pad>
          Sign-ups for <b>{@state.event["name"]}</b>
          are no longer open.
          <p>Ask the club head about the next session.</p>
        </.section>
      </div>
    </Layouts.app>
    """
  end

  defp stage_label(%{stage: :signup}), do: "sign-up open"
  defp stage_label(%{stage: :closed}), do: "sign-ups closed"
  defp stage_label(%{stage: :running}), do: "running"
  defp stage_label(%{stage: :done}), do: "done"
end
