defmodule CabWeb.ApiDocsController do
  @moduledoc """
  The API reference: Scalar, served from cab itself. GET /api/cab/docs shows
  cab's own API (priv/api/cab.json), GET /api/engine/docs the engine's
  (priv/api/engine.yml, a copy of the pinned engine's docs/openapi.yml).
  No session: the page and the files are the same for everyone.
  """
  use CabWeb, :controller

  # GET /api/cab/docs
  def show(conn, _params), do: page(conn, :cab, gettext("cab API"))

  # GET /api/docs - the old address
  def to_cab_docs(conn, _params), do: redirect(conn, to: ~p"/api/cab/docs")

  # GET /api/engine/docs
  def show_engine(conn, _params), do: page(conn, :engine, gettext("Engine API"))

  defp page(conn, doc, title) do
    conn = fetch_cookies(conn)
    # the language cab's footer chose, read from its cookie (no session here)
    if conn.cookies["cab_locale"] in ~w(en uk),
      do: Gettext.put_locale(CabWeb.Gettext, conn.cookies["cab_locale"])

    conn
    |> put_root_layout(false)
    |> put_layout(false)
    |> render(:show, doc: doc, page_title: title)
  end

  # GET /api/cab/docs/openapi.json
  def cab_spec(conn, _params), do: send_spec(conn, "cab.json", "application/json")

  # GET /api/engine/docs/openapi.yml
  def engine_spec(conn, _params), do: send_spec(conn, "engine.yml", "application/yaml")

  defp send_spec(conn, file, type) do
    conn
    |> put_resp_content_type(type)
    |> send_file(200, Path.join([:code.priv_dir(:cab), "api", file]))
  end
end
