defmodule PublicWeb.Manage.CalendarController do
  use PublicWeb, :controller

  alias Public.Events
  alias Public.Events.Event
  alias PublicWeb.Period

  def index(conn, params) do
    period = Period.parse(params)
    kind = if params["kind"] in Event.kinds(), do: params["kind"]
    tag = Public.Tags.find(params["tag"])

    conn
    |> put_view(PublicWeb.Manage.HTML)
    |> render(:calendar,
      manage_active: :calendar,
      page_title: gettext("Calendar"),
      period: period,
      kind: kind,
      tag: tag,
      tags: Public.Tags.list(),
      calendar_public: Public.Settings.calendar_public?(),
      events: Events.all_in(Period.range(period), kind, tag)
    )
  end

  # POST /manage/calendar/public {"public": "true" | "false"} - cab admins
  # only; for everyone else, content managers included, it does not exist
  def set_public(%{assigns: %{access: :admin}} = conn, %{"public" => public}) do
    public? = public == "true"
    {:ok, _} = Public.Settings.set_calendar_public(public?, conn.assigns.manager.id)

    conn
    |> put_flash(
      :info,
      if(public?,
        do: gettext("The calendar is public again."),
        else: gettext("The calendar is private: no event reaches the public site.")
      )
    )
    |> redirect(to: ~p"/manage/calendar")
  end

  def set_public(_conn, _params), do: raise(PublicWeb.NotFound)
end
