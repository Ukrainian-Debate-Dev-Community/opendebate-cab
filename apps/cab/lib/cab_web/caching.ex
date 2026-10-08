defmodule CabWeb.Caching do
  @moduledoc """
  The cache rule in one place: finished sessions are immutable — their
  pages cache hard; anything live is never stored. Role-scoped pages
  (owner, admin, cabinet) stay on the browser default (no header).
  """
  import Plug.Conn

  @doc "Public page over finished (immutable) data."
  def finished(conn), do: put_resp_header(conn, "cache-control", "public, max-age=3600")

  @doc "Live page — state changes under the viewer's feet."
  def live(conn), do: put_resp_header(conn, "cache-control", "no-store")

  @doc "Finished when the session's stage is done, live otherwise."
  def by_stage(conn, :done), do: finished(conn)
  def by_stage(conn, _stage), do: live(conn)
end
