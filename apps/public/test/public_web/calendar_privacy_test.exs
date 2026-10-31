defmodule PublicWeb.CalendarPrivacyTest do
  @moduledoc """
  An admin can keep the whole calendar private: no event then reaches
  the public calendar, the home page or the iCal feed, while content
  managers keep preparing events under /manage.
  """
  use PublicWeb.ConnCase

  alias Public.{Events, Roles, Settings}

  setup do
    today = Date.utc_today()

    {:ok, _} =
      Events.create(
        %{
          "title" => "Northport Open",
          "kind" => "tournament",
          "starts_on" => Date.to_iso8601(today),
          "visibility" => "public"
        },
        1
      )

    editor = cab_user()
    {:ok, _} = Roles.grant(editor.id)
    %{editor: editor, admin: cab_user(%{is_admin: true})}
  end

  test "the calendar is public until an admin turns it off", %{conn: conn, admin: admin} do
    assert Settings.calendar_public?()
    assert conn |> get(~p"/calendar") |> html_response(200) =~ "Northport Open"

    signed = cab_sign_in(conn, admin)
    page = signed |> get(~p"/manage/calendar") |> html_response(200)
    assert page =~ ~s(id="calendar-public-switch")
    refute page =~ ~s(id="calendar-private-notice")

    resp = post(signed, ~p"/manage/calendar/public", %{"public" => "false"})
    assert redirected_to(resp) == "/manage/calendar"
    refute Settings.calendar_public?()

    assert signed |> get(~p"/manage/calendar") |> html_response(200) =~
             ~s(id="calendar-private-notice")
  end

  test "while private, no public page or feed shows an event", %{conn: conn, admin: admin} do
    {:ok, _} = Settings.set_calendar_public(false, admin.id)

    calendar = conn |> get(~p"/calendar") |> html_response(200)
    refute calendar =~ "Northport Open"
    assert calendar =~ ~s(id="calendar-not-public")
    refute calendar =~ "/calendar.ics"

    refute conn |> get(~p"/") |> html_response(200) =~ "Northport Open"

    ics = conn |> get(~p"/calendar.ics") |> response(200)
    assert ics =~ "BEGIN:VCALENDAR"
    assert ics =~ "END:VCALENDAR"
    refute ics =~ "Northport Open"

    {:ok, _} = Settings.set_calendar_public(true, admin.id)
    assert conn |> get(~p"/calendar") |> html_response(200) =~ "Northport Open"
    assert conn |> get(~p"/") |> html_response(200) =~ "Northport Open"
    assert conn |> get(~p"/calendar.ics") |> response(200) =~ "Northport Open"
  end

  test "content managers neither see nor flip the switch, but keep the events",
       %{conn: conn, editor: editor, admin: admin} do
    {:ok, _} = Settings.set_calendar_public(false, admin.id)
    signed = cab_sign_in(conn, editor)

    page = signed |> get(~p"/manage/calendar") |> html_response(200)
    refute page =~ ~s(id="calendar-public-switch")
    assert page =~ ~s(id="calendar-private-notice")
    assert page =~ "Northport Open"

    assert_error_sent 404, fn ->
      post(signed, ~p"/manage/calendar/public", %{"public" => "true"})
    end

    refute Settings.calendar_public?()
  end

  test "signed out, the switch does not exist", %{conn: conn} do
    assert_error_sent 404, fn ->
      post(conn, ~p"/manage/calendar/public", %{"public" => "false"})
    end

    assert Settings.calendar_public?()
  end
end
