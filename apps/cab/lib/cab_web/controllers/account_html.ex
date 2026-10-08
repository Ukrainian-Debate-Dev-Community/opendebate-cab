defmodule CabWeb.AccountHTML do
  use CabWeb, :html

  # /account — profile card + display-name form (Save lives in the
  # chrome, the form carries no button of its own) + providers card
  def show(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active="account">
      <.chrome here="account">
        <:seg form="account-form" primary>Save</:seg>
        <:seg href={~p"/auth/logout"} quiet>Sign out</:seg>
      </.chrome>

      <div class="pbody">
        <.flash_banners flash={@flash} />

        <.section title="Profile">
          <.form_for id="account-form" action={~p"/account"}>
            <:block
              name={:name}
              type={:text}
              label="Display name"
              value={@current_user.name}
              hint="Shown instead of your username on rosters and draws."
            />
          </.form_for>
          <div class="pad">
            <p>
              Username: <b>{@current_user.username}</b>
              {if @current_user.email, do: " · #{@current_user.email}"}
            </p>
          </div>
        </.section>

        <.section title="Sign-in methods" pad>
          <%= if @identities == [] do %>
            Dev session — no provider linked.
          <% else %>
            Signed in with {Enum.map_join(@identities, ", ", & &1.provider)}.
          <% end %>
          <p>
            Google can be linked when it ships. Claim codes (guest history)
            land here later.
          </p>
          <p>
            Data requests or deletion:
            <a href="mailto:support@uadebate.com">support@uadebate.com</a>.
          </p>
        </.section>
      </div>
    </Layouts.app>
    """
  end
end
