defmodule PublicWeb do
  @moduledoc "The web layer of the public site: `use PublicWeb, :controller` and friends."

  def static_paths, do: ~w(css fonts images js favicon.ico robots.txt)

  def router do
    quote do
      use Phoenix.Router, helpers: false
      import Plug.Conn
      import Phoenix.Controller
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:html]
      use Gettext, backend: PublicWeb.Gettext
      import Plug.Conn
      import Phoenix.Component, only: [to_form: 2]
      unquote(verified_routes())
    end
  end

  def html do
    quote do
      use Phoenix.Component
      import Phoenix.Controller, only: [get_csrf_token: 0]
      use Gettext, backend: PublicWeb.Gettext
      import PublicWeb.Site
      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: PublicWeb.Endpoint,
        router: PublicWeb.Router,
        statics: PublicWeb.static_paths()
    end
  end

  defmacro __using__(which) when is_atom(which), do: apply(__MODULE__, which, [])
end
