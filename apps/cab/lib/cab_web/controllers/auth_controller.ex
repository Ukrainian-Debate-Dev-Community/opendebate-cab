defmodule CabWeb.AuthController do
  use CabWeb, :controller

  plug Ueberauth

  alias Cab.Accounts

  # Ueberauth's request phase redirects to the provider; reaching the
  # action means the provider is unknown.
  def request(conn, _params) do
    conn
    |> put_flash(:error, "Unknown login provider.")
    |> redirect(to: ~p"/signin")
  end

  # linking a sign-in method from /account: the browser comes back
  # here signed in, with the link intent kept in the session
  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, params) do
    user_id = get_session(conn, :user_id)

    if user_id && get_session(conn, :link_to) == user_id do
      link(conn |> delete_session(:link_to), Accounts.get_user(user_id), auth)
    else
      sign_in(conn, auth, params)
    end
  end

  def callback(%{assigns: %{ueberauth_failure: _failure}} = conn, _params) do
    conn
    |> delete_session(:link_to)
    |> put_flash(:error, "Authentication failed.")
    |> redirect(to: ~p"/signin")
  end

  defp link(conn, user, auth) do
    provider = provider_name(auth.provider)

    case Accounts.link_identity(user, auth) do
      {:ok, :linked} ->
        conn
        |> put_flash(:info, "#{provider} is now linked to this account.")
        |> redirect(to: ~p"/account")

      {:ok, :already} ->
        conn |> put_flash(:info, "#{provider} was already linked.") |> redirect(to: ~p"/account")

      {:other_account, other} ->
        # proven: they just signed in to that account's provider
        conn |> put_session(:merge_candidate, other.id) |> redirect(to: ~p"/account/merge")

      {:error, message} ->
        conn |> put_flash(:error, message) |> redirect(to: ~p"/account")
    end
  end

  defp provider_name(provider) do
    case to_string(provider) do
      "github" -> "GitHub"
      "google" -> "Google"
      other -> other
    end
  end

  defp sign_in(conn, auth, _params) do
    case Accounts.upsert_from_oauth(auth) do
      {:ok, user} ->
        conn |> link_pending(user) |> signed_in(user)

      # the provider vouches for an address an account already has:
      # the person picks that account or a separate one on /signin
      {:existing, user, pending} ->
        conn
        |> put_session(:pending_identity, %{pending: pending, user_id: user.id})
        |> redirect(to: ~p"/signin")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Sign-in failed.")
        |> redirect(to: ~p"/signin")
    end
  end

  # signing in to the account /signin pointed at adds the sign-in that
  # led there; any other sign-in just drops it
  defp link_pending(conn, user) do
    pending = get_session(conn, :pending_identity)
    conn = delete_session(conn, :pending_identity)

    with %{pending: pending, user_id: user_id} when user_id == user.id <- pending,
         {:ok, :linked} <- Accounts.link_identity(user, pending) do
      put_flash(conn, :info, "#{provider_name(pending.provider)} is now linked to this account.")
    else
      _ -> conn
    end
  end

  @doc false
  def signed_in(conn, user) do
    # Best-effort engine provisioning; sign-in must not depend on it.
    user = Accounts.ensure_node_user(user)
    linked = Phoenix.Flash.get(conn.assigns.flash, :info)

    conn
    |> configure_session(renew: true)
    |> put_session(:user_id, user.id)
    |> put_flash(:info, linked || "Signed in as #{user.username}.")
    |> redirect(to: ~p"/")
  end

  def logout(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> redirect(to: ~p"/")
  end
end
