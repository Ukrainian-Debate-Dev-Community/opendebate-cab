defmodule PublicWeb.ManageAccess do
  @moduledoc """
  Lets into /manage only content managers and cab admins. It reads
  cab's session cookie (never writes it) through CabWeb.Session, loads
  the cab account and asks Public.Roles. Someone not signed in to cab
  at all is sent to cab's sign-in, which brings them back here (cab's
  RETURN_HOSTS lists this site); anyone signed in without the role -
  a guest's personal link included - gets the same 404 as for a page
  that does not exist, so the public never sees /manage exists.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_cookies(conn)
    user_id = CabWeb.Session.user_id(conn.req_cookies[CabWeb.Session.cookie_key()])
    user = user_id && Cab.Accounts.get_viewer(user_id)

    case user && !user.guest && Public.Roles.access(user) do
      access when access in [:admin, :content_manager] ->
        conn |> assign(:manager, user) |> assign(:access, access)

      _ when is_nil(user) and conn.method in ["GET", "HEAD"] ->
        conn |> Phoenix.Controller.redirect(external: signin_url(conn)) |> halt()

      _ ->
        raise PublicWeb.NotFound
    end
  end

  # cab's sign-in, returning to the very page asked for
  defp signin_url(conn) do
    back = PublicWeb.Endpoint.url() <> conn.request_path <> query(conn.query_string)
    Application.fetch_env!(:public, :cab_url) <> "/signin?" <> URI.encode_query(return_to: back)
  end

  defp query(""), do: ""
  defp query(qs), do: "?" <> qs
end
