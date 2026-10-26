defmodule CabWeb.TimeZoneTest do
  # async: false - one test sets the deployment's default zone
  use CabWeb.ConnCase, async: false

  import Cab.Fixtures
  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias Cab.{Accounts, Sessions, TimeZones}

  test "an account keeps a time zone from the list, or follows its device" do
    user = user_fixture()

    {:ok, user} = Accounts.update_profile(user, %{"time_zone" => "Europe/Kyiv"})
    assert user.time_zone == "Europe/Kyiv"

    # anything off the list is ignored
    {:ok, user} = Accounts.update_profile(user, %{"time_zone" => "Mars/Olympus"})
    assert user.time_zone == "Europe/Kyiv"

    {:ok, user} = Accounts.update_profile(user, %{"time_zone" => ""})
    assert user.time_zone == nil
  end

  test "pages carry the account's zone for the browser to format times in", %{conn: conn} do
    user = user_fixture()
    {:ok, user} = Accounts.update_profile(user, %{"time_zone" => "Europe/Kyiv"})

    html =
      conn |> init_test_session(%{user_id: user.id}) |> get(~p"/account") |> html_response(200)

    assert html =~ ~s(data-tz="Europe/Kyiv")
    assert html =~ ~s(name="time_zone")
  end

  test "a time renders as its UTC instant with a UTC fallback text" do
    assigns = %{at: ~U[2026-10-09 15:30:00Z]}

    html = rendered_to_string(~H"<CabWeb.Ui.local_time at={@at} as={:short} />")
    assert html =~ ~s(datetime="2026-10-09T15:30:00Z")
    assert html =~ ~s(data-when="short")
    assert html =~ "9 Oct, 15:30 UTC"
  end

  describe "the schedule form's date and time" do
    test "read in the account's zone, summer and winter time alike" do
      {:ok, user} = Accounts.update_profile(user_fixture(), %{"time_zone" => "Europe/Kyiv"})
      zone = TimeZones.for_form(nil, user)
      assert zone == "Europe/Kyiv"

      assert Sessions.parse_schedule("2026-07-01", "18:30", zone) ==
               {:ok, ~U[2026-07-01 15:30:00Z]}

      assert Sessions.parse_schedule("2026-12-01", "18:30", zone) ==
               {:ok, ~U[2026-12-01 16:30:00Z]}

      # a picker that sends seconds
      assert Sessions.parse_schedule("2026-12-01", "18:30:00", zone) ==
               {:ok, ~U[2026-12-01 16:30:00Z]}

      # the browser's zone wins; one Postgres does not know does not
      assert TimeZones.for_form("Asia/Kolkata", user) == "Asia/Kolkata"
      assert TimeZones.for_form("Mars/Olympus", user) == "Europe/Kyiv"
      assert TimeZones.for_form("", user) == "Europe/Kyiv"
    end

    test "read in the deployment's default zone for an account without one" do
      user = user_fixture()
      assert TimeZones.for_form(nil, user) == "Etc/UTC"

      assert Sessions.parse_schedule("2026-07-01", "18:30", "Etc/UTC") ==
               {:ok, ~U[2026-07-01 18:30:00Z]}

      previous = Application.get_env(:cab, :default_time_zone)
      Application.put_env(:cab, :default_time_zone, "Europe/Warsaw")
      on_exit(fn -> Application.put_env(:cab, :default_time_zone, previous) end)

      zone = TimeZones.for_form(nil, user)
      assert zone == "Europe/Warsaw"

      assert Sessions.parse_schedule("2026-07-01", "18:30", zone) ==
               {:ok, ~U[2026-07-01 16:30:00Z]}
    end

    test "DST changes: a skipped time moves on an hour, a repeated one is the later" do
      # Kyiv: 03:00 -> 04:00 on 29 Mar 2026, 04:00 -> 03:00 on 25 Oct 2026
      assert TimeZones.to_utc(~N[2026-03-29 02:59:00], "Europe/Kyiv") == ~U[2026-03-29 00:59:00Z]
      assert TimeZones.to_utc(~N[2026-03-29 03:30:00], "Europe/Kyiv") == ~U[2026-03-29 01:30:00Z]
      assert TimeZones.to_utc(~N[2026-03-29 04:00:00], "Europe/Kyiv") == ~U[2026-03-29 01:00:00Z]
      assert TimeZones.to_utc(~N[2026-10-25 03:30:00], "Europe/Kyiv") == ~U[2026-10-25 01:30:00Z]

      # and back: both instants of the repeated hour show as 03:30
      assert TimeZones.local_parts(~U[2026-10-25 00:30:00Z], "Europe/Kyiv") ==
               ["2026-10-25", "03:30"]

      assert TimeZones.local_parts(~U[2026-10-25 01:30:00Z], "Europe/Kyiv") ==
               ["2026-10-25", "03:30"]

      assert TimeZones.local_parts(~U[2026-10-24 22:30:00Z], "Europe/Kyiv") ==
               ["2026-10-25", "01:30"]
    end

    test "the pickers render prefilled in the given zone, the instant beside them" do
      assigns = %{at: ~U[2026-12-01 16:30:00Z]}

      html =
        rendered_to_string(~H"""
        <CabWeb.Ui.form_for action="/schedule">
          <:block names={[:date, :time]} type={:datetime} at={@at} zone="Europe/Kyiv" />
        </CabWeb.Ui.form_for>
        """)

      assert html =~ ~s(data-at="2026-12-01T16:30:00Z")
      assert html =~ ~s(type="date" name="date" value="2026-12-01")
      assert html =~ ~s(type="time" name="time" value="18:30")
      assert html =~ ~s(type="hidden" name="zone" value="Europe/Kyiv")

      # nothing planned yet: empty pickers, the server picks the zone
      html =
        rendered_to_string(~H"""
        <CabWeb.Ui.form_for action="/schedule">
          <:block names={[:date, :time]} type={:datetime} />
        </CabWeb.Ui.form_for>
        """)

      refute html =~ "data-at"
      assert html =~ ~s(<input type="date" name="date")
      refute html =~ ~s(name="date" value=)
      assert html =~ ~s(<input type="hidden" name="zone">)
    end
  end
end
