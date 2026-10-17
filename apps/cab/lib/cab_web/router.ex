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
    plug CabWeb.Locale
  end

  # the API reference: no session, the same for everyone
  pipeline :docs do
    plug :accepts, ["html", "json"]
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :fetch_current_user
    plug CabWeb.RateLimit
  end

  # the API references: /api/<name>/docs beside each API's /api/<name>/v1
  scope "/api", CabWeb do
    pipe_through :docs

    get "/cab/docs", ApiDocsController, :show
    get "/cab/docs/openapi.json", ApiDocsController, :cab_spec
    get "/engine/docs", ApiDocsController, :show_engine
    get "/engine/docs/openapi.yml", ApiDocsController, :engine_spec
    get "/docs", ApiDocsController, :to_cab_docs
  end

  # the container health check: no pipeline, so no session or cookie
  scope "/", CabWeb do
    get "/healthz", HealthController, :show
  end

  # Global pages. Navigation lives in the sidenav, every page's chrome
  # carries only that page's actions, status is written out as words.
  scope "/", CabWeb do
    pipe_through :browser

    # global welcome: public = clubs directory, signed-in = + my
    # clubs / my sessions
    get "/", PageController, :home

    # the ONLY auth entry; /auth/:provider is just the hop
    get "/signin", SigninController, :show
    post "/signin/separate", SigninController, :separate
    # an e-mailed invitation to head a club: sign in, become the head
    get "/head-invitations/:token", HeadInvitationController, :show

    # my page - engine stats verbatim + participation history
    get "/me", MeController, :show

    # the Policy (personal data) and the Terms, linked from the footer;
    # the old /privacy address keeps working
    get "/policy", PageController, :policy
    get "/terms", PageController, :terms
    get "/locale/:locale", LocaleController, :set
    get "/privacy", PageController, :privacy_moved

    # profile - entry only via the sidenav bottom
    get "/account", AccountController, :show
    post "/account", AccountController, :update
    post "/account/claim", AccountController, :claim
    get "/account/link/:provider", AccountController, :link
    post "/account/unlink/:provider", AccountController, :unlink
    get "/account/merge", AccountController, :merge_form
    post "/account/merge", AccountController, :merge

    post "/invitations/:id/accept", InvitationController, :accept
    post "/invitations/:id/decline", InvitationController, :decline

    # platform admin (is_admin; 404 for everyone else). Club creation
    # is ADMIN-ONLY - users can only request membership.
    get "/admin", AdminController, :show
    post "/admin/clubs", AdminController, :create_club
    post "/admin/head", AdminController, :change_head
    post "/admin/merge", AdminController, :merge
    post "/admin/clubs/:uuid/archive", AdminController, :archive
    post "/admin/head-invitations/:id/resend", AdminController, :resend_head_invitation
    post "/admin/head-invitations/:id/cancel", AdminController, :cancel_head_invitation

    # global standings: four tabs, RULE 0 - engine output verbatim
    # per session (default: the latest finished platform-wide)
    get "/standings", StandingsController, :index
    get "/standings/:tab", StandingsController, :show
  end

  # Role-scoped HTML trees (tabbycat-style): the URL names the view,
  # CabWeb.ClubScope (plugged in each controller) enforces the right
  # to it. Forms POST to controller actions in the same tree.
  scope "/c/:club_uuid", CabWeb do
    pipe_through :browser

    # public tree: the club page (profile view) + the four standings
    # tabs + the join-request FORM (required answers, never a bare
    # button)
    get "/", ClubPublicController, :show
    get "/standings", ClubPublicController, :standings
    get "/standings/:tab", ClubPublicController, :standings
    get "/join", ClubPublicController, :join_form
    post "/join", ClubPublicController, :join

    # THE session page, public and stage-aware (reached via the
    # sidenav Rooms item). Its actions are identity-gated, not
    # tree-gated: a member judge, the head and a guest judge (session
    # identity from /l/:code) all ballot here; anyone cancels only
    # their OWN registration.
    live_session :club_public, on_mount: [CabWeb.Locale, {CabWeb.LiveScope, :club}] do
      live "/s/:session_uuid", SessionLive, :show
      live "/s/:session_uuid/rooms/:id", RoomLive, :show
    end

    post "/s/:session_uuid/signups/:participant_id/remove",
         SessionPageController,
         :cancel_signup

    # ONE room URL for every viewer - identity picks the render and
    # gates the actions (chair/head set the motion, ballot below)
    post "/s/:session_uuid/rooms/:id/motion", SessionPageController, :motion

    get "/s/:session_uuid/rooms/:id/ballot", SessionPageController, :ballot
    post "/s/:session_uuid/rooms/:id/ballot", SessionPageController, :submit_ballot

    # a team's feedback on its room's adjudicator (team members only)
    get "/s/:session_uuid/rooms/:id/feedback", FeedbackController, :new
    post "/s/:session_uuid/rooms/:id/feedback", FeedbackController, :create

    # the roster - the only member-gated page (v3.1: the member tree
    # is gone; registration lives at /r/:sess, the club page is the
    # sessions archive)
    get "/members", MemberController, :members

    # owner tree: /owner is the club page as an edit-in-place form
    # with the Club Sessions table and the open-session form; members
    # carries requests and removal; /owner/s/:sess runs a session.
    get "/owner", OwnerController, :club
    post "/owner/club", OwnerController, :update_club
    get "/owner/form", OwnerController, :guest_form
    get "/owner/form/preview", OwnerController, :preview_form
    post "/owner/form/fields", OwnerController, :add_field
    post "/owner/form/fields/:field_id", OwnerController, :update_field
    post "/owner/form/fields/:field_id/remove", OwnerController, :remove_field
    post "/owner/form/fields/:field_id/move/:direction", OwnerController, :move_field
    post "/owner/sessions", OwnerController, :open_session
    get "/owner/members", OwnerController, :members
    post "/owner/join-requests/:id/approve", OwnerController, :approve
    post "/owner/join-requests/:id/decline", OwnerController, :decline
    post "/owner/members/:user_id/remove", OwnerController, :remove_member

    live_session :club_owner,
      on_mount: [CabWeb.Locale, {CabWeb.LiveScope, :club}, {CabWeb.LiveScope, :owner}] do
      live "/owner/s/:session_uuid", OwnerSessionLive, :show
    end

    post "/owner/sessions/:session_uuid/start", OwnerController, :start
    post "/owner/sessions/:session_uuid/close-signups", OwnerController, :close_signups
    post "/owner/sessions/:session_uuid/reopen-signups", OwnerController, :reopen_signups

    post "/owner/sessions/:session_uuid/reopen-registration",
         OwnerController,
         :reopen_registration

    post "/owner/sessions/:session_uuid/signups", OwnerController, :add_person

    post "/owner/sessions/:session_uuid/signups/:participant_id/remove",
         OwnerController,
         :remove_signup

    post "/owner/sessions/:session_uuid/rooms", OwnerController, :make_rooms
    post "/owner/sessions/:session_uuid/rooms/delete", OwnerController, :delete_rooms
    post "/owner/sessions/:session_uuid/finish", OwnerController, :finish
    get "/owner/sessions/:session_uuid/delete", OwnerController, :confirm_delete
    post "/owner/sessions/:session_uuid/cancel", OwnerController, :cancel_session
    get "/owner/sessions/:session_uuid/responses", OwnerController, :responses
    get "/owner/sessions/:session_uuid/responses/csv", OwnerController, :responses_csv
  end

  # /r/:session_uuid is THE one registration URL (v3.1): guests get a
  # personal link, signed-in users sign up as themselves; /l/:code is a
  # guest's permanent personal link - the code IS the identity:
  # opening it signs the browser session in as the guest and lands
  # on the session page, where their cancel/ballot actions work by
  # that identity.
  scope "/", CabWeb do
    pipe_through :browser

    get "/r/:session_uuid", RegistrationController, :new
    post "/r/:session_uuid", RegistrationController, :create

    get "/l/:code", GuestLinkController, :show
    post "/l/:code/claim", GuestLinkController, :claim
  end

  # JSON API over the same contexts (club creation is admin-only:
  # the /admin HTML form or the `mix cab.seed_club` task)
  scope "/api/cab/v1", CabWeb.Api do
    pipe_through :api

    get "/clubs", ClubController, :index
    get "/clubs/:uuid", ClubController, :show
    patch "/clubs/:uuid", ClubController, :update
    get "/clubs/:uuid/members", ClubController, :members
    get "/clubs/:uuid/registration-form", ClubController, :registration_form
    put "/clubs/:uuid/registration-form", ClubController, :replace_registration_form
    delete "/clubs/:uuid/members/:user_id", ClubController, :remove_member
    post "/clubs/:uuid/join-requests", JoinRequestController, :create
    patch "/join-requests/:id", JoinRequestController, :update

    post "/clubs/:uuid/sessions", SessionController, :create
    get "/sessions/:uuid", SessionController, :show
    delete "/sessions/:uuid", SessionController, :delete
    post "/sessions/:uuid/start", SessionController, :start
    post "/sessions/:uuid/close-signups", SessionController, :close_signups
    post "/sessions/:uuid/reopen-signups", SessionController, :reopen_signups
    post "/sessions/:uuid/reopen-registration", SessionController, :reopen_registration
    put "/sessions/:uuid/room-count", SessionController, :room_count
    post "/sessions/:uuid/signups", SignupController, :create
    delete "/sessions/:uuid/signups/:participant_id", SignupController, :delete
    post "/sessions/:uuid/rooms", RoomController, :create
    delete "/sessions/:uuid/rooms", RoomController, :delete
    post "/sessions/:uuid/finish", SessionController, :finish

    post "/rooms/:id/motion", RoomController, :motion
    post "/rooms/:id/ballot", RoomController, :ballot
    post "/rooms/:id/feedback", FeedbackController, :create
    get "/sessions/:uuid/feedback", FeedbackController, :index

    # guest links (head only): list, add a guest by hand. A guest
    # leaves through DELETE signups like everyone else. The public
    # shared URL has no API twin - it IS an HTML flow.
    get "/sessions/:uuid/people", PeopleController, :search
    post "/sessions/:uuid/invitations", PeopleController, :invite

    get "/sessions/:uuid/links", LinkController, :index
    get "/sessions/:uuid/responses", LinkController, :responses
    post "/sessions/:uuid/links", LinkController, :create
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

      # e-mails the local adapter kept instead of sending
      forward "/mailbox", Plug.Swoosh.MailboxPreview

      # DEV ONLY: session user switcher (bypasses OAuth).
      get "/switch-user", CabWeb.DevSessionController, :switch
    end
  end

  # short links (<host>/<code>[/<room>]) come LAST: every
  # named route above wins, and a code always holds a digit
  scope "/", CabWeb do
    pipe_through :browser

    get "/:short", ShortLinkController, :session
    get "/:short/:room", ShortLinkController, :room
  end
end
