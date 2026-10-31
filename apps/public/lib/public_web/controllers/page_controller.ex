defmodule PublicWeb.PageController do
  use PublicWeb, :controller

  alias Public.{Events, News}
  alias PublicWeb.Clubs

  def home(conn, _params) do
    today = Date.utc_today()
    clubs = Clubs.list()
    counts = Clubs.city_counts(clubs)
    upcoming = Events.upcoming_public(today, 4)

    render(conn, :home,
      active: :home,
      news: News.list_published(limit: 3),
      upcoming: upcoming,
      next_tournament: Enum.find(upcoming, &(&1.kind == "tournament")),
      counts: counts,
      club_count: length(clubs),
      city_count: map_size(counts)
    )
  end

  # a tenant's own page (pages/<slug>.<lang>.md), else not found
  def page(conn, %{"page" => slug}) do
    page = Public.Tenant.page(slug) || raise PublicWeb.NotFound
    render(conn, :page, active: {:page, slug}, page: page, page_title: page.title)
  end
end
