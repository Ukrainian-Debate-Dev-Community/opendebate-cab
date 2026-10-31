defmodule PublicWeb.Router do
  use PublicWeb, :router

  # Public pages read nothing about the visitor: no session, no cookie.
  # They look the same for everyone, content managers included.
  pipeline :public do
    plug :accepts, ["html"]
    plug PublicWeb.Locale
    plug :put_root_layout, html: {PublicWeb.Layouts, :root}
    plug :put_secure_browser_headers
  end

  # /manage: the only place that knows who is signed in; 404 for anyone
  # without the content-manager role, so the public never sees it exists.
  pipeline :manage do
    plug :accepts, ["html"]
    plug PublicWeb.ManageAccess
    plug PublicWeb.Locale
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_root_layout, html: {PublicWeb.Layouts, :root}
    plug :put_secure_browser_headers
  end

  # the event request form: the one public page with a session, only
  # for its CSRF token (the rest of the public site reads nothing)
  pipeline :public_form do
    plug :accepts, ["html"]
    plug PublicWeb.Locale
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_root_layout, html: {PublicWeb.Layouts, :root}
    plug :put_secure_browser_headers
  end

  scope "/", PublicWeb do
    # the container health check
    get "/healthz", HealthController, :show
    get "/calendar.ics", CalendarController, :ics
    get "/calendar/:id/ics", CalendarController, :event_ics
    # the language menu: sets its own cookie, never the session
    get "/locale/:locale", LocaleController, :set
  end

  scope "/", PublicWeb do
    pipe_through :public

    get "/", PageController, :home
    get "/about", PageController, :about
    get "/news", NewsController, :index
    get "/news/:slug", NewsController, :show
    get "/calendar", CalendarController, :index
    get "/clubs", ClubController, :index
    get "/clubs/:uuid", ClubController, :show
  end

  scope "/", PublicWeb do
    pipe_through :public_form

    get "/calendar/request", EventRequestController, :new
    post "/calendar/request", EventRequestController, :create
  end

  # after /calendar/request, which it would otherwise take
  scope "/", PublicWeb do
    pipe_through :public

    get "/calendar/:id", CalendarController, :show
  end

  scope "/manage", PublicWeb.Manage do
    pipe_through :manage

    get "/", DashController, :show

    get "/news", NewsController, :index
    get "/news/new", NewsController, :new
    post "/news", NewsController, :create
    get "/news/:id/edit", NewsController, :edit
    put "/news/:id", NewsController, :update
    post "/news/:id/publish", NewsController, :publish
    post "/news/:id/unpublish", NewsController, :unpublish

    get "/calendar", CalendarController, :index
    post "/calendar/public", CalendarController, :set_public
    get "/events/new", EventController, :new
    post "/events", EventController, :create
    get "/events/:id", EventController, :show
    get "/events/:id/edit", EventController, :edit
    put "/events/:id", EventController, :update
    delete "/events/:id", EventController, :delete
    post "/events/:id/visibility", EventController, :visibility

    get "/tags", TagController, :index
    post "/tags", TagController, :create
    get "/tags/:id/edit", TagController, :edit
    put "/tags/:id", TagController, :update
    delete "/tags/:id", TagController, :delete

    get "/requests", RequestController, :index
    post "/requests/:id/decline", RequestController, :decline
    post "/requests/form/fields", RequestController, :add_field
    post "/requests/form/fields/:field_id", RequestController, :update_field
    post "/requests/form/fields/:field_id/remove", RequestController, :remove_field
    post "/requests/form/fields/:field_id/move/:direction", RequestController, :move_field

    get "/people", PeopleController, :index
    post "/people", PeopleController, :grant
    delete "/people/:user_id", PeopleController, :revoke
  end
end
