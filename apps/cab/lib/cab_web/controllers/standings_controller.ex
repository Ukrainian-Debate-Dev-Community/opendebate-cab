defmodule CabWeb.StandingsController do
  @moduledoc """
  `/standings/{teams|speakers|judges|clubs}` — the global standings,
  RULE 0: engine output verbatim for the latest finished session of a
  public club (teams, speakers, judge stats); clubs = plain counts from
  cab's records. No cab-side math.
  """

  use CabWeb, :controller

  alias Cab.Standings

  def index(conn, _params), do: redirect(conn, to: ~p"/standings/teams")

  def show(conn, %{"tab" => tab}) when tab in ~w(teams speakers judges) do
    scope = Standings.latest_finished()

    conn
    |> CabWeb.Caching.no_store()
    |> render(:show,
      tab: tab,
      scope: scope,
      rows: rows(tab, scope),
      club: nil,
      page_title: "standings"
    )
  end

  def show(conn, %{"tab" => "clubs"}) do
    render(conn, :show,
      tab: "clubs",
      scope: nil,
      rows: Standings.clubs(),
      club: nil,
      page_title: "standings"
    )
  end

  def show(conn, _params), do: conn |> CabWeb.ErrorHTML.respond(404)

  defp rows(_tab, nil), do: []
  defp rows("teams", scope), do: Standings.teams(scope)
  defp rows("speakers", scope), do: Standings.speakers(scope)
  defp rows("judges", scope), do: Standings.judges(scope)
end
