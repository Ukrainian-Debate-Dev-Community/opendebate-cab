defmodule CabWeb.Layouts do
  @moduledoc """
  The page shell: root (the HTML document) and app (sidenav + main
  column + footer).
  """
  use CabWeb, :html

  embed_templates "layouts/*"

  @doc """
  The app shell: left sidenav (the only navigation) + the main column
  the page fills with its chrome and body, the footer under it.

      <Layouts.app flash={@flash} current_user={@current_user}
                   club={@club} club_role={@club_role}
                   nav_session={@nav_session} active="rooms">
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

  def app(assigns)
end
