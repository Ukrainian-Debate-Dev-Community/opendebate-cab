defmodule CabWeb.RegistrationController do
  @moduledoc """
  THE one registration URL (v3.1): `/r/:session_uuid` is what the
  head gives out - it serves everyone. A guest fills name + role and
  gets a permanent personal `/l/:code` URL; a signed-in user gets the
  form prefilled (role pills only) and signs up as themselves; only
  guests answer the club's own registration form fields. Any
  other stage serves the "registration closed" notice.
  """

  use CabWeb, :controller

  alias Cab.{Links, Sessions}
  alias Cab.Sessions.Session

  # GET /r/:session_uuid - the form while :signup, the notice after
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

  # a signed-in user registers as themselves - no guest link involved
  defp create_signed_in(conn, user, session) do
    result =
      case Cab.Invitations.pending(session, user) do
        nil -> Sessions.signup(user, session)
        invitation -> Cab.Invitations.accept(invitation, user)
      end

    case result do
      {:ok, _participant} ->
        conn
        |> put_flash(:info, gettext("You are registered."))
        |> redirect(to: ~p"/c/#{session.club.uuid}/s/#{session.uuid}")

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

  # POST /r/:session_uuid {"name"} - guest user + engine signup
  # + link row, then the personal-link page (the URL must be SHOWN,
  # so this render is the one deliberate exception to redirect+flash)
  def create(conn, %{"session_uuid" => session_uuid} = params) do
    with_session(conn, session_uuid, fn conn, session, state ->
      case conn.assigns[:current_user] do
        %Cab.Accounts.User{} = user -> create_signed_in(conn, user, session)
        nil -> create_guest(conn, session, state, params)
      end
    end)
  end

  # the club's own form fields come after the name; an e-mail answer
  # gets the personal link sent there too
  defp create_guest(conn, session, state, params) do
    case Links.register_guest(session, params["name"], answer_params(params)) do
      {:ok, link} ->
        render(conn, :created,
          club: session.club,
          session: session,
          link: link,
          personal_url: url(~p"/l/#{link.code}"),
          mail: mail_link(link, session, state),
          page_title: gettext("%{club} — Registered", club: session.club.name)
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

  defp answer_params(%{"answers" => %{} = answers}), do: answers
  defp answer_params(_params), do: %{}

  # {:sent, address} | {:failed, address} | nil (no e-mail given)
  defp mail_link(link, session, state) do
    case Core.Forms.first_value(link.answers, "email") do
      nil ->
        nil

      address ->
        case CabWeb.Emails.guest_registered(address, link, session, state.event["name"]) do
          :ok -> {:sent, address}
          {:error, _reason} -> {:failed, address}
        end
    end
  end

  defp render_form(conn, session, state, params, errors) do
    render(conn, :new,
      club: session.club,
      session: session,
      state: state,
      name: params["name"],
      fields: session.club.guest_form,
      answers: answer_params(params),
      errors: form_errors(session.club.guest_form, errors),
      page_title: gettext("%{club} — Register", club: session.club.name)
    )
  end

  # the name's message as is; the answers' codes worded per field
  defp form_errors(definition, errors) do
    {answers, rest} = Map.split_with(errors, &match?({{:answer, _id}, _code}, &1))
    codes = Map.new(answers, fn {{:answer, id}, code} -> {id, code} end)
    Map.merge(rest, CabWeb.FormComponents.answer_errors(definition, codes))
  end

  defp render_closed(conn, session, state) do
    render(conn, :closed,
      club: session.club,
      session: session,
      state: state,
      page_title: gettext("%{club} — Registration closed", club: session.club.name)
    )
  end

  # the shared URL is public: resolve the session or 404; engine
  # trouble falls back to the club's public session page with a flash
  defp with_session(conn, session_uuid, fun) do
    with %Session{} = session <- Sessions.get_by_uuid(session_uuid),
         {:ok, state} <- Sessions.state(session) do
      conn
      |> assign(:club_role, Cab.Clubs.role_for(session.club, conn.assigns[:current_user]))
      |> fun.(session, state)
    else
      nil ->
        conn |> CabWeb.ErrorHTML.respond(404)

      {:error, message} ->
        conn
        |> put_flash(:error, error_message(message))
        |> redirect(to: ~p"/")
    end
  end

  defp error_message(message) when is_binary(message), do: message
  defp error_message(_other), do: gettext("registration is unavailable right now")
end
