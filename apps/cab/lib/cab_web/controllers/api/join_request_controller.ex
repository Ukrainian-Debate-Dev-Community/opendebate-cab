defmodule CabWeb.Api.JoinRequestController do
  use CabWeb, :controller

  alias Cab.Clubs
  alias CabWeb.ClubScope

  action_fallback CabWeb.Api.FallbackController

  plug ClubScope, [source: :club, require: :authenticated] when action == :create
  plug ClubScope, [source: :join_request, require: :owner] when action == :update

  # POST /api/v1/clubs/:uuid/join-requests {"message", "contact"} -
  # a join request IS a pending membership; both answers are
  # REQUIRED (the join form's fields, read by the head in Requests)
  def create(conn, params) do
    with {:ok, membership} <-
           Clubs.request_join(conn.assigns.current_user, conn.assigns.club, params) do
      conn
      |> put_status(201)
      |> json(%{
        id: membership.id,
        status: membership.status,
        message: membership.message,
        contact: membership.contact
      })
    end
  end

  # PATCH /api/v1/join-requests/:id {"action": "approve" | "decline"}
  def update(conn, params) do
    membership = conn.assigns.join_request

    case params["action"] do
      "approve" ->
        with {:ok, membership} <- Clubs.approve_join(membership) do
          json(conn, %{id: membership.id, status: membership.status})
        end

      "decline" ->
        with {:ok, _} <- Clubs.decline_join(membership) do
          json(conn, %{id: membership.id, status: "declined"})
        end

      _ ->
        {:error, ~s(action must be "approve" or "decline")}
    end
  end
end
