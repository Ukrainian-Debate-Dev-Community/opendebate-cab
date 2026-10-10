defmodule CabWeb.AdminController do
  @moduledoc """
  `/admin` — the platform admin console (is_admin only; everyone
  else gets a plain 404, the page does not exist for them). Club
  creation is ADMIN-ONLY: this form replaces the admin's need for
  `mix cab.seed_club` (the task stays for scripting). Change head
  and archive live here too; archiving sets the gateway
  `archived_at` flag only — the engine stays untouched.

  Admin is HTML-only by design: no API twins.
  """

  use CabWeb, :controller

  alias Cab.{Accounts, Clubs}
  alias Cab.Clubs.Club

  plug :require_admin

  def show(conn, _params) do
    render_admin(conn)
  end

  # POST /admin/clubs {"name", "city", "head_id"}
  def create_club(conn, params) do
    with {:ok, head} <- picked_user(params["head_id"]),
         {:ok, club} <- Clubs.create_club(params["name"] || "", params["city"], head) do
      conn
      |> put_flash(
        :info,
        gettext("Club %{club} created, headed by %{head}.", club: club.name, head: head.username)
      )
      |> redirect(to: ~p"/admin")
    else
      {:error, %Ecto.Changeset{}} -> bounce(conn, gettext("The club needs a name."))
      {:error, message} -> bounce(conn, message)
    end
  end

  # POST /admin/head {"uuid", "head_id"} — the club rides in the body
  # (one dropdown form serves every club)
  def change_head(conn, %{"uuid" => uuid} = params) do
    with %Club{} = club <- Clubs.get_by_uuid(uuid),
         {:ok, head} <- picked_user(params["head_id"]),
         {:ok, _club} <- Clubs.change_head(club, head) do
      conn
      |> put_flash(
        :info,
        gettext("%{club} is now headed by %{head}.", club: club.name, head: head.username)
      )
      |> redirect(to: ~p"/admin")
    else
      nil -> conn |> CabWeb.ErrorHTML.respond(404)
      {:error, message} -> bounce(conn, message)
    end
  end

  # POST /admin/merge {"first_id", "second_id"} — one person's two
  # accounts, for when they cannot sign in to both themselves
  def merge(conn, params) do
    with {:ok, first} <- picked_user(params["first_id"]),
         {:ok, second} <- picked_user(params["second_id"]),
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

  # POST /admin/clubs/:uuid/archive — the club disappears from every
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
      users: Accounts.list_users(),
      page_title: gettext("Admin")
    )
  end

  defp picked_user(id) do
    with id when is_binary(id) <- id,
         {id, ""} <- Integer.parse(id),
         %Accounts.User{} = user <- Accounts.get_user(id) do
      {:ok, user}
    else
      _ -> {:error, gettext("Pick an account.")}
    end
  end

  defp bounce(conn, message) do
    conn
    |> put_flash(:error, message)
    |> redirect(to: ~p"/admin")
  end

  # the page does not exist for non-admins — a plain 404, never 403
  defp require_admin(conn, _opts) do
    case conn.assigns.current_user do
      %{is_admin: true} -> conn
      _ -> conn |> CabWeb.ErrorHTML.respond(404)
    end
  end
end
