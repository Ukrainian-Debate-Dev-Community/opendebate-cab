defmodule CabWeb.AccountController do
  @moduledoc """
  `/account` — the signed-in profile page, opened from the sidenav
  bottom only: display name (editable), provider/avatar info, sign
  out, and claiming a guest history by pasting its personal link.
  """

  use CabWeb, :controller

  import CabWeb.UserAuth, only: [require_account: 2]

  alias Cab.{Accounts, Links}

  plug :require_account

  def show(conn, _params) do
    render_account(conn)
  end

  # POST /account {"name"} — display name only
  def update(conn, params) do
    case Accounts.update_profile(conn.assigns.current_user, params) do
      {:ok, user} ->
        conn
        |> assign(:current_user, user)
        |> put_flash(:info, "Profile saved.")
        |> redirect(to: ~p"/account")

      {:error, %Ecto.Changeset{}} ->
        conn
        |> put_flash(:error, "Could not save the profile.")
        |> render_account()
    end
  end

  @providers ~w(github google)

  # GET /account/link/:provider — remember the intent, then the
  # provider's own sign-in; the callback links instead of signing in
  def link(conn, %{"provider" => provider}) when provider in @providers do
    conn
    |> put_session(:link_to, conn.assigns.current_user.id)
    |> redirect(to: "/auth/#{provider}")
  end

  def link(conn, _params), do: CabWeb.ErrorHTML.respond(conn, 404)

  # POST /account/unlink/:provider
  def unlink(conn, %{"provider" => provider}) do
    case Accounts.unlink_identity(conn.assigns.current_user, provider) do
      {:ok, _} ->
        conn |> put_flash(:info, "Sign-in method removed.") |> redirect(to: ~p"/account")

      {:error, message} ->
        conn |> put_flash(:error, message) |> redirect(to: ~p"/account")
    end
  end

  # GET /account/merge — the sign-in just linked has its own account
  def merge_form(conn, _params) do
    case merge_candidate(conn) do
      nil ->
        redirect(conn, to: ~p"/account")

      other ->
        render(conn, :merge,
          other: other,
          kept: Accounts.kept_in_merge(conn.assigns.current_user, other),
          clubs: Cab.Clubs.list_user_memberships(other),
          page_title: "Merge accounts"
        )
    end
  end

  # POST /account/merge {"decision": "merge" | "keep"}
  def merge(conn, params) do
    other = merge_candidate(conn)
    conn = delete_session(conn, :merge_candidate)

    case {other, params["decision"]} do
      {nil, _} ->
        redirect(conn, to: ~p"/account")

      {_other, "keep"} ->
        conn |> put_flash(:info, "The accounts stay separate.") |> redirect(to: ~p"/account")

      {other, "merge"} ->
        case Accounts.merge_accounts(conn.assigns.current_user, other) do
          {:ok, kept} ->
            conn
            |> configure_session(renew: true)
            |> put_session(:user_id, kept.id)
            |> put_flash(:info, "The accounts are merged into #{kept.username}.")
            |> redirect(to: ~p"/account")

          {:error, message} when is_binary(message) ->
            conn |> put_flash(:error, message) |> redirect(to: ~p"/account")

          {:error, _} ->
            conn
            |> put_flash(:error, "The merge did not go through. Nothing changed.")
            |> redirect(to: ~p"/account")
        end
    end
  end

  defp merge_candidate(conn) do
    with id when is_integer(id) <- get_session(conn, :merge_candidate),
         %Cab.Accounts.User{} = other <- Accounts.get_user(id),
         true <- other.id != conn.assigns.current_user.id do
      other
    else
      _ -> nil
    end
  end

  # POST /account/claim {"link"} — the pasted personal link's guest
  # history moves onto this account
  def claim(conn, params) do
    case Links.find_by_pasted(params["link"]) do
      nil ->
        conn
        |> put_flash(:error, "That personal link does not exist or no longer works.")
        |> redirect(to: ~p"/account")

      link ->
        case Links.claim(link, conn.assigns.current_user) do
          {:ok, _moved} ->
            conn
            |> put_flash(:info, "#{link.user.name}'s guest history is now on your account.")
            |> redirect(to: ~p"/me")

          {:error, message} ->
            conn |> put_flash(:error, message) |> redirect(to: ~p"/account")
        end
    end
  end

  defp render_account(conn) do
    user = conn.assigns.current_user

    render(conn, :show,
      identities: Accounts.list_identities(user),
      page_title: "Account"
    )
  end
end
