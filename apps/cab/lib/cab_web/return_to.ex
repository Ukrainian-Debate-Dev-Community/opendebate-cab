defmodule CabWeb.ReturnTo do
  @moduledoc """
  Where to send someone back after signing in: a local path ("/c/..."),
  or a full address on one of the deployment's sibling sites
  (`config :cab, :return_hosts`, RETURN_HOSTS in production) - e.g. a
  site that sends its editors here to sign in. Anything else is
  ignored, so the sign-in never redirects to an unknown site.
  """

  import Phoenix.Controller, only: [redirect: 2]

  @doc "The value when it may be returned to, else nil."
  def accept("/" <> rest = path) do
    if String.starts_with?(rest, ["/", "\\"]), do: nil, else: path
  end

  # Browsers read a backslash as a slash and drop a user@ part, so
  # "https://evil.example\@sibling.example" goes to evil.example while
  # URI.parse/1 sees the sibling's host: such addresses are refused, and
  # the one returned is rebuilt from the parsed parts.
  def accept(url) when is_binary(url) do
    with false <- String.contains?(url, "\\") or url =~ ~r/[[:space:][:cntrl:]]/u,
         %URI{scheme: scheme, userinfo: nil, host: host} = uri
         when scheme in ["https", "http"] and is_binary(host) <- URI.parse(url),
         true <- String.downcase(host) in hosts() do
      URI.to_string(%URI{
        scheme: scheme,
        host: host,
        port: uri.port,
        path: uri.path,
        query: uri.query
      })
    else
      _refused -> nil
    end
  end

  def accept(_value), do: nil

  @doc "Redirects to an accepted value: a local path, or a sibling site."
  def redirect_to(conn, "/" <> _ = path), do: redirect(conn, to: path)
  def redirect_to(conn, url), do: redirect(conn, external: url)

  defp hosts do
    :cab
    |> Application.get_env(:return_hosts, [])
    |> Enum.map(&String.downcase/1)
  end
end
