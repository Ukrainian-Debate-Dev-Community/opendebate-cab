defmodule CabWeb.Api.PeopleController do
  @moduledoc """
  The head's add field over the API: search what a typed value
  matches, and invite a registered non-member by exact username or
  email. Members are signed up through the signups endpoint, guests
  through the links endpoint.
  """
  use CabWeb, :controller

  alias Cab.{Invitations, Sessions}
  alias CabWeb.ClubScope

  action_fallback CabWeb.Api.FallbackController

  plug ClubScope, source: :session, require: :owner

  # GET /api/v1/sessions/:uuid/people?q= — names and usernames only;
  # emails never leave the server
  def search(conn, params) do
    with {:ok, state} <- Sessions.state(conn.assigns.session) do
      hits =
        Invitations.search(conn.assigns.club, conn.assigns.session, state.signups, params["q"])

      json(conn, %{
        members: Enum.map(hits.members, &person/1),
        users: Enum.map(hits.users, &person/1),
        guest: hits.guest
      })
    end
  end

  # POST /api/v1/sessions/:uuid/invitations {"user": exact username or email}
  def invite(conn, params) do
    session = conn.assigns.session

    with {:ok, state} <- Sessions.state(session),
         {:user, user} <-
           Invitations.resolve(conn.assigns.club, session, state.signups, params["user"]) ||
             {:error, "no registered user has that exact username or email"},
         {:ok, invitation} <- Invitations.invite(conn.assigns.current_user, session, user) do
      conn
      |> put_status(201)
      |> json(%{participant_id: invitation.engine_participant_id, username: user.username})
    else
      {:member, _user} -> {:error, "that is a club member — sign them up instead"}
      {:guest, _name} -> {:error, "no registered user has that exact username or email"}
      error -> error
    end
  end

  defp person(user), do: %{username: user.username, name: user.name}
end
