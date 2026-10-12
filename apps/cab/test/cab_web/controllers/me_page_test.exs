defmodule CabWeb.MePageTest do
  use CabWeb.ConnCase, async: true

  import Cab.Fixtures

  defp log_in(conn, user) do
    conn
    |> init_test_session(%{user_id: user.id})
    |> Plug.Conn.put_private(:plug_skip_csrf_protection, true)
  end

  test "anonymous hits the auth wall", %{conn: conn} do
    assert conn |> get(~p"/me") |> redirected_to() == "/signin"
  end

  test "engine stats verbatim + empty history in words", %{conn: conn} do
    user = user_fixture(%{username: "vera", node_user_id: 344})

    Req.Test.stub(Core.Engine, fn req ->
      case req.request_path do
        "/api/users/schedule" ->
          Req.Test.json(req, %{
            "status" => "success",
            "data" => %{"as_adjudicator" => [], "as_player" => []}
          })

        "/api/users/history" ->
          Req.Test.json(req, %{
            "status" => "success",
            "data" => %{"as_adjudicator" => [], "as_player" => []}
          })

        "/api/users/344/stats" ->
          Req.Test.json(req, %{
            "status" => "success",
            "data" => %{
              "overview" => %{
                "total_ballots_received" => 22,
                "total_debates_ranked" => 22,
                "average_speaker_score" => 77.4,
                "highest_score" => 84,
                "lowest_score" => 71
              },
              "placements" => %{"first_places" => 6, "win_rate_percentage" => 27.3}
            }
          })
      end
    end)

    html = conn |> log_in(user) |> get(~p"/me") |> html_response(200)

    assert html =~ ~s(id="me-stats")
    # the engine's numbers, as reported - nothing recomputed
    assert html =~ "77.40"
    assert html =~ "27.3%"
    assert html =~ ~s(id="me-history")
    assert html =~ "No sessions played yet."
    # the global sidenav lights My page
    assert html =~ ">My page<"
  end

  test "no logged debates yet - words, not an error", %{conn: conn} do
    user = user_fixture(%{node_user_id: 345})

    Req.Test.stub(Core.Engine, fn req ->
      case req.request_path do
        "/api/users/schedule" ->
          Req.Test.json(req, %{
            "status" => "success",
            "data" => %{"as_adjudicator" => [], "as_player" => []}
          })

        "/api/users/history" ->
          Req.Test.json(req, %{
            "status" => "success",
            "data" => %{"as_adjudicator" => [], "as_player" => []}
          })

        "/api/users/345/stats" ->
          Req.Test.json(req, %{"status" => "success", "data" => nil})
      end
    end)

    html = conn |> log_in(user) |> get(~p"/me") |> html_response(200)
    assert html =~ "No logged debates yet"
  end
end
