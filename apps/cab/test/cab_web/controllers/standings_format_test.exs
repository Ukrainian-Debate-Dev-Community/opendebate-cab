defmodule CabWeb.StandingsFormatTest do
  @moduledoc """
  BP and Australs never share a figure: the club's speakers table and
  My page's stats show one format at a time.
  """
  use CabWeb.ConnCase, async: true

  import Cab.Fixtures

  defp log_in(conn, user), do: init_test_session(conn, %{user_id: user.id})

  defp ok(conn, data), do: Req.Test.json(conn, %{"status" => "success", "data" => data})

  defp format_of(conn), do: Plug.Conn.fetch_query_params(conn).query_params["format"]

  test "the club's speakers: one table per format, the latest night's first", %{conn: conn} do
    head = user_fixture(%{node_user_id: 19})
    club = club_fixture(head, %{engine_organisation_id: 3})
    session_fixture(club, engine_event_id: 10, finished_at: ~U[2026-10-01 20:00:00Z])

    session_fixture(club,
      engine_event_id: 11,
      format: "aus",
      finished_at: ~U[2026-10-08 20:00:00Z]
    )

    Req.Test.stub(Core.Engine, fn conn ->
      case conn.request_path do
        "/api/organisations/3/standings/speakers" ->
          name = if format_of(conn) == "AUS", do: "Ada of Australs", else: "Bo of BP"
          ok(conn, [%{"user_id" => 7, "name" => name, "total_points" => 70}])

        "/api/events/11" ->
          ok(conn, %{"id" => 11, "name" => "Night", "status" => "completed"})
      end
    end)

    html =
      conn |> log_in(head) |> get(~p"/c/#{club.uuid}/standings/speakers") |> html_response(200)

    assert html =~ "Ada of Australs"
    refute html =~ "Bo of BP"
    assert html =~ ~s(href="/c/#{club.uuid}/standings/speakers?format=bp")

    bp =
      conn
      |> log_in(head)
      |> get(~p"/c/#{club.uuid}/standings/speakers?format=bp")
      |> html_response(200)

    assert bp =~ "Bo of BP"
  end

  test "My page: the format debated most, the other a click away", %{conn: conn} do
    user = user_fixture(%{node_user_id: 344})

    stats = fn ranked, rate ->
      %{
        "overview" => %{
          "total_ballots_received" => ranked,
          "total_debates_ranked" => ranked,
          "average_speaker_score" => 75,
          "highest_score" => 80,
          "lowest_score" => 70
        },
        "placements" => %{"first_places" => 1, "win_rate_percentage" => rate}
      }
    end

    Req.Test.stub(Core.Engine, fn conn ->
      case conn.request_path do
        "/api/users/344/stats" ->
          if format_of(conn) == "AUS",
            do: ok(conn, stats.(9, 55.5)),
            else: ok(conn, stats.(3, 12.5))

        _schedule_or_history ->
          ok(conn, %{"as_adjudicator" => [], "as_player" => []})
      end
    end)

    html = conn |> log_in(user) |> get(~p"/me") |> html_response(200)
    assert html =~ "55.5%"
    refute html =~ "12.5%"
    assert html =~ ~s(href="/me?format=bp")

    bp = conn |> log_in(user) |> get(~p"/me?format=bp") |> html_response(200)
    assert bp =~ "12.5%"
  end
end
