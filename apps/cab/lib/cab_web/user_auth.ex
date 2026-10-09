defmodule CabWeb.UserAuth do
  import Plug.Conn
  import Phoenix.Controller

  alias Cab.Accounts

  def fetch_current_user(conn, _opts) do
    user_id = get_session(conn, :user_id)
    assign(conn, :current_user, user_id && Accounts.get_viewer(user_id))
  end

  # pages that belong to an account: a personal-link guest signs in first
  def require_account(conn, _opts) do
    case conn.assigns[:current_user] do
      %{guest: false} ->
        conn

      %{guest: true} ->
        conn
        |> put_flash(:error, "Sign in with your own account first.")
        |> redirect(to: "/signin")
        |> halt()

      nil ->
        require_authenticated_user(conn, [])
    end
  end

  # Every auth wall lands on P1 /signin — never straight to a provider.
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "Please sign in.")
      |> redirect(to: "/signin")
      |> halt()
    end
  end
end
