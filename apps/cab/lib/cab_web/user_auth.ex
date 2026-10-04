defmodule CabWeb.UserAuth do
  import Plug.Conn
  import Phoenix.Controller

  alias Cab.Accounts

  def fetch_current_user(conn, _opts) do
    user_id = get_session(conn, :user_id)
    assign(conn, :current_user, user_id && Accounts.get_user(user_id))
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
