defmodule PublicWeb.Manage.EventController do
  use PublicWeb, :controller

  alias Public.{EventRequests, Events, Tags}
  alias Public.Events.Event
  alias PublicWeb.{CalendarHTML, Emails, Period}
  alias PublicWeb.Manage.HTML

  plug :put_view, PublicWeb.Manage.HTML

  # ?request=<id>: accepting a public request - the form prefilled from
  # its answers; the request counts accepted once the event is saved
  def new(conn, %{"request" => id}) do
    request = EventRequests.get!(id)
    attrs = EventRequests.event_attrs(request)
    conn |> assign(:request, request) |> render_form(nil, Events.change(%Event{}, attrs), attrs)
  end

  def new(conn, _params), do: render_form(conn, nil, Events.change())

  def create(conn, %{"event" => attrs} = params) do
    request = params["request_id"] && EventRequests.get!(params["request_id"])

    case Events.create(attrs, conn.assigns.manager.id) do
      {:ok, event} ->
        conn
        |> put_flash(:info, gettext("Event saved."))
        |> accept_request(request, event)
        |> redirect(to: back_to(event))

      {:error, changeset} ->
        conn |> assign(:request, request) |> render_form(nil, changeset, attrs)
    end
  end

  defp accept_request(conn, nil, _event), do: conn

  defp accept_request(conn, request, event) do
    case EventRequests.accept(request, event.id, conn.assigns.manager.id) do
      {:ok, request} ->
        Emails.request_accepted(request, event.title)

        put_flash(
          conn,
          :info,
          gettext("Event saved and the request accepted. The requester got an e-mail.")
        )

      {:error, _decided} ->
        conn
    end
  end

  # any event, private ones too; the calendar's period, kind and tag ride
  # along in the query, so the way back shows the same calendar
  def show(conn, %{"id" => id} = params) do
    event = Events.get!(id)

    render(conn, :event,
      manage_active: :calendar,
      page_title: event.title,
      event: event,
      back: with_filters(~p"/manage/calendar", params),
      visibility_action: with_filters(~p"/manage/events/#{event.id}/visibility", params)
    )
  end

  def edit(conn, %{"id" => id}) do
    event = Events.get!(id)
    render_form(conn, event, Events.change(event))
  end

  def update(conn, %{"id" => id, "event" => attrs}) do
    event = Events.get!(id)

    case Events.update(event, attrs) do
      {:ok, event} ->
        conn
        |> put_flash(:info, gettext("Event saved."))
        |> redirect(to: back_to(event))

      {:error, changeset} ->
        render_form(conn, event, changeset, attrs)
    end
  end

  def delete(conn, %{"id" => id}) do
    event = Events.get!(id)
    {:ok, _} = Events.delete(event)

    conn
    |> put_flash(:info, gettext("Event deleted."))
    |> redirect(to: back_to(event))
  end

  # back=event: sent from the event's page, which it returns to
  def visibility(conn, %{"id" => id, "visibility" => visibility} = params)
      when visibility in ~w(public private) do
    event = Events.get!(id)
    {:ok, event} = Events.set_visibility(event, visibility)

    redirect(conn,
      to:
        if(params["back"] == "event",
          do: with_filters(~p"/manage/events/#{event.id}", params),
          else: back_to(event)
        )
    )
  end

  defp render_form(conn, event, changeset, attrs \\ %{}) do
    render(conn, :event_form,
      manage_active: :calendar,
      page_title: if(event, do: event.title, else: gettext("New event")),
      event: event,
      request: conn.assigns[:request],
      form: to_form(changeset, as: :event),
      tags: Tags.list(),
      selected_tags: HTML.selected_tag_ids(attrs, event)
    )
  end

  defp with_filters(base, params) do
    kind = if params["kind"] in Event.kinds(), do: params["kind"]
    CalendarHTML.link(base, Period.parse(params), kind, Tags.find(params["tag"]))
  end

  defp back_to(event),
    do: ~p"/manage/calendar?#{[month: PublicWeb.Month.param(event.starts_on)]}"
end
