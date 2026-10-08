defmodule CabWeb.RegistrationController do
  @moduledoc """
  THE one registration URL (v3.1): `/r/:session_uuid` is what the
  head gives out — it serves everyone. A guest fills name + role and
  gets a permanent personal `/l/:code` URL; a signed-in user gets the
  form prefilled (role pills only) and signs up as themselves. Any
  other stage serves the "registration closed" notice.
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

  # a signed-in user registers as themselves — no guest link involved
  defp create_signed_in(conn, user, session, params) do
    kind = params["as"] || ""

    with true <- kind in ["speak", "judge"],
         {:ok, _participant} <- Sessions.signup(user, session, kind) do
      conn
      |> put_flash(:info, "registered to #{kind}")
      |> redirect(to: ~p"/c/#{session.club.uuid}/s/#{session.uuid}")
    else
      false ->
        conn
        |> put_flash(:error, ~s(sign up "as" must be "speak" or "judge"))
        |> redirect(to: ~p"/r/#{session.uuid}")

      {:error, :conflict, message} ->
        conn
        |> put_flash(:error, message)
        |> redirect(to: ~p"/c/#{session.club.uuid}/s/#{session.uuid}")

      {:error, message} ->
        conn
        |> put_flash(:error, error_message(message))
        |> redirect(to: ~p"/c/#{session.club.uuid}/s/#{session.uuid}")
    end
  end

  # POST /r/:session_uuid {"name", "as"} — guest user + engine signup
  # + link row, then the personal-link page (the URL must be SHOWN,
  # so this render is the one deliberate exception to redirect+flash)
  def create(conn, %{"session_uuid" => session_uuid} = params) do
    with_session(conn, session_uuid, fn conn, session, state ->
      case conn.assigns[:current_user] do
        %Cab.Accounts.User{} = user -> create_signed_in(conn, user, session, params)
        nil -> create_guest(conn, session, state, params)
      end
    end)
  end

  defp create_guest(conn, session, state, params) do
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
