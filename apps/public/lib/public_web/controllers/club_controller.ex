defmodule PublicWeb.ClubController do
  use PublicWeb, :controller

  alias PublicWeb.Clubs

  def index(conn, params) do
    clubs = Clubs.list()
    shown = Clubs.filter(clubs, params)

    render(conn, :index,
      active: :clubs,
      page_title: gettext("Clubs"),
      clubs: shown,
      counts: Clubs.city_counts(clubs),
      cities: clubs |> Clubs.city_counts() |> Map.keys() |> Enum.sort(),
      shown_cities: map_size(Clubs.city_counts(shown)),
      filters: Map.take(params, ~w(city format language audience))
    )
  end

  def show(conn, %{"uuid" => uuid}) do
    club = Clubs.get(uuid) || raise PublicWeb.NotFound

    render(conn, :show,
      active: :clubs,
      page_title: club.name,
      club: club,
      members: Clubs.member_count(club),
      head: Clubs.head_name(club),
      counts: Clubs.city_counts([club])
    )
  end
end
