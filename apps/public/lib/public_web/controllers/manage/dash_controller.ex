defmodule PublicWeb.Manage.DashController do
  use PublicWeb, :controller

  alias Public.{Events, News}

  def show(conn, _params) do
    upcoming = Events.upcoming_all(Date.utc_today())

    conn
    |> put_view(PublicWeb.Manage.HTML)
    |> render(:dash,
      manage_active: :dash,
      page_title: gettext("Manage"),
      published: length(News.list_published()),
      drafts: News.count_drafts(),
      upcoming: Enum.take(upcoming, 5),
      upcoming_count: length(upcoming),
      private_count: Enum.count(upcoming, &(&1.visibility == "private"))
    )
  end
end
