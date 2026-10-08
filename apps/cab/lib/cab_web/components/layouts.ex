defmodule CabWeb.Layouts do
  @moduledoc """
  The page shell: root (the HTML document) and app (sidenav + main
  column + footer).
  """
  use CabWeb, :html

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
                  Clubs across Ukraine run weekly practice rounds — pick one and
                  come debate. Free for every Ukrainian club.
                </p>
                <div class="flinks">
                  <a href="https://uadebate.com">Main page</a>
                </div>
              </div>
              <div>
                <h6>Our organisation</h6>
                <p>
                  Run by the NGO Debate Federation of Ukraine
                  (ВМГО «Федерація Дебатів України»).
                </p>
                <div class="flinks">
                  <a href="https://dfu.uadebate.com">DFU</a>
                  <a href="mailto:ngo.dfu@uadebate.com">Contact us</a>
                </div>
              </div>
              <div>
                <h6>Data &amp; privacy</h6>
                <p>
                  cab is in beta testing.
                </p>
                <div class="flinks">
                  <a href="/privacy">Privacy&amp;Policy</a>
                  <a href="mailto:support@uadebate.com">Support</a>
                </div>
              </div>
            </div>
          </div>
        </footer>
      </div>
    </div>
    """
  end
end
