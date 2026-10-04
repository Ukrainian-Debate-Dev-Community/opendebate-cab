defmodule CabWeb.GuestRegistrationController do
  @moduledoc """
  The PUBLIC shared registration URL (M6): `/r/:session_uuid` is what
  the head gives out — no account, no auth. While the session is
  `:signup` it serves the registration form (name + role pills); the
  POST creates the guest user + engine signup + link row and renders
  the page carrying the guest's permanent personal `/l/:code` URL.
  Any other stage serves the "registration closed" notice.
  """

  use CabWeb, :controller

  alias Cab.{Links, Sessions}
  alias Cab.Sessions.Session

  # GET /r/:session_uuid — the form while :signup, the notice after
  def new(conn, %{"session_uuid" => session_uuid} = params) do
    with_session(conn, session_uuid, fn conn, session, state ->
      case state.stage do
        :signup ->
          render_form(conn, session, state, params, %{})

        _stage ->
          render_closed(conn, session, state)
      end
    end)
  end

  # POST /r/:session_uuid {"name", "as"} — guest user + engine signup
  # + link row, then the personal-link page (the URL must be SHOWN,
  # so this render is the one deliberate exception to redirect+flash)
  def create(conn, %{"session_uuid" => session_uuid} = params) do
    with_session(conn, session_uuid, fn conn, session, state ->
      case Links.register_guest(session, params["name"], params["as"] || "") do
        {:ok, link} ->
          render(conn, :created,
            club: session.club,
            session: session,
            link: link,
            personal_url: url(~p"/l/#{link.code}"),
            role: params["as"],
            page_title: "#{session.club.name} · registered"
          )

        {:error, :conflict, _message} ->
          render_closed(conn, session, state)

        {:error, %{} = errors} ->
          conn |> put_status(422) |> render_form(session, state, params, errors)

        {:error, message} ->
          conn
          |> put_status(422)
          |> render_form(session, state, params, %{name: error_message(message)})
      end
    end)
  end

  defp render_form(conn, session, state, params, errors) do
    render(conn, :new,
      club: session.club,
      session: session,
      state: state,
      name: params["name"],
      as: params["as"] || "speak",
      errors: errors,
      page_title: "#{session.club.name} · register"
    )
  end

  defp render_closed(conn, session, state) do
    render(conn, :closed,
      club: session.club,
      session: session,
      state: state,
      page_title: "#{session.club.name} · registration closed"
    )
  end

  # the shared URL is public: resolve the session or 404; engine
  # trouble falls back to the club's public session page with a flash
  defp with_session(conn, session_uuid, fun) do
    with %Session{} = session <- Sessions.get_by_uuid(session_uuid),
         {:ok, state} <- Sessions.state(session) do
      fun.(conn, session, state)
    else
      nil ->
        conn |> send_resp(404, "not found") |> halt()

      {:error, message} ->
        conn
        |> put_flash(:error, error_message(message))
        |> redirect(to: ~p"/")
    end
  end

  defp error_message(message) when is_binary(message), do: message
  defp error_message(_other), do: "registration is unavailable right now"
end
