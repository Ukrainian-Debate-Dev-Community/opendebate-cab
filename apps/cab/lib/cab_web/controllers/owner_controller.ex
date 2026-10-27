defmodule CabWeb.OwnerController do
  use CabWeb, :controller

  alias Cab.{Clubs, Links, Sessions}
  alias Cab.Clubs.{Club, Membership}
  alias Core.Forms
  alias Cab.Sessions.Session

  plug CabWeb.ClubScope, source: :club, require: :owner

  # ---------------------------------------------------------------
  # The club page, owner path: the SAME profile page as /c/:club but
  # as an edit-in-place form (Save lives in the chrome)
  # ---------------------------------------------------------------

  # GET /c/:club_uuid/owner - the club page as an edit-in-place form,
  # with the session archive and the open-session form below (v3.1:
  # there is no separate owner Sessions page)
  def club(conn, _params) do
    club = conn.assigns.club

    render(conn, :club,
      archive: Sessions.club_sessions(club),
      live: Sessions.current_for_club(club),
      page_title: gettext("%{club} — Edit", club: club.name)
    )
  end

  @profile_fields ~w(name city meeting_info description contacts is_private formats languages audiences format_other language_other)

  # POST /c/:club_uuid/owner/club - the in-place save; twin of
  # PATCH /api/cab/v1/clubs/:uuid
  def update_club(conn, params) do
    # an unticked group sends nothing, so the form means "none of them"
    attrs =
      %{"formats" => [], "languages" => [], "audiences" => []}
      |> Map.merge(Map.take(params, @profile_fields))
      |> one_choice(~w(formats languages audiences))

    case Clubs.update_club(conn.assigns.club, attrs, logo_change(params)) do
      {:ok, _club} ->
        conn
        |> put_flash(:info, gettext("Club profile saved."))
        |> redirect(to: ~p"/c/#{conn.assigns.club.uuid}/owner")

      {:error, reason} ->
        conn
        |> put_flash(:error, update_error(reason))
        |> redirect(to: ~p"/c/#{conn.assigns.club.uuid}/owner")
    end
  end

  # a new file wins over the remove box; no file and no tick keeps it
  defp logo_change(%{"logo" => %Plug.Upload{path: path}}), do: {:file, path}
  defp logo_change(%{"remove_logo" => "yes"}), do: :remove
  defp logo_change(_params), do: :keep

  defp update_error(:type), do: gettext("The logo must be a PNG, JPEG or WebP image.")
  defp update_error(:size), do: gettext("The logo must be at most 1 MB.")

  defp update_error(%Ecto.Changeset{} = changeset), do: CabWeb.ClubProfile.save_error(changeset)

  defp update_error(_engine_error), do: gettext("Something went wrong, try again.")

  # ---------------------------------------------------------------
  # The guest registration form: the club's own fields after the
  # built-in name on /r/:sess. Core.Forms edits the definition and
  # its editor component renders the page; the club keeps it.
  # ---------------------------------------------------------------

  # GET /c/:club_uuid/owner/form[?edit=<field id>] - the fields in
  # order, then the add form (or the one field being edited)
  def guest_form(conn, params) do
    editing = params["edit"] && Forms.field(Clubs.guest_form(conn.assigns.club), params["edit"])
    render_guest_form(conn, editing, %{}, %{})
  end

  # GET /c/:club_uuid/owner/form/preview - what a guest sees on /r for
  # this club, with nothing to send
  def preview_form(conn, _params) do
    render(conn, :guest_form_preview,
      fields: Clubs.guest_fields(conn.assigns.club),
      page_title: gettext("%{club} - Registration form", club: conn.assigns.club.name)
    )
  end

  # POST /c/:club_uuid/owner/form/fields
  def add_field(conn, params) do
    conn
    |> edit_form(&Forms.add_field(&1, params, Club.form_attrs()), gettext("Field added."))
    |> on_field_error(nil, params)
  end

  # POST /c/:club_uuid/owner/form/fields/:field_id
  def update_field(conn, %{"field_id" => id} = params) do
    conn
    |> edit_form(&Forms.update_field(&1, id, params, Club.form_attrs()), gettext("Field saved."))
    |> on_field_error(Forms.field(Clubs.guest_form(conn.assigns.club), id), params)
  end

  # POST /c/:club_uuid/owner/form/fields/:field_id/remove
  def remove_field(conn, %{"field_id" => id}) do
    conn
    |> edit_form(&Forms.remove_field(&1, id), gettext("Field removed."))
    |> on_field_error(nil, %{})
  end

  # POST /c/:club_uuid/owner/form/fields/:field_id/move/(up|down)
  def move_field(conn, %{"field_id" => id, "direction" => direction})
      when direction in ["up", "down"] do
    conn
    |> edit_form(&Forms.move_field(&1, id, String.to_existing_atom(direction)), nil)
    |> on_field_error(nil, %{})
  end

  def move_field(conn, _params), do: CabWeb.ErrorHTML.respond(conn, 404)

  # a saved edit goes back to the editor; an error comes back as-is
  defp edit_form(conn, edit, info) do
    case Clubs.edit_registration_form(conn.assigns.club, edit) do
      {:ok, _club} ->
        conn = if info, do: put_flash(conn, :info, info), else: conn
        redirect(conn, to: ~p"/c/#{conn.assigns.club.uuid}/owner/form")

      error ->
        {conn, error}
    end
  end

  defp on_field_error(%Plug.Conn{} = conn, _editing, _params), do: conn

  defp on_field_error({conn, {:error, :not_found}}, _editing, _params),
    do: CabWeb.ErrorHTML.respond(conn, 404)

  # the always-asked fields keep their place
  defp on_field_error({conn, {:error, :locked}}, _editing, _params) do
    conn
    |> put_flash(:error, CabWeb.FormComponents.editor_error(:locked))
    |> redirect(to: ~p"/c/#{conn.assigns.club.uuid}/owner/form")
  end

  defp on_field_error({conn, {:error, %{} = errors}}, editing, params),
    do: conn |> put_status(422) |> render_guest_form(editing, params, errors)

  defp render_guest_form(conn, editing, values, errors) do
    render(conn, :guest_form,
      definition: Clubs.guest_form(conn.assigns.club),
      editing: editing,
      values: Map.take(values, ~w(label hint type required options scope)),
      errors: errors,
      page_title: gettext("%{club} - Registration form", club: conn.assigns.club.name)
    )
  end

  # ---------------------------------------------------------------
  # Opening a session (the form lives on /owner)
  # ---------------------------------------------------------------

  # POST /c/:club_uuid/owner/sessions - name + optional date/time and
  # participant limit; lands on the new session's owner surface
  def open_session(conn, params) do
    with {:ok, scheduled_at} <- parse_schedule(conn, params),
         {:ok, limit} <- Sessions.parse_participant_limit(params["max_participants"]),
         {:ok, session} <-
           Sessions.open(
             conn.assigns.current_user,
             conn.assigns.club,
             params["name"],
             scheduled_at,
             limit
           ) do
      conn
      |> put_flash(:info, gettext("Session opened. Registration is open."))
      |> redirect(to: ~p"/c/#{conn.assigns.club.uuid}/owner/s/#{session.uuid}")
    else
      {:error, message} ->
        conn
        |> put_flash(:error, error_message(message))
        |> redirect(to: ~p"/c/#{conn.assigns.club.uuid}/owner")
    end
  end

  # ---------------------------------------------------------------
  # Members page, owner path: roster + join requests (the form's
  # answers shown) + remove
  # ---------------------------------------------------------------

  # GET /c/:club_uuid/owner/members
  def members(conn, _params) do
    club = conn.assigns.club

    render(conn, :members,
      members: Clubs.list_members(club),
      join_requests: Clubs.list_join_requests(club),
      page_title: gettext("%{club} — Members", club: club.name)
    )
  end

  # POST /c/:club_uuid/owner/join-requests/:id/approve
  def approve(conn, %{"id" => id}) do
    with_join_request(conn, id, fn membership ->
      case Clubs.approve_join(membership) do
        {:ok, _} -> {:ok, gettext("Join request approved.")}
        error -> error
      end
    end)
  end

  # POST /c/:club_uuid/owner/join-requests/:id/decline
  def decline(conn, %{"id" => id}) do
    with_join_request(conn, id, fn membership ->
      case Clubs.decline_join(membership) do
        {:ok, _} -> {:ok, gettext("Join request declined.")}
        error -> error
      end
    end)
  end

  # POST /c/:club_uuid/owner/members/:user_id/remove
  def remove_member(conn, %{"user_id" => user_id}) do
    with {user_id, ""} <- Integer.parse(user_id),
         {:ok, _membership} <- Clubs.remove_member(conn.assigns.club, user_id) do
      back_members(conn, info: gettext("Member removed."))
    else
      {:error, message} -> back_members(conn, error: error_message(message))
      _ -> conn |> CabWeb.ErrorHTML.respond(404)
    end
  end

  # ---------------------------------------------------------------
  # The owner session page and its lifecycle actions
  # ---------------------------------------------------------------

  # POST .../owner/sessions/:session_uuid/start - the gold action:
  # closes registration and creates the rooms from the dragged
  # allocator state (only the room count was automatic)
  def start(conn, %{"session_uuid" => session_uuid} = params) do
    with_session(conn, session_uuid, fn session ->
      case params["rooms"] do
        %{} = rooms ->
          case Sessions.start(conn.assigns.current_user, session, compose_spec(rooms)) do
            {:ok, count} -> {:ok, gettext("Session started with %{count} room(s).", count: count)}
            error -> error
          end

        _missing ->
          {:error, gettext("Drag people into the rooms first. Nobody is placed automatically.")}
      end
    end)
  end

  # POST .../owner/sessions/:session_uuid/reopen-registration - from a
  # running session with all rooms still pending: rooms die, the
  # public window opens again
  def reopen_registration(conn, %{"session_uuid" => session_uuid}) do
    with_session(conn, session_uuid, fn session ->
      case Sessions.reopen_registration(conn.assigns.current_user, session) do
        {:ok, _session} -> {:ok, gettext("Rooms deleted. Registration is open again.")}
        error -> error
      end
    end)
  end

  # POST .../owner/sessions/:session_uuid/close-signups
  def close_signups(conn, %{"session_uuid" => session_uuid}) do
    with_session(conn, session_uuid, fn session ->
      case Sessions.close_signups(session) do
        {:ok, _session} ->
          {:ok, gettext("Registration closed. Drag people into the rooms when ready.")}

        error ->
          error
      end
    end)
  end

  # POST .../owner/sessions/:session_uuid/reopen-signups
  def reopen_signups(conn, %{"session_uuid" => session_uuid}) do
    with_session(conn, session_uuid, fn session ->
      case Sessions.reopen_signups(session) do
        {:ok, _session} -> {:ok, gettext("Registration reopened.")}
        error -> error
      end
    end)
  end

  # POST .../owner/sessions/:session_uuid/limit {"max_participants"} -
  # while sign-ups are open; empty = no limit
  def set_limit(conn, %{"session_uuid" => session_uuid} = params) do
    with_session(conn, session_uuid, fn session ->
      case Sessions.set_max_participants(session, params["max_participants"]) do
        {:ok, %Session{max_participants: nil}} -> {:ok, gettext("Participant limit removed.")}
        {:ok, _session} -> {:ok, gettext("Participant limit saved.")}
        error -> error
      end
    end)
  end

  # POST .../owner/sessions/:session_uuid/schedule {"date", "time",
  # "zone"} - the planned start, moved or cleared
  def reschedule(conn, %{"session_uuid" => session_uuid} = params) do
    with_session(conn, session_uuid, fn session ->
      with {:ok, scheduled_at} <- parse_schedule(conn, params),
           {:ok, _session} <- Sessions.reschedule(session, scheduled_at) do
        {:ok, gettext("Start time saved.")}
      end
    end)
  end

  # the date/time block's wall clock, in the zone it was typed in
  defp parse_schedule(conn, params) do
    zone = Cab.TimeZones.for_form(params["zone"], conn.assigns.current_user)
    Sessions.parse_schedule(params["date"], params["time"], zone)
  end

  # POST .../owner/sessions/:session_uuid/signups {"q"} - the add field
  # without JavaScript: an exact member username signs them up, an
  # exact registered user is invited, anything else becomes a guest
  def add_person(conn, %{"session_uuid" => session_uuid} = params) do
    with_session(conn, session_uuid, fn session ->
      with {:ok, state} <- Sessions.state(session) do
        add_resolved(
          conn.assigns.current_user,
          session,
          Cab.Invitations.resolve(conn.assigns.club, session, state.signups, params["q"])
        )
      end
    end)
  end

  @doc false
  def add_resolved(head, session, resolved) do
    case resolved do
      {:member, user} ->
        with {:ok, _} <-
               Sessions.claim_place(session, fn ->
                 Sessions.signup_for(head, session, user.username)
               end),
             do: {:ok, gettext("Registered %{name}.", name: user.name || user.username)}

      {:user, user} ->
        with {:ok, _} <-
               Sessions.claim_place(session, fn -> Cab.Invitations.invite(head, session, user) end) do
          added =
            gettext("%{name} is in the session. They accept on their My page.",
              name: user.name || user.username
            )

          {:ok, added <> " " <> invitation_mail(user, session)}
        end

      {:guest, name} ->
        with {:ok, link} <-
               Sessions.claim_place(session, fn -> Links.register_guest(session, name) end),
             do:
               {:ok,
                gettext("%{name} added as a guest. Personal link: %{url}",
                  name: link.user.name,
                  url: url(~p"/l/#{link.code}")
                )}

      nil ->
        {:error,
         gettext("Type a member's name, a user's exact username or email, or a guest's name.")}
    end
  end

  # the invite stands whether or not the e-mail goes out
  defp invitation_mail(%{email: email}, _session) when email in [nil, ""], do: ""

  defp invitation_mail(user, session) do
    session = Cab.Repo.preload(session, :club)

    case CabWeb.Emails.invitation(user, session, session.club) do
      :ok -> gettext("We e-mailed them.")
      {:error, _reason} -> gettext("The e-mail could not be sent.")
    end
  end

  # POST .../owner/sessions/:session_uuid/signups/:participant_id/remove
  def remove_signup(conn, %{"session_uuid" => session_uuid, "participant_id" => participant_id}) do
    with_session(conn, session_uuid, fn session ->
      case Integer.parse(participant_id) do
        {participant_id, ""} ->
          case Sessions.remove_signup(conn.assigns.current_user, session, participant_id) do
            :ok -> {:ok, gettext("Registration removed.")}
            error -> error
          end

        _ ->
          {:error, gettext("That person isn't in this session.")}
      end
    end)
  end

  # POST .../owner/sessions/:session_uuid/rooms - the allocator form
  # at :closed; the head's explicit composition, never auto-paired
  def make_rooms(conn, %{"session_uuid" => session_uuid} = params) do
    with_session(conn, session_uuid, fn session ->
      case params["rooms"] do
        %{} = rooms ->
          case Sessions.make_rooms(conn.assigns.current_user, session, compose_spec(rooms)) do
            {:ok, count} -> {:ok, gettext("%{count} room(s) created.", count: count)}
            error -> error
          end

        _missing ->
          {:error, gettext("Drag people into the rooms first. Nobody is placed automatically.")}
      end
    end)
  end

  # the dnd page posts rooms[i][og|oo|cg|co][1|2] + rooms[i][judge]
  # (empty slots post ""); the API takes the canonical
  # {"adjudicator_participant_id", "teams"} shape directly. Rows left
  # entirely empty (an unused "+ room" row) are dropped.
  defp compose_spec(%{} = rooms) do
    rooms
    |> Enum.sort_by(fn {index, _room} ->
      case Integer.parse(index) do
        {i, ""} -> i
        _ -> 0
      end
    end)
    |> Enum.map(fn {_index, room} ->
      %{
        "adjudicator_participant_id" => presence(room["judge"]),
        "teams" =>
          for side <- ~w(og oo cg co) do
            team = room[side] || %{}

            ~w(1 2)
            |> Enum.map(&presence(team[&1]))
            |> Enum.reject(&is_nil/1)
          end
      }
    end)
    |> Enum.reject(&empty_room?/1)
  end

  defp compose_spec(other), do: other

  defp empty_room?(%{"adjudicator_participant_id" => nil, "teams" => teams}),
    do: Enum.all?(teams, &(&1 == []))

  defp empty_room?(_room), do: false

  defp presence(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp presence(value), do: value

  # POST .../owner/sessions/:session_uuid/rooms/delete - rebuild:
  # pending rooms go away so the head can recompose
  def delete_rooms(conn, %{"session_uuid" => session_uuid}) do
    with_session(conn, session_uuid, fn session ->
      case Sessions.delete_rooms(conn.assigns.current_user, session) do
        {:ok, count} ->
          {:ok, gettext("%{count} room(s) deleted. Allocate the rooms again.", count: count)}

        error ->
          error
      end
    end)
  end

  # GET .../owner/sessions/:session_uuid/delete - the confirm step
  # before deleting a session nobody signed up for (no sign-ups, rooms
  # or ballots); any other session goes back to its page with the reason
  def confirm_delete(conn, %{"session_uuid" => session_uuid}) do
    case Sessions.get_for_club(conn.assigns.club, session_uuid) do
      %Session{} = session ->
        back = ~p"/c/#{conn.assigns.club.uuid}/owner/s/#{session.uuid}"

        case Sessions.state(%{session | club: conn.assigns.club}) do
          {:ok, state} ->
            case Sessions.deletion_refusal(state) do
              nil ->
                render(conn, :delete_session,
                  current: session,
                  name: session.name || state.event["name"],
                  page_title: gettext("%{club} - Delete session", club: conn.assigns.club.name)
                )

              message ->
                flash_error(conn, back, message)
            end

          {:error, message} ->
            flash_error(conn, back, message)
        end

      nil ->
        conn |> CabWeb.ErrorHTML.respond(404)
    end
  end

  # POST .../owner/sessions/:session_uuid/cancel - deletes the session
  # (twin of DELETE /api/cab/v1/sessions/:uuid); refused with the
  # reason once anyone signed up, rooms exist or it finished
  def cancel_session(conn, %{"session_uuid" => session_uuid}) do
    case Sessions.get_for_club(conn.assigns.club, session_uuid) do
      %Session{} = session ->
        case Sessions.cancel(conn.assigns.current_user, session) do
          {:ok, _session} ->
            conn
            |> put_flash(:info, gettext("Session deleted."))
            |> redirect(to: ~p"/c/#{conn.assigns.club.uuid}/owner")

          {:error, :conflict, message} ->
            conn
            |> put_flash(:error, message)
            |> redirect(to: ~p"/c/#{conn.assigns.club.uuid}/owner/s/#{session.uuid}")

          {:error, message} ->
            conn
            |> put_flash(:error, error_message(message))
            |> redirect(to: ~p"/c/#{conn.assigns.club.uuid}/owner/s/#{session.uuid}")
        end

      nil ->
        conn |> CabWeb.ErrorHTML.respond(404)
    end
  end

  # GET .../owner/sessions/:session_uuid/responses - the guests'
  # answers to the club's registration form, one row per guest; twin of
  # GET /api/cab/v1/sessions/:uuid/responses. cab's own rows only.
  def responses(conn, %{"session_uuid" => session_uuid}) do
    case Sessions.get_for_club(conn.assigns.club, session_uuid) do
      %Session{} = session ->
        %{columns: columns, rows: rows} = Links.responses(session)

        render(conn, :responses,
          current: session,
          columns: columns,
          rows: rows,
          page_title:
            gettext("%{club} - Responses - %{session}",
              club: conn.assigns.club.name,
              session: session.name
            )
        )

      nil ->
        conn |> CabWeb.ErrorHTML.respond(404)
    end
  end

  # GET .../owner/sessions/:session_uuid/responses/csv - the same rows
  # as a spreadsheet file
  def responses_csv(conn, %{"session_uuid" => session_uuid}) do
    case Sessions.get_for_club(conn.assigns.club, session_uuid) do
      %Session{} = session ->
        filename = CabWeb.ResponsesCsv.filename(conn.assigns.club, session)

        conn
        |> put_resp_content_type("text/csv")
        |> put_resp_header("content-disposition", CabWeb.ResponsesCsv.disposition(filename))
        |> CabWeb.Caching.no_store()
        |> send_resp(200, CabWeb.ResponsesCsv.encode(Links.responses(session)))

      nil ->
        conn |> CabWeb.ErrorHTML.respond(404)
    end
  end

  # POST .../owner/sessions/:session_uuid/finish - results live on
  # the public session page
  def finish(conn, %{"session_uuid" => session_uuid}) do
    case Sessions.get_for_club(conn.assigns.club, session_uuid) do
      %Session{} = session ->
        case Sessions.finish(conn.assigns.current_user, session) do
          :ok ->
            conn
            |> put_flash(:info, gettext("Session finished."))
            |> redirect(to: ~p"/c/#{conn.assigns.club.uuid}/s/#{session.uuid}")

          {:error, :conflict, message} ->
            conn
            |> put_flash(:error, message)
            |> redirect(to: ~p"/c/#{conn.assigns.club.uuid}/owner/s/#{session.uuid}")

          {:error, message} ->
            conn
            |> put_flash(:error, error_message(message))
            |> redirect(to: ~p"/c/#{conn.assigns.club.uuid}/owner/s/#{session.uuid}")
        end

      nil ->
        conn |> CabWeb.ErrorHTML.respond(404)
    end
  end

  # ---------------------------------------------------------------

  defp with_join_request(conn, id, fun) do
    with {id, ""} <- Integer.parse(id),
         %Membership{} = membership <- Clubs.get_membership(id),
         true <- membership.club_id == conn.assigns.club.id do
      case fun.(membership) do
        {:ok, info} -> back_members(conn, info: info)
        {:error, message} -> back_members(conn, error: message)
      end
    else
      _ -> conn |> CabWeb.ErrorHTML.respond(404)
    end
  end

  defp with_session(conn, session_uuid, fun) do
    case Sessions.get_for_club(conn.assigns.club, session_uuid) do
      %Session{} = session ->
        back = ~p"/c/#{conn.assigns.club.uuid}/owner/s/#{session.uuid}"

        case fun.(session) do
          {:ok, info} -> conn |> put_flash(:info, info) |> redirect(to: back)
          {:error, :conflict, message} -> flash_error(conn, back, message)
          {:error, message} -> flash_error(conn, back, message)
        end

      nil ->
        conn |> CabWeb.ErrorHTML.respond(404)
    end
  end

  defp flash_error(conn, back, message) do
    conn
    |> put_flash(:error, error_message(message))
    |> redirect(to: back)
  end

  defp back_members(conn, info: info) do
    conn
    |> put_flash(:info, info)
    |> redirect(to: ~p"/c/#{conn.assigns.club.uuid}/owner/members")
  end

  defp back_members(conn, error: message) do
    conn
    |> put_flash(:error, error_message(message))
    |> redirect(to: ~p"/c/#{conn.assigns.club.uuid}/owner/members")
  end

  defp error_message(message) when is_binary(message), do: message
  defp error_message(%{rooms: message}), do: message
  defp error_message(%{name: message}), do: message
  defp error_message(other), do: inspect(other)

  # the form picks one of each; the club keeps them as lists
  defp one_choice(attrs, keys) do
    Enum.reduce(keys, attrs, fn key, acc ->
      case acc[key] do
        value when is_binary(value) and value != "" -> Map.put(acc, key, [value])
        value when is_list(value) -> acc
        _ -> Map.put(acc, key, [])
      end
    end)
  end
end
