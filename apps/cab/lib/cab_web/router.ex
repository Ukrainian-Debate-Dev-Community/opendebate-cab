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
    plug :fetch_session
    plug :fetch_current_user
  end

  scope "/", CabWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Role-scoped HTML trees (tabbycat-style): the URL names the view,
  # CabWeb.ClubScope (plugged in each controller) enforces the right
  # to it. Forms POST to controller actions in the same tree.
  scope "/c/:club_uuid", CabWeb do
    pipe_through :browser

    # public tree: profile + history + session detail; join is the
    # HTML twin of the join-requests API action (redirect + flash)
    get "/", ClubPublicController, :show
    get "/s/:session_uuid", ClubPublicController, :session
    post "/join", ClubPublicController, :join

    # member tree: sessions, registration (ONE entry: form with role
    # pills), cancel own registration, the room judge's ballot
    get "/member", MemberController, :show
    get "/member/sessions/:session_uuid/register", MemberController, :register
    post "/member/sessions/:session_uuid/signups", MemberController, :signup

    post "/member/sessions/:session_uuid/signups/:participant_id/remove",
         MemberController,
         :cancel_signup

    get "/member/rooms/:id/ballot", MemberController, :ballot
    post "/member/rooms/:id/ballot", MemberController, :submit_ballot

    # owner tree: approvals, club settings, open session, signups on
    # behalf, rooms (auto + composed + rebuild), ballot, reopen,
    # finish, cancel — the head controls everything from here
    get "/owner", OwnerController, :show
    post "/owner/join-requests/:id/approve", OwnerController, :approve
    post "/owner/join-requests/:id/decline", OwnerController, :decline
    post "/owner/club", OwnerController, :update_club
    post "/owner/members/:user_id/remove", OwnerController, :remove_member
    post "/owner/sessions", OwnerController, :open_session
    post "/owner/sessions/:session_uuid/close-signups", OwnerController, :close_signups
    post "/owner/sessions/:session_uuid/reopen-signups", OwnerController, :reopen_signups
    post "/owner/sessions/:session_uuid/signups", OwnerController, :add_signup

    post "/owner/sessions/:session_uuid/signups/:participant_id/remove",
         OwnerController,
         :remove_signup

    get "/owner/sessions/:session_uuid/compose", OwnerController, :compose
    post "/owner/sessions/:session_uuid/rooms", OwnerController, :make_rooms
    post "/owner/sessions/:session_uuid/rooms/delete", OwnerController, :delete_rooms
    post "/owner/sessions/:session_uuid/finish", OwnerController, :finish
    post "/owner/sessions/:session_uuid/cancel", OwnerController, :cancel_session
    post "/owner/rooms/:id/motion", OwnerController, :motion
    get "/owner/rooms/:id/ballot", OwnerController, :ballot
    post "/owner/rooms/:id/ballot", OwnerController, :submit_ballot
    post "/owner/rooms/:id/reopen", OwnerController, :reopen
  end

  # JSON API over the same contexts (club creation is the
  # `mix cab.seed_club` task, not an endpoint)
  scope "/api/v1", CabWeb.Api do
    pipe_through :api

    get "/clubs/:uuid", ClubController, :show
    patch "/clubs/:uuid", ClubController, :update
    get "/clubs/:uuid/members", ClubController, :members
    delete "/clubs/:uuid/members/:user_id", ClubController, :remove_member
    post "/clubs/:uuid/join-requests", JoinRequestController, :create
    patch "/join-requests/:id", JoinRequestController, :update

    post "/clubs/:uuid/sessions", SessionController, :create
    get "/sessions/:uuid", SessionController, :show
    delete "/sessions/:uuid", SessionController, :delete
    post "/sessions/:uuid/close-signups", SessionController, :close_signups
    post "/sessions/:uuid/reopen-signups", SessionController, :reopen_signups
    post "/sessions/:uuid/signups", SignupController, :create
    delete "/sessions/:uuid/signups/:participant_id", SignupController, :delete
    post "/sessions/:uuid/rooms", RoomController, :create
    delete "/sessions/:uuid/rooms", RoomController, :delete
    post "/sessions/:uuid/finish", SessionController, :finish

    post "/rooms/:id/motion", RoomController, :motion
    post "/rooms/:id/ballot", RoomController, :ballot
    patch "/rooms/:id/reopen", RoomController, :reopen
  end

  scope "/auth", CabWeb do
    pipe_through :browser

    get "/logout", AuthController, :logout
    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
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
    end
  end
end
