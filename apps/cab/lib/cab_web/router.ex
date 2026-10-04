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

  # THE CANONICAL EIGHT (design/v2-stages.md, 2026-10-04): every
  # screen is one of P1-P8; every link/redirect lands on one of them.
  scope "/", CabWeb do
    pipe_through :browser

    # P2 (anonymous front) / P3 (signed-in cabinet)
    get "/", PageController, :home

    # P1 — the ONLY auth entry; /auth/:provider is just the hop
    get "/signin", SigninController, :show
  end

  # Role-scoped HTML trees (tabbycat-style): the URL names the view,
  # CabWeb.ClubScope (plugged in each controller) enforces the right
  # to it. Forms POST to controller actions in the same tree.
  scope "/c/:club_uuid", CabWeb do
    pipe_through :browser

    # public tree: P4 club welcome + P7 standings; join is the HTML
    # twin of the join-requests API action (redirect + flash)
    get "/", ClubPublicController, :show
    get "/standings", ClubPublicController, :standings
    post "/join", ClubPublicController, :join

    # P6 — THE session page, public and stage-aware. Its actions are
    # identity-gated, not tree-gated: a member judge, the head and a
    # guest judge (session identity from /l/:code) all ballot here;
    # anyone cancels only their OWN registration.
    get "/s/:session_uuid", SessionPageController, :show

    post "/s/:session_uuid/signups/:participant_id/remove",
         SessionPageController,
         :cancel_signup

    get "/s/:session_uuid/rooms/:id/ballot", SessionPageController, :ballot
    post "/s/:session_uuid/rooms/:id/ballot", SessionPageController, :submit_ballot

    # member tree: P5 my-club page + registration (ONE entry: form
    # with role pills) and cancel own registration
    get "/member", MemberController, :show
    get "/member/sessions/:session_uuid/register", MemberController, :register
    post "/member/sessions/:session_uuid/signups", MemberController, :signup

    post "/member/sessions/:session_uuid/signups/:participant_id/remove",
         MemberController,
         :cancel_signup

    # owner tree: P8 console (?tab= section nav) with the ballot and
    # compose sub-pages reachable from its Rooms tab — the head
    # controls everything from here
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

    # owner registration surface (M6): issue a guest link by hand,
    # revoke one — the shared /r/:session_uuid URL lives below
    post "/owner/sessions/:session_uuid/links", OwnerController, :issue_link
    post "/owner/links/:id/revoke", OwnerController, :revoke_link
  end

  # M6 guest access (launch-timeline L2). /r/:session_uuid is the
  # PUBLIC shared registration URL the head gives out; /l/:code is a
  # guest's permanent personal link — the code IS the identity:
  # opening it signs the browser session in as the guest and lands
  # on P6, where their cancel/ballot actions work by that identity.
  scope "/", CabWeb do
    pipe_through :browser

    get "/r/:session_uuid", GuestRegistrationController, :new
    post "/r/:session_uuid", GuestRegistrationController, :create

    get "/l/:code", GuestLinkController, :show
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

    # guest links (head only): list, issue by hand, revoke. The
    # public shared URL has no API twin — it IS an HTML flow.
    get "/sessions/:uuid/links", LinkController, :index
    post "/sessions/:uuid/links", LinkController, :create
    delete "/links/:id", LinkController, :delete
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
