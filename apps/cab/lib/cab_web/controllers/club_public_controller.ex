defmodule CabWeb.ClubPublicController do
  use CabWeb, :controller

  alias Cab.{Clubs, Sessions, Standings}
  alias Cab.Sessions.Session

  plug CabWeb.ClubScope,
       [source: :club, require: :public] when action in [:show, :standings, :register]

  plug CabWeb.ClubScope,
       [source: :club, require: :authenticated] when action in [:join_form, :join]

  # GET /c/:club_uuid - the club page, a PROFILE VIEW: about card
  # (meeting info, description, contacts), recent finished sessions,
  # join CTA; while the club's current session takes sign-ups, the
  # registration section (#register) is the page's gold action. The
  # owner edits the same page in place at /owner.
  def show(conn, params) do
    render_show(conn, registration(conn, Map.take(params, ["session"]), %{}))
  end

  # POST /c/:club_uuid/register {"session", "name", "answers"} - the
  # section's form: a guest gets a personal link (shown in the section),
  # a signed-in person signs up as themselves with their answers
  def register(conn, params) do
    club = conn.assigns.club

    with %Session{} = session <- Sessions.get_for_club(club, params["session"] || ""),
         {:ok, state} <- Sessions.state(%{session | club: club}) do
      case {account(conn.assigns.current_user), state.stage} do
        {_viewer, stage} when stage != :signup ->
          conn
          |> put_flash(:error, gettext("Registration is closed for this session."))
          |> redirect(to: ~p"/c/#{club.uuid}")

        {nil, :signup} ->
          register_guest(conn, %{session | club: club}, state, params)

        {user, :signup} ->
          register_account(conn, %{session | club: club}, user, params)
      end
    else
      nil ->
        conn |> CabWeb.ErrorHTML.respond(404)

      {:error, message} ->
        conn
        |> put_flash(:error, registration_error(message))
        |> redirect(to: ~p"/c/#{club.uuid}")
    end
  end

  defp register_account(conn, session, user, params) do
    case Cab.Registrations.register(user, session, answer_params(params)) do
      {:ok, _participant_id} ->
        conn
        |> put_flash(:info, gettext("You are registered."))
        |> redirect(to: register_path(session))

      {:error, {:answers, codes}} ->
        {_kind, fields, _values} = Cab.Registrations.form_for(session.club, user)
        errors = CabWeb.FormComponents.answer_errors(fields, codes)

        conn
        |> put_status(422)
        |> render_show(registration(conn, params, errors))

      {:error, :conflict, message} ->
        conn |> put_flash(:error, message) |> redirect(to: ~p"/c/#{session.club.uuid}")

      {:error, message} ->
        conn
        |> put_flash(:error, registration_error(message))
        |> redirect(to: ~p"/c/#{session.club.uuid}")
    end
  end

  defp register_guest(conn, session, state, params) do
    case CabWeb.BotGuard.check(conn, params, {:guest, session}) do
      :ok ->
        create_guest(conn, session, state, params)

      {:limited, seconds} ->
        conn
        |> CabWeb.BotGuard.limited(seconds)
        |> render_show(registration(conn, params, %{}))

      {:error, message} ->
        conn
        |> put_status(422)
        |> render_show(registration(conn, params, %{turnstile: message}))
    end
  end

  defp create_guest(conn, session, state, params) do
    case Cab.Links.register_guest(session, params["name"], answer_params(params)) do
      {:ok, link} ->
        done = %{
          link: link,
          personal_url: url(~p"/l/#{link.code}"),
          mail: mail_link(link, session, state)
        }

        conn
        |> CabWeb.Caching.no_store()
        |> render_show(%{registration(conn, %{"session" => session.uuid}, %{}) | done: done})

      {:error, :conflict, message} ->
        conn |> put_flash(:error, message) |> redirect(to: ~p"/c/#{session.club.uuid}")

      {:error, %{} = errors} ->
        errors = guest_errors(Cab.Clubs.guest_fields(session.club), errors)
        conn |> put_status(422) |> render_show(registration(conn, params, errors))

      {:error, message} ->
        conn
        |> put_status(422)
        |> render_show(registration(conn, params, %{name: registration_error(message)}))
    end
  end

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

  # the name's message as is; the answers' codes worded per field
  defp guest_errors(fields, errors) do
    {answers, rest} = Map.split_with(errors, &match?({{:answer, _id}, _code}, &1))
    codes = Map.new(answers, fn {{:answer, id}, code} -> {id, code} end)
    Map.merge(rest, CabWeb.FormComponents.answer_errors(fields, codes))
  end

  defp render_show(conn, registration) do
    club = conn.assigns.club

    render(conn, :show,
      recent: Sessions.club_sessions(club),
      members: Clubs.list_members(club),
      registration: registration,
      page_title: club.name
    )
  end

  @doc "The club page's registration section, with this session chosen."
  def register_path(%Session{} = session),
    do: ~p"/c/#{session.club.uuid}?#{[session: session.uuid]}" <> "#register"

  # the registration section, or nil: every session taking sign-ups to
  # choose from (params["session"], else the nearest one the viewer is
  # not registered for) and what this viewer sees of the chosen one -
  # :guest, :member or :account (a form), :registered; with none open,
  # the current session's :closed or :running. `params`/`errors`
  # refill a form
  defp registration(conn, params, errors) do
    club = conn.assigns.club

    case Enum.map(Sessions.open_for_club(club), &%{&1 | club: club}) do
      [] ->
        case Sessions.current_for_club(club) do
          nil -> nil
          session -> section(conn, %{session | club: club}, params, errors)
        end

      open ->
        choices = Enum.map(open, &%{session: &1, registered: registered?(conn, &1)})

        chosen =
          Enum.find(open, &(&1.uuid == params["session"])) ||
            Enum.find_value(choices, hd(open), &(!&1.registered && &1.session))

        section = section(conn, chosen, params, errors)
        if length(choices) > 1, do: %{section | choices: choices}, else: section
    end
  end

  defp registered?(conn, session) do
    viewer = conn.assigns.current_user

    cond do
      is_nil(viewer) -> false
      Cab.Links.holds_session?(viewer.id, session) -> true
      user = account(viewer) -> own_signup(session, user) != nil
      true -> false
    end
  end

  defp section(conn, session, params, errors) do
    base = %{
      session: session,
      kind: nil,
      fields: [],
      values: %{},
      name: params["name"],
      errors: errors,
      signup: nil,
      done: nil,
      choices: []
    }

    viewer = conn.assigns.current_user

    case Sessions.stage_of(session) do
      :signup -> signup_section(base, session, viewer, params)
      stage -> %{base | kind: stage}
    end
  end

  defp signup_section(base, session, viewer, params) do
    user = account(viewer)

    cond do
      viewer && Cab.Links.holds_session?(viewer.id, session) ->
        %{base | kind: :registered}

      is_nil(user) ->
        %{
          base
          | kind: :guest,
            fields: Clubs.guest_fields(session.club),
            values: answer_params(params)
        }

      signup = own_signup(session, user) ->
        %{base | kind: :registered, signup: signup}

      true ->
        {kind, fields, saved} = Cab.Registrations.form_for(session.club, user)
        values = if Map.has_key?(params, "answers"), do: answer_params(params), else: saved
        %{base | kind: kind, fields: fields, values: values}
    end
  end

  # the viewer's own engine signup in the session, or nil (engine
  # trouble reads as not registered; the POST checks again)
  defp own_signup(session, user) do
    case Sessions.state(session) do
      {:ok, %{signups: signups}} -> Enum.find(signups, &Sessions.own_participant?(&1, user))
      _error -> nil
    end
  end

  # a real account; a guest's link identity registers as a guest
  defp account(%Cab.Accounts.User{guest: false} = user), do: user
  defp account(_viewer), do: nil

  defp answer_params(%{"answers" => %{} = answers}), do: answers
  defp answer_params(_params), do: %{}

  defp registration_error(message) when is_binary(message), do: message
  defp registration_error(_other), do: gettext("registration is unavailable right now")

  # GET /c/:club_uuid/standings[/:tab] - teams, speakers, adjudicators
  # scoped to this club (RULE 0 passthrough); Clubs is global-only
  def standings(conn, params) do
    club = conn.assigns.club

    case params["tab"] || "teams" do
      # speakers and adjudicators: every finished session of the club at
      # once - only for whoever sees the whole club (a private club's
      # members); someone who played some nights steps through teams
      tab when tab in ~w(speakers adjudicators) ->
        if whole_club?(club, conn) do
          scope = Standings.latest_finished(club)

          conn
          |> CabWeb.Caching.no_store()
          |> render(:standings,
            tab: tab,
            scope: scope,
            whole_club: true,
            rows: if(scope, do: club_rows(tab, club), else: []),
            archive: nil,
            page_title: gettext("%{club} — Standings", club: club.name)
          )
        else
          deny_private_standings(conn, club)
        end

      "teams" = tab ->
        own = own_sessions(club, conn)

        scope =
          case {params["session"], own} do
            # someone who only played here opens on their own latest night
            {nil, [mine | _]} -> standings_scope(club, mine)
            {session, _} -> standings_scope(club, session)
          end

        if standings_allowed?(club, conn, scope) do
          archive = Sessions.archive(club)

          archive =
            if own == [],
              do: archive,
              else: Enum.filter(archive, &(&1.session_uuid in own))

          conn
          |> CabWeb.Caching.no_store()
          |> render(:standings,
            tab: tab,
            scope: scope,
            rows: standings_rows(tab, scope),
            archive: archive,
            page_title: gettext("%{club} — Standings", club: club.name)
          )
        else
          deny_private_standings(conn, club)
        end

      _tab ->
        conn |> CabWeb.ErrorHTML.respond(404)
    end
  end

  # A private club's standings are members-only, but whoever played a
  # night keeps it: for a viewer who is not a member, the finished
  # sessions of this club they took part in, newest first ([] for
  # public clubs and members, who see everything). A guest's nights come
  # from their personal links; an account's from its engine history.
  defp own_sessions(%{is_private: false}, _conn), do: []

  defp own_sessions(club, conn) do
    user = conn.assigns.current_user

    cond do
      is_nil(user) or Clubs.covers?(conn.assigns.club_role, :member) ->
        []

      Map.get(user, :guest, false) ->
        Cab.Links.finished_session_uuids(user, club)

      true ->
        for row <- Sessions.user_history(user), row.club_uuid == club.uuid, do: row.session_uuid
    end
  end

  # default: the club's latest finished session; ?session=uuid walks
  # the archive (only finished sessions resolve)
  defp standings_scope(club, nil), do: Standings.latest_finished(club)

  defp standings_scope(club, session_uuid) do
    case Sessions.get_for_club(club, session_uuid) do
      nil -> nil
      session -> Standings.finished(%{session | club: club})
    end
  end

  # private = standings only: members (ladder) always pass; a guest or
  # user who PLAYED the shown session keeps that session's data - any
  # other session is lost to them
  defp standings_allowed?(%{is_private: false}, _conn, _scope), do: true

  defp standings_allowed?(_club, conn, scope) do
    Clubs.covers?(conn.assigns.club_role, :member) or
      participant_of?(conn.assigns.current_user, scope)
  end

  defp participant_of?(nil, _scope), do: false
  defp participant_of?(_user, nil), do: false

  defp participant_of?(%{node_user_id: id}, %{actor: actor, session: session})
       when is_integer(id) do
    case Cab.EngineApi.list_participants(actor, session.engine_event_id) do
      {:ok, participants} -> Enum.any?(participants, &(&1["user_id"] == id))
      _ -> false
    end
  end

  # a guest has no engine account: their personal link names the place
  defp participant_of?(%{id: user_id}, %{session: session}),
    do: Cab.Links.participant_ids(user_id) != [] and Cab.Links.holds_session?(user_id, session)

  defp participant_of?(_user, _scope), do: false

  defp deny_private_standings(conn, _club) do
    case conn.assigns.current_user do
      nil ->
        conn
        |> put_flash(:error, gettext("This club's standings are for members. Please sign in."))
        |> redirect(to: ~p"/signin")
        |> halt()

      _user ->
        conn
        |> CabWeb.ErrorHTML.respond(403, gettext("This club's standings are for its members."))
    end
  end

  defp whole_club?(%{is_private: false}, _conn), do: true
  defp whole_club?(_club, conn), do: Clubs.covers?(conn.assigns.club_role, :member)

  defp club_rows("speakers", club), do: Standings.club_speakers(club)
  defp club_rows("adjudicators", club), do: Standings.club_adjudicators(club)

  defp standings_rows(_tab, nil), do: []
  defp standings_rows("teams", scope), do: Standings.teams(scope)
  defp standings_rows("speakers", scope), do: Standings.speakers(scope)
  defp standings_rows("adjudicators", scope), do: Standings.adjudicators(scope)

  # GET /c/:club_uuid/join - the join-request FORM: the club form's
  # member fields (none asked: the request alone)
  def join_form(conn, _params) do
    render_join(conn, %{}, %{})
  end

  # POST /c/:club_uuid/join - creates the pending membership with
  # the answers; the head reads them in Requests
  def join(conn, params) do
    club = conn.assigns.club
    user = conn.assigns.current_user

    case CabWeb.BotGuard.check(conn, params, {:join, club, user}) do
      :ok ->
        request_join(conn, club, user, params)

      {:limited, seconds} ->
        conn |> CabWeb.BotGuard.limited(seconds) |> render_join(params, %{})

      {:error, message} ->
        conn |> put_status(422) |> render_join(params, %{turnstile: message})
    end
  end

  defp request_join(conn, club, user, params) do
    case Clubs.request_join(user, club, params) do
      {:ok, _membership} ->
        conn
        |> put_flash(:info, gettext("Request sent. The club head will review it."))
        |> redirect(to: ~p"/c/#{club.uuid}")

      {:error, {:answers, codes}} ->
        errors = CabWeb.FormComponents.answer_errors(Clubs.member_fields(club), codes)
        conn |> put_status(422) |> render_join(params, errors)

      # the row itself refused: already a member or a pending request
      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_flash(:error, join_error(changeset))
        |> redirect(to: ~p"/c/#{club.uuid}")
    end
  end

  defp render_join(conn, params, errors) do
    render(conn, :join,
      fields: Clubs.member_fields(conn.assigns.club),
      answers: answer_params(params),
      errors: errors,
      page_title: gettext("%{club} — Join", club: conn.assigns.club.name)
    )
  end

  defp join_error(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Gettext.dgettext(CabWeb.Gettext, "errors", message, opts)
    end)
    |> Enum.find_value(fn {_field, [message | _rest]} -> message end)
  end
end
