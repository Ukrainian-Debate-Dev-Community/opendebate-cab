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

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    case Accounts.upsert_from_oauth(auth) do
      {:ok, user} ->
        # Best-effort engine provisioning; sign-in must not depend on it.
        user = Accounts.ensure_node_user(user)

        conn
        |> configure_session(renew: true)
        |> put_session(:user_id, user.id)
        |> put_flash(:info, "Signed in as #{user.username}.")
        |> redirect(to: ~p"/")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Sign-in failed.")
        |> redirect(to: ~p"/signin")
    end
  end

  def callback(%{assigns: %{ueberauth_failure: _failure}} = conn, _params) do
    conn
    |> put_flash(:error, "Authentication failed.")
    |> redirect(to: ~p"/signin")
  end

  def logout(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> redirect(to: ~p"/")
  end
end
