defmodule CabWeb.AdminController do
  @moduledoc """
  `/admin` - the platform admin console (is_admin only; everyone
  else gets a plain 404, the page does not exist for them). Club
  creation is ADMIN-ONLY: this form replaces the admin's need for
  `mix cab.seed_club` (the task stays for scripting). Change head
  and archive live here too; archiving sets the gateway
  `archived_at` flag only - the engine stays untouched.

  Admin is HTML-only by design: no API twins.
  """

  use CabWeb, :controller

  alias Cab.{Accounts, Clubs, HeadInvitations}
  alias Cab.Clubs.{Club, HeadInvitation}
  alias CabWeb.Emails

  plug :require_admin

  def show(conn, _params) do
    render_admin(conn)
  end

  # POST /admin/clubs {"name", "city", "head", "head_name"} - "head" is
  # an account's exact username or e-mail, or an e-mail no account uses:
  # then the admin heads the new club until the invitee accepts
  def create_club(conn, params) do
    admin = conn.assigns.current_user

    case resolve_head(params) do
      {:user, head} ->
        case Clubs.create_club(params["name"] || "", params["city"], head) do
          {:ok, club} ->
            conn
            |> put_flash(
              :info,
              gettext("Club %{club} created, headed by %{head}.",
                club: club.name,
                head: head.username
              )
            )
            |> redirect(to: ~p"/admin")

          {:error, %Ecto.Changeset{} = changeset} ->
            bounce(conn, CabWeb.ClubProfile.save_error(changeset))

          {:error, message} ->
            bounce(conn, message)
        end

      {:invite, email, name} ->
        with {:ok, club} <- Clubs.create_club(params["name"] || "", params["city"], admin),
             {:ok, invitation, token} <- HeadInvitations.invite(club, email, name, admin, admin) do
          conn |> invited(invitation, token, :created) |> redirect(to: ~p"/admin")
        else
          {:error, %Ecto.Changeset{} = changeset} ->
            bounce(conn, CabWeb.ClubProfile.save_error(changeset))

          {:error, message} ->
            bounce(conn, message)
        end

      {:error, message} ->
        bounce(conn, message)
    end
  end

  # POST /admin/head {"uuid", "head", "head_name"} - the club rides in
  # the body; an invitation leaves the current head in place until it
  # is accepted
  def change_head(conn, %{"uuid" => uuid} = params) do
    with %Club{} = club <- Clubs.get_by_uuid(uuid) do
      case resolve_head(params) do
        {:user, head} ->
          case Clubs.change_head(club, head) do
            {:ok, _club} ->
              conn
              |> put_flash(
                :info,
                gettext("%{club} is now headed by %{head}.",
                  club: club.name,
                  head: head.username
                )
              )
              |> redirect(to: ~p"/admin")

            {:error, message} ->
              bounce(conn, message)
          end

        {:invite, email, name} ->
          case HeadInvitations.invite(club, email, name, conn.assigns.current_user) do
            {:ok, invitation, token} ->
              conn |> invited(invitation, token, :changed) |> redirect(to: ~p"/admin")

            {:error, message} ->
              bounce(conn, message)
          end

        {:error, message} ->
          bounce(conn, message)
      end
    else
      nil -> conn |> CabWeb.ErrorHTML.respond(404)
    end
  end

  # POST /admin/head-invitations/:id/resend - a new link, e-mailed again
  def resend_head_invitation(conn, %{"id" => id}) do
    with %HeadInvitation{} = invitation <- HeadInvitations.get(id),
         {:ok, invitation, token} <- HeadInvitations.resend(invitation) do
      conn |> invited(invitation, token, :resent) |> redirect(to: ~p"/admin")
    else
      nil -> conn |> CabWeb.ErrorHTML.respond(404)
      {:error, message} -> bounce(conn, message)
    end
  end

  # POST /admin/head-invitations/:id/cancel
  def cancel_head_invitation(conn, %{"id" => id}) do
    with %HeadInvitation{} = invitation <- HeadInvitations.get(id),
         {:ok, _} <- HeadInvitations.cancel(invitation) do
      conn
      |> put_flash(
        :info,
        gettext("The invitation to head %{club} is cancelled.", club: invitation.club.name)
      )
      |> redirect(to: ~p"/admin")
    else
      nil -> conn |> CabWeb.ErrorHTML.respond(404)
      {:error, _} -> bounce(conn, gettext("Could not cancel the invitation. Try again."))
    end
  end

  # POST /admin/merge {"first", "second"} (username or e-mail) - one person's two
  # accounts, for when they cannot sign in to both themselves
  def merge(conn, params) do
    with {:ok, first} <- typed_account(params["first"]),
         {:ok, second} <- typed_account(params["second"]),
         {:ok, kept} <- Accounts.merge_accounts(first, second) do
      conn
      |> put_flash(
        :info,
        gettext("The accounts are merged into %{username}.", username: kept.username)
      )
      |> redirect(to: ~p"/admin")
    else
      {:error, message} when is_binary(message) -> bounce(conn, message)
      {:error, _} -> bounce(conn, gettext("The merge did not go through. Nothing changed."))
    end
  end

  # POST /admin/clubs/:uuid/archive - the club disappears from every
  # public surface; history stays in the engine
  def archive(conn, %{"uuid" => uuid}) do
    with %Club{} = club <- Clubs.get_by_uuid(uuid),
         {:ok, _club} <- Clubs.archive_club(club) do
      conn
      |> put_flash(
        :info,
        gettext("%{club} is archived and hidden from public pages.", club: club.name)
      )
      |> redirect(to: ~p"/admin")
    else
      nil -> conn |> CabWeb.ErrorHTML.respond(404)
      {:error, _} -> bounce(conn, gettext("Could not archive the club. Try again."))
    end
  end

  defp render_admin(conn) do
    clubs = Clubs.list_all_clubs()

    render(conn, :show,
      clubs: clubs,
      heads: Map.new(clubs, &{&1.id, Clubs.head_of(&1)}),
      member_counts: Clubs.member_counts(Enum.map(clubs, & &1.id)),
      accounts: Accounts.list_accounts(),
      head_invitations: HeadInvitations.list_pending(),
      page_title: gettext("Admin")
    )
  end

  # an account by exact username or e-mail; else an address to invite
  defp resolve_head(params) do
    login = Core.Text.trim(params["head"])

    case Accounts.get_user_by_login(login) do
      %Accounts.User{} = user ->
        {:user, user}

      nil ->
        cond do
          login == "" ->
            {:error, gettext("Type the head's username or e-mail.")}

          HeadInvitations.email?(login) ->
            with {:ok, email, name} <- HeadInvitations.check_invitee(login, params["head_name"]),
                 do: {:invite, email, name}

          true ->
            {:error,
             gettext(
               "No account has that username or e-mail. Type an e-mail address to invite someone new."
             )}
        end
    end
  end

  # the invitation e-mail; when it cannot go out the admin gets the
  # link to pass on themselves
  defp invited(conn, invitation, token, kind) do
    club = invitation.club.name
    name = invitation.name

    case Emails.head_invitation(invitation, token, conn.assigns.current_user) do
      :ok ->
        put_flash(conn, :info, invited_words(kind, club, name))

      {:error, _} ->
        put_flash(
          conn,
          :error,
          gettext("%{done} The e-mail could not be sent: send %{name} this link yourself: %{url}",
            done: unsent_words(kind, club),
            name: name,
            url: Emails.head_invitation_url(token)
          )
        )
    end
  end

  defp invited_words(:created, club, name),
    do:
      gettext(
        "Club %{club} created. %{name} is invited by e-mail to be its head; you head it until they accept.",
        club: club,
        name: name
      )

  defp invited_words(:changed, club, name),
    do:
      gettext(
        "%{name} is invited by e-mail to head %{club}; the current head stays until they accept.",
        club: club,
        name: name
      )

  defp invited_words(:resent, _club, name),
    do: gettext("A new link was e-mailed to %{name}.", name: name)

  defp unsent_words(:created, club), do: gettext("Club %{club} created.", club: club)

  defp unsent_words(:changed, club),
    do: gettext("The invitation to head %{club} is saved.", club: club)

  defp unsent_words(:resent, _club), do: gettext("A new link is ready.")

  # an account by its exact username or e-mail, as typed on the form
  defp typed_account(login) do
    login = Core.Text.trim(login)

    case login != "" && Accounts.get_user_by_login(login) do
      %Accounts.User{} = user -> {:ok, user}
      _ -> {:error, gettext("No account has the username or e-mail \"%{login}\".", login: login)}
    end
  end

  defp bounce(conn, message) do
    conn
    |> put_flash(:error, message)
    |> redirect(to: ~p"/admin")
  end

  # the page does not exist for non-admins - a plain 404, never 403
  defp require_admin(conn, _opts) do
    case conn.assigns.current_user do
      %{is_admin: true} -> conn
      _ -> conn |> CabWeb.ErrorHTML.respond(404)
    end
  end
end
