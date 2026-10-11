defmodule CabWeb.DevSessionController do
  @moduledoc """
  DEV ONLY user switcher. The route is registered exclusively inside
  the `:dev_routes` compile-time guard in the router, so this is
  unreachable in prod builds. Signs the session in as the named
  gateway user, creating them (and their engine counterpart) if
  needed - bypasses OAuth for local testing.
  """

  use CabWeb, :controller

  alias Cab.Accounts
  alias Cab.Accounts.User
  alias Cab.Repo

  def switch(conn, %{"username" => username} = params) do
    username = String.trim(username)

    if username == "" do
      conn |> put_flash(:error, "username required") |> redirect(to: return_to(params))
    else
      user =
        Repo.get_by(User, username: username) ||
          Repo.insert!(User.changeset(%User{}, %{username: username}))

      user = Accounts.ensure_node_user(user)

      conn
      |> configure_session(renew: true)
      |> put_session(:user_id, user.id)
      |> redirect(to: return_to(params))
    end
  end

  defp return_to(%{"return_to" => "/" <> _ = path}), do: path
  defp return_to(_params), do: "/"
end
