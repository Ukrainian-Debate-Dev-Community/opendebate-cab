defmodule CabWeb.Api.JoinRequestController do
  use CabWeb, :controller

  alias Cab.Clubs
  alias CabWeb.ClubScope

  action_fallback CabWeb.Api.FallbackController

  plug ClubScope, [source: :club, require: :authenticated] when action == :create
  plug ClubScope, [source: :join_request, require: :owner] when action == :update

  # POST /api/cab/v1/clubs/:uuid/join-requests {"answers": {field id
  # => value}, "message", "contact"} - a join request IS a pending
  # membership; the answers to the club form's member fields are
  # checked like the web form's, message and contact are optional
  def create(conn, params) do
    club = conn.assigns.club

    case Clubs.request_join(conn.assigns.current_user, club, params) do
      {:ok, membership} ->
        conn
        |> put_status(201)
        |> json(%{
          id: membership.id,
          status: membership.status,
          message: membership.message,
          contact: membership.contact,
          answers: membership.answers
        })

      {:error, {:answers, codes}} ->
        {:error, answer_details(Clubs.member_fields(club), codes)}

      error ->
        error
    end
  end

  defp answer_details(fields, codes) do
    for field <- fields, code = codes[field["id"]], into: %{} do
      {field["id"], CabWeb.FormComponents.answer_error(code, field["type"])}
    end
  end

  # PATCH /api/cab/v1/join-requests/:id {"action": "approve" | "decline"}
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
