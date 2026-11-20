defmodule Ui.TenantStaticTest do
  @moduledoc """
  The tenant's static/ folder at /tenant and its theme.css as the theme
  link; nothing at all without a tenant folder or without a theme.
  """
  use ExUnit.Case, async: false

  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]
  import Phoenix.Component, only: [sigil_H: 2]
  import Plug.Test

  alias Ui.TenantStatic

  setup do
    tenant = Path.join(System.tmp_dir!(), "tenant-static-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(tenant, "static/fonts"))
    File.write!(Path.join(tenant, "tenant.json"), ~s({"secret": true}))
    File.write!(Path.join(tenant, "static/fonts/brand.woff2"), "woff2")

    previous = Application.get_env(:ui, :tenant_dir)
    Application.put_env(:ui, :tenant_dir, tenant)

    on_exit(fn ->
      Application.put_env(:ui, :tenant_dir, previous)
      File.rm_rf!(tenant)
    end)

    %{tenant: tenant}
  end

  defp get(path), do: conn(:get, path) |> TenantStatic.call([])

  defp theme do
    assigns = %{}
    rendered_to_string(~H"<Ui.Components.tenant_theme />")
  end

  test "the static folder is served at /tenant, nothing outside it" do
    conn = get("/tenant/fonts/brand.woff2")
    assert {conn.status, conn.resp_body} == {200, "woff2"}
    assert Plug.Conn.get_resp_header(conn, "x-content-type-options") == ["nosniff"]

    # a path leaving the folder is refused (Plug answers 400)
    assert_raise Plug.Static.InvalidPathError, fn -> get("/tenant/../tenant.json") end
    refute get("/tenant/tenant.json").halted
    refute get("/tenant/missing.css").halted
    refute get("/assets/app.css").halted
  end

  test "a theme.css is the theme link, versioned by its change time", %{tenant: tenant} do
    assert theme() == ""

    File.write!(Path.join(tenant, "static/theme.css"), ":root { --brand: #0a5; }")
    assert TenantStatic.theme_href() =~ ~r{^/tenant/theme\.css\?v=\d+$}
    assert theme() =~ ~r{<link[^>]* rel="stylesheet" href="/tenant/theme\.css\?v=\d+">}
    assert get("/tenant/theme.css").resp_body =~ "--brand"
  end

  test "without a tenant folder nothing is served and there is no theme" do
    Application.put_env(:ui, :tenant_dir, nil)

    refute get("/tenant/fonts/brand.woff2").halted
    assert TenantStatic.theme_href() == nil
    assert theme() == ""
  end
end
