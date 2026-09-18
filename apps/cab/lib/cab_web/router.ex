defmodule CabWeb.Router do
  use CabWeb, :router

  import CabWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CabWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Server-to-server API for the uadebate.com portal (static bearer token).
  pipeline :public_api do
    plug :accepts, ["json"]
    plug CabWeb.Plugs.PortalApiAuth
  end

  scope "/", CabWeb do
    pipe_through :browser

    live_session :app, on_mount: {CabWeb.LiveAuth, :current_user} do
      live "/", DashboardLive
      live "/club", ClubLive
      live "/t/:id", TournamentLive
      live "/t/:id/setup", SetupLive
      live "/t/:id/r/:n/checkin", CheckinLive
      live "/t/:id/r/:n/draw", DrawLive
      live "/t/:id/r/:n/ballots", BallotsLive
    end
  end

  scope "/auth", CabWeb do
    pipe_through :browser

    get "/logout", AuthController, :logout
    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
  end

  scope "/api/public", CabWeb do
    pipe_through :public_api

    get "/tournaments", PublicApiController, :tournaments
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:cab, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: CabWeb.Telemetry

      # DEV ONLY: session user switcher (bypasses OAuth).
      get "/switch-user", CabWeb.DevSessionController, :switch

      # DEV ONLY: debug panel — auto-generate participants (bots).
      live_session :dev_debug, on_mount: {CabWeb.LiveAuth, :current_user} do
        live "/debug", CabWeb.DevDebugLive
      end
    end
  end
end
