defmodule CabWeb.MeController do
  @moduledoc """
  GET /me — the signed-in user's personal page: engine statistics
  VERBATIM (`GET /users/:id/stats`, rule 0 — cab never derives its
  own numbers) plus the participation history rows.
  """
  use CabWeb, :controller

  alias Cab.{Accounts, EngineApi, Sessions}

  import CabWeb.UserAuth, only: [require_account: 2]

  plug :require_account

  def show(conn, _params) do
    user = conn.assigns.current_user

    render(conn, :show,
      stats: fetch_stats(user),
      history: Sessions.user_history(user),
      page_title: "my page"
    )
  end

  # the engine's stats payload or nil (never participated / engine
  # trouble) — the page says so in words either way
  defp fetch_stats(user) do
    with %{node_user_id: id} when is_integer(id) <- Accounts.ensure_node_user(user),
         {:ok, stats} when is_map(stats) <- EngineApi.user_stats(id, id) do
      stats
    else
      _ -> nil
    end
  end
end
