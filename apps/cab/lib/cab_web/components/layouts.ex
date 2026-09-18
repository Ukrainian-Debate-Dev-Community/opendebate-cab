defmodule CabWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use CabWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  The cab app layout (design/cab2 chrome): top bar with brand,
  context title and the dev user menu, then the page body with title,
  guides and content. Every LiveView template begins with it:

      <Layouts.app flash={@flash} current_user={@current_user} ...>
        content
      </Layouts.app>

  Styling lives in `assets/css/app.css` under the `.cab` scope.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :current_user, :any, default: nil
  attr :dev_routes, :boolean, default: false
  attr :dev_users, :list, default: []
  attr :context, :any, default: nil, doc: "bar context title, e.g. tournament name"
  attr :return_to, :string, default: "/"
  attr :title, :string, required: true
  attr :subtitle, :any, default: nil
  attr :error, :any, default: nil, doc: "inline engine/validation error line"
  attr :notice, :any, default: nil, doc: "inline success line"
  slot :head_tag
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="cab">
      <div class="bar">
        <.link navigate={~p"/"} class="brand"><span class="dot">C</span> cab</.link>
        <span :if={@context} class="ctx">{@context}</span>
        <details :if={@dev_routes} class="usermenu" id="user-menu">
          <summary>
            <span :if={@current_user} class="avatar">{initials(@current_user.username)}</span>
            <span :if={@current_user}>{@current_user.username}</span>
            <span :if={is_nil(@current_user)} class="tag tag--warn">
              not signed in — pick a user
            </span>
            ▾
          </summary>
          <div class="userdrop">
            <div class="dhead">switch user (dev only)</div>
            <a
              :for={user <- @dev_users}
              href={"/dev/switch-user?username=#{user.username}&return_to=#{@return_to}"}
              style={
                @current_user && @current_user.username == user.username &&
                  "font-weight:800;color:var(--violet-700);"
              }
            >
              {user.username}
            </a>
            <form action="/dev/switch-user" method="get" id="dev-switch-user-form">
              <input type="hidden" name="return_to" value={@return_to} />
              <input
                class="input"
                type="text"
                name="username"
                placeholder="new user…"
                style="flex:1;"
              />
              <button class="btn btn--soft btn--sm" type="submit">Go</button>
            </form>
            <div style="border-top:1px solid var(--line); margin:5px 0;"></div>
            <a href="/dev/debug">Debug panel</a>
          </div>
        </details>
        <span :if={!@dev_routes} class="usermenu" style="font-size:.82rem; font-weight:600;">
          <span :if={@current_user}>{@current_user.username}</span>
          <span :if={is_nil(@current_user)} class="text-muted">not signed in</span>
        </span>
      </div>

      <div class="pubwrap">
        <div class="rolehead">
          <h1 class="h1">{@title}</h1>
          {render_slot(@head_tag)}
        </div>
        <p :if={@subtitle} class="text-muted" style="margin:-8px 0 14px; font-size:.86rem;">
          {@subtitle}
        </p>
        <div :if={@error} class="alert alert--warn" id="inline-error">
          <b>!</b> <span>{@error}</span>
        </div>
        <div :if={@notice} class="alert alert--ok" id="inline-notice">
          <b>✓</b> <span>{@notice}</span>
        </div>
        {render_slot(@inner_block)}
      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  defp initials(username) do
    username
    |> String.split(~r/[\s_-]+/, trim: true)
    |> Enum.map(&String.first/1)
    |> Enum.take(2)
    |> Enum.join()
    |> String.upcase()
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
