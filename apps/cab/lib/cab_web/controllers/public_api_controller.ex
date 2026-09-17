defmodule CabWeb.PublicApiController do
  use CabWeb, :controller

  def tournaments(conn, _params) do
    # Engine's GET /api/events is public — no engine-side auth needed.
    case Core.Engine.public_get("/api/events") do
      {:ok, %Req.Response{status: 200, body: body}} ->
        json(conn, body)

      _error ->
        # TODO: serve cached last-known tournament list instead of a bare 502
        conn
        |> put_status(:bad_gateway)
        |> json(%{error: "engine_unavailable"})
    end
  end
end
