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
  Renders your app layout: the pages-v6 SHELL — left sidenav (the
  only navigation) + the main column the page fills with its chrome
  and body; the footer scheme stays below.

      <Layouts.app flash={@flash} current_user={@current_user}
                   club={@club} club_role={@club_role}
                   nav_session={@nav_session} active="sessions">
        <.chrome .../>
        <div class="pbody">...</div>
      </Layouts.app>
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_user, :any, default: nil
  attr :club, :any, default: nil, doc: "club context for the sidenav; nil = global"
  attr :club_role, :atom, default: :public
  attr :nav_session, :any, default: nil, doc: "the club's newest session (sidenav Rooms)"
  attr :active, :string, default: nil, doc: "the lit sidenav item"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="shell">
      <CabWeb.Ui.sidenav
        current_user={@current_user}
        club={@club}
        club_role={@club_role}
        nav_session={@nav_session}
        active={@active}
      />
      <div class="mainc">
        <main class="page-main">
          {render_slot(@inner_block)}
        </main>
        <footer class="footer">
          <div class="in">
            <div class="cols">
              <div>
                <h6>Find your club</h6>
                <p>
                  Clubs across Ukraine run weekly practice rounds — pick one on
                  <a href="https://uadebate.com">uadebate.com</a>
                  and come debate.
                  Free for every Ukrainian club.
                </p>
              </div>
              <div>
                <h6>Our organisation</h6>
                <p>
                  Run by the NGO Debate Federation of Ukraine
                  (ВМГО «Дебатна Федерація України») ·
                  <a href="https://dfu.uadebate.com">dfu.uadebate.com</a>
                  · <a href="mailto:ngo.dfu@uadebate.com">ngo.dfu@uadebate.com</a>
                </p>
              </div>
              <div>
                <h6>Data &amp; privacy</h6>
                <p>
                  cab is in beta testing · <a href="/privacy">Privacy &amp; data policy</a>
                  · <a href="mailto:support@uadebate.com">support@uadebate.com</a>
                </p>
              </div>
            </div>
          </div>
        </footer>
      </div>
    </div>
    """
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
