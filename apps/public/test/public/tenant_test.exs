defmodule Public.TenantTest do
  # loads tenants of its own into the shared :persistent_term: not async
  use ExUnit.Case, async: false

  alias Public.Tenant

  @fixture Path.expand("../support/tenant", __DIR__)

  defp folder(tenant, map \\ nil) do
    dir = Path.join(System.tmp_dir!(), "tenant-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    File.write!(Path.join(dir, "tenant.json"), Jason.encode!(tenant))
    File.write!(Path.join(dir, "map.json"), Jason.encode!(map || fixture("map.json")))
    dir
  end

  defp fixture(file), do: @fixture |> Path.join(file) |> File.read!() |> Jason.decode!()

  test "the neutral test tenant has every key the site needs" do
    assert %{"name" => "LeagueSite", "map" => %{"size" => [200, 100]}} = Tenant.read!(@fixture)
  end

  test "a folder missing keys refuses to load, naming every one of them" do
    tenant =
      fixture("tenant.json")
      |> Map.delete("org")
      |> update_in(["home"], &Map.delete(&1, "kicker"))
      |> update_in(["cab"], &Map.put(&1, "welcome", nil))

    map = Map.delete(fixture("map.json"), "outline")

    error = assert_raise ArgumentError, fn -> Tenant.read!(folder(tenant, map)) end

    for key <- ~w(org home.kicker cab.welcome map.outline) do
      assert error.message =~ key
    end

    refute error.message =~ "since"
  end

  test "a branch the map cannot place refuses to load" do
    map = Map.put(fixture("map.json"), "branches", ["Northport", "Nowhere"])

    error =
      assert_raise ArgumentError, fn -> Tenant.read!(folder(fixture("tenant.json"), map)) end

    assert error.message =~ "map.cities.Nowhere"
  end

  test "a page that does not read, or has no English file, refuses to load" do
    dir = folder(fixture("tenant.json"))
    File.mkdir_p!(Path.join(dir, "pages"))

    File.write!(
      Path.join([dir, "pages", "rules.en.md"]),
      "---\ntitle: Rules\n---\n::: gallery :::\n"
    )

    File.write!(Path.join([dir, "pages", "join.uk.md"]), "---\ntitle: UK Join\n---\nText\n")

    error = assert_raise ArgumentError, fn -> Tenant.read!(dir) end
    assert error.message =~ "pages/rules.en.md: unknown block gallery"
    assert error.message =~ "pages/join.en.md"
  end

  test "pages: in the locale or English, the menu by nav" do
    assert %{title: "About the league"} = Tenant.page("about", "en")
    assert %{title: "UK About the league"} = Tenant.page("about", "uk")
    assert Tenant.page("about", "de").title == "About the league"
    assert Tenant.page("nowhere", "en") == nil
    assert Tenant.nav_pages("uk") == [{"about", "UK About the league"}]
  end

  test "a missing file refuses to load" do
    dir = Path.join(System.tmp_dir!(), "tenant-test-none-#{System.unique_integer([:positive])}")
    assert_raise ArgumentError, ~r/tenant\.json/, fn -> Tenant.read!(dir) end
  end

  test "home.notice and event_requests_email may be null or left out" do
    tenant =
      fixture("tenant.json")
      |> Map.delete("event_requests_email")
      |> put_in(["home", "notice"], nil)

    assert %{"name" => "LeagueSite"} = Tenant.read!(folder(tenant))
  end

  test "texts are given in the locale, English when the locale has none" do
    assert Tenant.text(:org, "en") == "League org"
    assert Tenant.text([:labels, :news], "uk") == "UK League news"
    assert Tenant.translate(%{"en" => "Only English"}, "uk") == "Only English"
    assert Tenant.translate(%{"en" => "English", "uk" => ""}, "uk") == "English"
    assert Tenant.translate("plain", "uk") == "plain"
    assert Tenant.translate(nil, "uk") == nil
  end

  test "texts follow the page language by default" do
    Gettext.with_locale(PublicWeb.Gettext, "uk", fn ->
      assert Tenant.text(:org) == "UK League org"
    end)

    Gettext.with_locale(PublicWeb.Gettext, "en", fn ->
      assert Tenant.text(:org) == "League org"
    end)
  end

  test "get reads plain values and nested keys" do
    assert Tenant.get(:name) == "LeagueSite"
    assert Tenant.get([:cab, :site_url]) == "https://league.example.org"
    assert Tenant.get([:map, :branches]) == ["Northport", "Southport"]
    assert Tenant.get([:no, :such]) == nil
  end
end
