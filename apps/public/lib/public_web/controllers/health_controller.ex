defmodule PublicWeb.HealthController do
  @moduledoc "GET /healthz - for the container health check: no session, one database ping."
  use PublicWeb, :controller

  def show(conn, _params) do
    case Ecto.Adapters.SQL.query(Public.Repo, "SELECT 1", []) do
      {:ok, _} -> conn |> put_resp_content_type("text/plain") |> send_resp(200, "ok")
      {:error, _} -> conn |> put_resp_content_type("text/plain") |> send_resp(503, "database")
    end
  end
end
