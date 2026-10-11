defmodule CabWeb.Caching do
  @moduledoc """
  HTML pages carry the viewer's identity in the sidenav shell, so they
  are NEVER HTTP-cached - a shared or stale copy would show someone
  else's account (a browser once served a guest's cached standings page
  to a signed-in head). Immutability of finished sessions is exploited
  server-side instead (`Cab.Standings.Cache`); hard public HTTP caching
  is reserved for the keyed public API (pillar 3), which carries no
  identity.
  """
  import Plug.Conn

  @doc "Every HTML page: never stored by browsers or proxies."
  def no_store(conn), do: put_resp_header(conn, "cache-control", "no-store")
end
