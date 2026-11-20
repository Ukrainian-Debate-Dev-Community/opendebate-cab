defmodule PublicWeb.TenantThemeTest do
  @moduledoc "The tenant's theme on the public site's pages and its static files at /tenant (Ui.TenantStatic)."
  use PublicWeb.ConnCase, async: false

  setup do
    tenant = Path.join(System.tmp_dir!(), "tenant-theme-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(tenant, "static"))
    previous = Application.get_env(:ui, :tenant_dir)
    Application.put_env(:ui, :tenant_dir, tenant)

    on_exit(fn ->
      Application.put_env(:ui, :tenant_dir, previous)
      File.rm_rf!(tenant)
    end)

    %{tenant: tenant}
  end

  test "a theme.css is linked after the app's stylesheet and served", %{
    conn: conn,
    tenant: tenant
  } do
    refute conn |> get(~p"/") |> html_response(200) =~ "/tenant/theme.css"

    File.write!(Path.join(tenant, "static/theme.css"), ":root { --brand: #0a5; }")
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~
             ~r{href="/assets/css/app\.css[^"]*">\s*<link[^>]* rel="stylesheet" href="/tenant/theme\.css\?v=\d+"}s

    assert conn |> get("/tenant/theme.css") |> response(200) =~ "--brand"
  end
end
