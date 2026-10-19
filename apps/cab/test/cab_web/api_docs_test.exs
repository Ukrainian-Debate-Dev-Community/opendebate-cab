defmodule CabWeb.ApiDocsTest do
  @moduledoc """
  The API reference: cab's description must match the router's /api/cab/v1
  routes both ways, the engine's description must be the pinned
  engine's own file, and the page loads nothing from elsewhere.
  """
  use CabWeb.ConnCase, async: true

  @priv Path.expand("../../priv/api", __DIR__)
  @engine_spec Path.expand("../../../../engine/docs/openapi.yml", __DIR__)

  defp spec, do: @priv |> Path.join("cab.json") |> File.read!() |> Jason.decode!()

  test "cab.json documents exactly the router's /api/cab/v1 routes" do
    routed =
      for %{verb: verb, path: "/api/cab/v1" <> path} <- Phoenix.Router.routes(CabWeb.Router),
          into: MapSet.new(),
          do: {verb |> to_string() |> String.upcase(), Regex.replace(~r/:(\w+)/, path, "{\\1}")}

    documented =
      for {path, ops} <- spec()["paths"],
          {method, _op} <- ops,
          into: MapSet.new(),
          do: {String.upcase(method), path}

    assert MapSet.difference(routed, documented) |> Enum.sort() == [],
           "routes missing from priv/api/cab.json"

    assert MapSet.difference(documented, routed) |> Enum.sort() == [],
           "documented routes the router does not have"
  end

  test "every documented operation has a summary, responses and plain ASCII" do
    for {path, ops} <- spec()["paths"], {method, op} <- ops do
      assert op["summary"] not in [nil, ""], "#{method} #{path} has no summary"
      assert map_size(op["responses"] || %{}) > 0, "#{method} #{path} has no responses"
    end

    raw = File.read!(Path.join(@priv, "cab.json"))
    assert raw == for(<<c <- raw>>, c < 128, into: "", do: <<c>>), "cab.json must be ASCII"
  end

  test "engine.yml is the pinned engine's own description, unchanged" do
    assert File.read!(Path.join(@priv, "engine.yml")) == File.read!(@engine_spec),
           "run make dev:api-docs to refresh the copy"
  end

  test "the page and both descriptions are served without a session", %{conn: conn} do
    page = get(conn, ~p"/api/cab/docs")
    html = html_response(page, 200)
    assert get_resp_header(page, "set-cookie") == []
    assert html =~ ~s(<title>cab API</title>)

    for [url] <- Regex.scan(~r/(?:src|href)="([^"]+)"/, html, capture: :all_but_first) do
      refute url =~ ~r{^(https?:)?//}, "the page must not load #{url} from elsewhere"
    end

    engine = conn |> get(~p"/api/engine/docs") |> html_response(200)
    assert engine =~ ~s(data-doc="engine")
    assert engine =~ ~s(href="/api/cab/docs")
    assert conn |> get("/api/docs") |> redirected_to() == "/api/cab/docs"

    assert conn |> get(~p"/api/cab/docs/openapi.json") |> json_response(200) |> Map.get("openapi") ==
             "3.1.0"

    yml = get(conn, ~p"/api/engine/docs/openapi.yml")
    assert response(yml, 200) =~ "openapi:"
    assert get_resp_header(yml, "content-type") |> hd() =~ "yaml"
  end

  test "nothing on the page links out to Scalar's services" do
    static = Path.expand("../../priv/static/apidocs", __DIR__)
    boot = File.read!(Path.join(static, "boot.js"))
    theme = File.read!(Path.join(static, "theme.css"))

    common = boot |> String.split("var cab =") |> hd()
    assert common =~ "hideClientButton: true", "no button out to client.scalar.com"
    assert common =~ "telemetry: false"
    assert common =~ "withDefaultFonts: false"
    refute theme =~ ~s(a[href*="scalar.com"]), "the Powered by credit stays visible"

    assert boot =~ ~s{setAttribute("href", "https://scalar.com/")},
           "the credit drops its tracking tags"
  end
end
