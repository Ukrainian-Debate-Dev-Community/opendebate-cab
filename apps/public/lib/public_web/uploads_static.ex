defmodule PublicWeb.UploadsStatic do
  @moduledoc """
  Serves Public.Uploads at /uploads. The folder is known only at boot
  (PUBLIC_UPLOADS_DIR), so Plug.Static is set up per request instead of
  when the endpoint compiles. The names are random and a file never
  changes, so browsers may keep it for a year.
  """
  @behaviour Plug

  def init(opts), do: opts

  def call(%Plug.Conn{path_info: ["uploads" | _]} = conn, _opts) do
    opts =
      Plug.Static.init(
        at: "/uploads",
        from: Public.Uploads.dir(),
        gzip: false,
        cache_control_for_etags: "public, max-age=31536000, immutable",
        headers: %{"x-content-type-options" => "nosniff"}
      )

    Plug.Static.call(conn, opts)
  end

  def call(conn, _opts), do: conn
end
