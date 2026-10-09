defmodule CabWeb.TimeZoneTest do
  use CabWeb.ConnCase, async: true

  import Cab.Fixtures
  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias Cab.Accounts

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
end
