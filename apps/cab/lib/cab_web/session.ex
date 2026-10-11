defmodule CabWeb.Session do
  @moduledoc """
  cab's session cookie in one place: its key, salt and (per deployment)
  domain, and a read-only check of a cookie value for services that
  share the sign-in. The domain is a deploy setting
  (`config :cab, :session_cookie_domain`), nil by default so the cookie
  stays on cab's own host.
  """

  @key "_cab_key"
  @signing_salt "icTlw4bX"

  def cookie_key, do: @key

  @doc "The Plug.Session options, read at request time."
  def options do
    base = [store: :cookie, key: @key, signing_salt: @signing_salt, same_site: "Lax"]

    case Application.get_env(:cab, :session_cookie_domain) do
      nil -> base
      domain -> Keyword.put(base, :domain, domain)
    end
  end

  @doc """
  The signed-in user's id in a cab session cookie value, or nil when
  the value is missing, tampered with or signed out. It only reads.
  """
  def user_id(nil), do: nil

  def user_id(cookie) when is_binary(cookie) do
    conn = %Plug.Conn{secret_key_base: CabWeb.Endpoint.config(:secret_key_base)}
    opts = Plug.Session.COOKIE.init(signing_salt: @signing_salt)

    case Plug.Session.COOKIE.get(conn, cookie, opts) do
      {_term, %{"user_id" => id}} -> id
      _ -> nil
    end
  end
end
