defmodule PublicWeb.EventPageTest do
  @moduledoc """
  Every calendar event has a page: public events at /calendar/:id while
  the calendar is public, any event at /manage/events/:id for content
  managers. Rows and month-grid chips open it, and its way back keeps
  the calendar's period, kind and tag.
  """
  use PublicWeb.ConnCase

  alias Public.{Events, Roles, Settings, Tags}

  defp event(attrs) do
    {:ok, event} =
      Events.create(
        Map.merge(
          %{
            "title" => "Northport Open",
            "kind" => "tournament",
            "starts_on" => "2026-11-14",
            "visibility" => "public"
          },
          attrs
        ),
        1
      )

    event
  end

  defp editor do
    user = cab_user()
    {:ok, _} = Roles.grant(user.id)
    user
  end

  test "the public page shows the event and its own link", %{conn: conn} do
    event =
      event(%{
        "ends_on" => "2026-11-15",
        "city" => "Northport",
        "format" => "BP",
        "language" => "en",
        "link" => "https://open.example.org/northport",
        "details" => "Two days of BP.\nFree entry.\n\nRegister by <b>Friday</b>."
      })

    html = conn |> get(~p"/calendar/#{event.id}") |> html_response(200)
    assert html =~ "<title>Northport Open"
    assert html =~ "<h1>Northport Open</h1>"
    assert html =~ "Tournament"
    assert html =~ "14 November 2026 - 15 November 2026"
    assert html =~ "Northport"
    assert html =~ "BP"
    assert html =~ "English"
    assert html =~ "<p>Two days of BP.\nFree entry.</p>"
    assert html =~ "<p>Register by &lt;b&gt;Friday&lt;/b&gt;.</p>"

    assert [link] = Regex.run(~r/<a[^>]*id="event-link"[^>]*>/, html)
    assert link =~ ~s(href="https://open.example.org/northport")
    assert link =~ ~s(target="_blank")
    assert link =~ ~s(rel="noopener")
    assert html =~ ~s(href="/calendar/#{event.id}/ics")
  end

  test "a one-day event without a link: one date, no link button", %{conn: conn} do
    event = event(%{"ends_on" => "2026-11-14"})

    html = conn |> get(~p"/calendar/#{event.id}") |> html_response(200)
    assert html =~ "14 November 2026"
    refute html =~ "14 November 2026 -"
    refute html =~ ~s(id="event-link")
    refute html =~ ~s(id="event-details")
  end

  test "private events, missing ones and any while the calendar is private are 404",
       %{conn: conn} do
    private = event(%{"visibility" => "private"})
    assert_error_sent 404, fn -> get(conn, ~p"/calendar/#{private.id}") end
    assert_error_sent 404, fn -> get(conn, ~p"/calendar/#{private.id}/ics") end
    assert_error_sent 404, fn -> get(conn, "/calendar/0") end
    assert_error_sent 404, fn -> get(conn, "/calendar/nope") end
    assert_error_sent 404, fn -> get(conn, "/calendar/99999999999999999999") end

    public = event(%{})
    {:ok, _} = Settings.set_calendar_public(false, cab_user(%{is_admin: true}).id)
    assert_error_sent 404, fn -> get(conn, ~p"/calendar/#{public.id}") end
    assert_error_sent 404, fn -> get(conn, ~p"/calendar/#{public.id}/ics") end
  end

  test "the event request form keeps its address", %{conn: conn} do
    assert conn |> get(~p"/calendar/request") |> html_response(200) =~ "request"
  end

  test "Add to my calendar: the one event, in the feed's format", %{conn: conn} do
    event = event(%{"city" => "Northport", "link" => "https://open.example.org/northport"})
    event(%{"title" => "Southport Cup"})

    resp = get(conn, ~p"/calendar/#{event.id}/ics")
    ics = response(resp, 200)
    assert ["text/calendar" <> _] = get_resp_header(resp, "content-type")
    assert [disposition] = get_resp_header(resp, "content-disposition")
    assert disposition =~ ~s(filename="event-#{event.id}.ics")

    assert ics =~ "BEGIN:VCALENDAR"
    assert ics =~ "UID:event-#{event.id}@"
    assert ics =~ "SUMMARY:Northport Open"
    assert ics =~ "LOCATION:Northport"
    assert ics =~ "URL:https://open.example.org/northport"
    refute ics =~ "Southport Cup"
    assert length(String.split(ics, "BEGIN:VEVENT")) == 2
  end

  test "calendar rows and chips open the page; the way back keeps the filters",
       %{conn: conn} do
    event = event(%{"link" => "https://open.example.org/northport"})

    month = conn |> get(~p"/calendar?month=2026-11&kind=tournament") |> html_response(200)
    href = "/calendar/#{event.id}?month=2026-11&amp;kind=tournament"
    assert month =~ ~s(<a class="ua-ev-link" href="#{href}">Northport Open</a>)
    assert month =~ ~r/<a class="ua-chip[^"]*" href="#{Regex.escape(href)}">/
    refute month =~ ~s(href="https://open.example.org/northport")

    year = conn |> get(~p"/calendar?view=year&year=2026") |> html_response(200)
    assert year =~ ~s(href="/calendar/#{event.id}?view=year&amp;year=2026")

    page =
      conn
      |> get("/calendar/#{event.id}?view=year&year=2026&kind=tournament")
      |> html_response(200)

    assert page =~ ~s(id="back-to-calendar")
    assert page =~ ~s(href="/calendar?view=year&amp;year=2026&amp;kind=tournament")

    home = conn |> get(~p"/") |> html_response(200)
    assert home =~ ~s(href="/calendar/#{event.id}")
  end

  test "the manage page shows any event, its tags and the calendar's actions",
       %{conn: conn} do
    {:ok, tag} = Tags.create(%{"name" => "Needs judges", "color" => "red"})

    event =
      event(%{
        "title" => "Closed sparring",
        "kind" => "training",
        "visibility" => "private",
        "details" => "Invite only.",
        "tag_ids" => [to_string(tag.id)]
      })

    signed = cab_sign_in(conn, editor())

    html =
      signed
      |> get("/manage/events/#{event.id}?month=2026-11&tag=#{tag.id}")
      |> html_response(200)

    assert html =~ "<h1>Closed sparring</h1>"
    assert html =~ "Training"
    assert html =~ "Invite only."
    assert html =~ "Needs judges"
    assert html =~ ~s(href="/manage/events/#{event.id}/edit")

    assert html =~
             ~s(action="/manage/events/#{event.id}/visibility?month=2026-11&amp;tag=#{tag.id}")

    assert html =~ ~s(name="back" value="event")
    assert html =~ ~r/<form[^>]*action="\/manage\/events\/#{event.id}"/
    assert html =~ ~r/name="_method"[^>]*value="delete"/
    assert html =~ ~s(href="/manage/calendar?month=2026-11&amp;tag=#{tag.id}")

    # the switch on the page comes back to the page, filters kept
    resp =
      post(signed, "/manage/events/#{event.id}/visibility?month=2026-11&tag=#{tag.id}", %{
        "visibility" => "public",
        "back" => "event"
      })

    assert redirected_to(resp) == "/manage/events/#{event.id}?month=2026-11&tag=#{tag.id}"
    assert Events.get!(event.id).visibility == "public"

    # the calendar's own switch still returns to the calendar
    resp = post(signed, ~p"/manage/events/#{event.id}/visibility", %{"visibility" => "private"})
    assert redirected_to(resp) == "/manage/calendar?month=2026-11"

    # the public never sees /manage, nor the private event
    assert_error_sent 404, fn ->
      conn |> cab_sign_in(cab_user()) |> get(~p"/manage/events/#{event.id}")
    end

    assert_error_sent 404, fn -> get(conn, ~p"/calendar/#{event.id}") end
  end

  test "manage rows and chips open the manage page, the row's switch stays a form",
       %{conn: conn} do
    event = event(%{})
    signed = cab_sign_in(conn, editor())

    html = signed |> get(~p"/manage/calendar?month=2026-11") |> html_response(200)
    href = "/manage/events/#{event.id}?month=2026-11"
    assert html =~ ~s(<a class="ua-ev-link" href="#{href}">Northport Open</a>)
    assert html =~ ~r/<a class="ua-chip[^"]*" href="#{Regex.escape(href)}">/
    assert html =~ ~s(action="/manage/events/#{event.id}/visibility")

    # no form or link inside the title's link
    for [inner] <-
          Regex.scan(~r/<a class="ua-ev-link"[^>]*>(.*?)<\/a>/s, html, capture: :all_but_first) do
      refute inner =~ "<a"
      refute inner =~ "<form"
      refute inner =~ "<button"
    end
  end
end
