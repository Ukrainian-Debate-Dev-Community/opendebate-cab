defmodule PublicWeb.CalendarController do
  use PublicWeb, :controller

  alias Public.Events
  alias Public.Events.Event
  alias PublicWeb.{CalendarHTML, Period}

  def index(conn, params) do
    period = Period.parse(params)
    kind = kind(params)

    render(conn, :index,
      active: :calendar,
      page_title: gettext("Calendar"),
      period: period,
      kind: kind,
      calendar_public: Public.Settings.calendar_public?(),
      events: Events.public_in(Period.range(period), kind)
    )
  end

  # one public event; the calendar's period and kind ride along in the
  # query, so the way back shows what the visitor was looking at
  def show(conn, %{"id" => id} = params) do
    event = Events.get_public(id) || raise PublicWeb.NotFound

    render(conn, :show,
      active: :calendar,
      page_title: event.title,
      event: event,
      back: CalendarHTML.link(~p"/calendar", Period.parse(params), kind(params), nil)
    )
  end

  # the public events as an iCalendar feed; private ones never leave /manage
  def ics(conn, _params) do
    conn
    |> put_resp_content_type("text/calendar")
    |> send_resp(200, Public.ICal.feed(Events.all_public(), conn.host, &language_line/1))
  end

  # one public event, in the feed's format, for "Add to my calendar"
  def event_ics(conn, %{"id" => id}) do
    event = Events.get_public(id) || raise PublicWeb.NotFound

    conn
    |> put_resp_content_type("text/calendar")
    |> put_resp_header("content-disposition", ~s(attachment; filename="event-#{event.id}.ics"))
    |> send_resp(200, Public.ICal.feed([event], conn.host, &language_line/1))
  end

  defp kind(params), do: if(params["kind"] in Event.kinds(), do: params["kind"])

  defp language_line(event) do
    if language = PublicWeb.Site.event_language(event),
      do: gettext("Language: %{language}", language: language)
  end
end
