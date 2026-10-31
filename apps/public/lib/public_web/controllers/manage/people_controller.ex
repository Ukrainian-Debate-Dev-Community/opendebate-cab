defmodule PublicWeb.Manage.PeopleController do
  use PublicWeb, :controller

  alias Public.Roles

  # cab admins only; for a content manager the page does not exist
  plug :admins_only
  plug :put_view, PublicWeb.Manage.HTML

  def index(conn, _params) do
    render(conn, :people, manage_active: :people, page_title: gettext("People"), roles: rows())
  end

  def grant(conn, %{"login" => login}) do
    case Cab.Accounts.get_user_by_login(login) do
      nil ->
        conn
        |> put_flash(
          :error,
          gettext("No cab account has that username or e-mail. They sign in to cab once first.")
        )
        |> redirect(to: ~p"/manage/people")

      user ->
        {:ok, _} = Roles.grant(user.id, conn.assigns.manager.id)

        conn
        |> put_flash(
          :info,
          gettext("%{name} can now manage the site. Send them the link %{link}.",
            name: user.name || user.username,
            link: PublicWeb.Endpoint.url() <> ~p"/manage"
          )
        )
        |> redirect(to: ~p"/manage/people")
    end
  end

  def revoke(conn, %{"user_id" => user_id}) do
    Roles.revoke(String.to_integer(user_id))

    conn
    |> put_flash(:info, gettext("The role is revoked; it takes effect on their next request."))
    |> redirect(to: ~p"/manage/people")
  end

  defp admins_only(conn, _opts) do
    if conn.assigns.access == :admin, do: conn, else: raise(PublicWeb.NotFound)
  end

  defp rows do
    roles = Roles.list()
    ids = Enum.flat_map(roles, &[&1.user_id, &1.granted_by_user_id]) |> Enum.reject(&is_nil/1)
    users = Map.new(ids, &{&1, Cab.Accounts.get_user(&1)})

    Enum.map(roles, fn role ->
      %{role: role, user: users[role.user_id], granted_by: users[role.granted_by_user_id]}
    end)
  end
end
