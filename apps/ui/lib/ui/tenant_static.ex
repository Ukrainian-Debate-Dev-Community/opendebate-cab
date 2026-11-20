defmodule Ui.TenantStatic do
  @moduledoc """
  The tenant's own static files - its `static/` folder in the tenant
  folder (`config :ui, :tenant_dir`, TENANT_DIR) - served at /tenant by
  every app that plugs this in. A `static/theme.css` there is the
  tenant's theme: token overrides (and @font-face rules for files beside
  it) that `Ui.Components.tenant_theme/1` loads after the app's own CSS.
  The folder is known only at boot, so Plug.Static is set up per request.
  """
  @behaviour Plug

  def init(opts), do: opts

  def call(%Plug.Conn{path_info: ["tenant" | _]} = conn, _opts) do
    case dir() do
      nil ->
        conn

      dir ->
        opts =
          Plug.Static.init(
            at: "/tenant",
            from: dir,
            gzip: false,
            headers: %{"x-content-type-options" => "nosniff"}
          )

        Plug.Static.call(conn, opts)
    end
  end

  def call(conn, _opts), do: conn

  @doc "The tenant theme's address, its change time as the version; nil without one."
  def theme_href do
    with dir when is_binary(dir) <- dir(),
         {:ok, %File.Stat{mtime: mtime}} <- File.stat(Path.join(dir, "theme.css"), time: :posix) do
      "/tenant/theme.css?v=#{mtime}"
    else
      _ -> nil
    end
  end

  defp dir do
    case Application.get_env(:ui, :tenant_dir) do
      nil -> nil
      tenant -> Path.join(tenant, "static")
    end
  end
end
