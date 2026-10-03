defmodule CabWeb.Api.SignupController do
  use CabWeb, :controller

  alias Cab.Sessions
  alias CabWeb.ClubScope

  action_fallback CabWeb.Api.FallbackController

  plug ClubScope, source: :session, require: :member

  # POST /api/v1/sessions/:uuid/signups {"as": "speak" | "judge"}
  def create(conn, %{"as" => kind}) when kind in ["speak", "judge"] do
    with {:ok, participant} <-
           Sessions.signup(conn.assigns.current_user, conn.assigns.session, kind) do
      conn
      |> put_status(201)
      |> json(%{participant_id: participant["id"], role: participant["role"]})
    end
  end

  def create(_conn, _params), do: {:error, ~s(sign up "as" must be "speak" or "judge")}
end
