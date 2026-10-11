defmodule CabWeb.Api.SignupController do
  use CabWeb, :controller

  alias Cab.Sessions
  alias CabWeb.ClubScope

  action_fallback CabWeb.Api.FallbackController

  plug ClubScope, source: :session, require: :member

  # POST /api/v1/sessions/:uuid/signups {"username": optional - head
  # only, signs up any approved member}. No role: the head decides
  # who judges at allocation.
  def create(conn, %{"username" => username}) when is_binary(username) do
    with :ok <- require_owner(conn),
         {:ok, participant} <-
           Sessions.signup_for(conn.assigns.current_user, conn.assigns.session, username) do
      conn
      |> put_status(201)
      |> json(%{participant_id: participant["id"], username: username})
    end
  end

  def create(conn, _params) do
    with {:ok, participant} <- Sessions.signup(conn.assigns.current_user, conn.assigns.session) do
      conn
      |> put_status(201)
      |> json(%{participant_id: participant["id"]})
    end
  end

  # DELETE /api/v1/sessions/:uuid/signups/:participant_id - the head
  # removes anyone, a member removes their own signup
  def delete(conn, %{"participant_id" => participant_id}) do
    with {:ok, participant_id} <- parse_id(participant_id),
         :ok <-
           Sessions.remove_signup(
             conn.assigns.current_user,
             conn.assigns.session,
             participant_id
           ) do
      json(conn, %{participant_id: participant_id, status: "removed"})
    end
  end

  defp require_owner(conn) do
    if Cab.Clubs.covers?(conn.assigns.club_role, :owner), do: :ok, else: {:error, :forbidden}
  end

  defp parse_id(id) do
    case Integer.parse(id) do
      {int, ""} -> {:ok, int}
      _ -> {:error, "bad participant id"}
    end
  end
end
