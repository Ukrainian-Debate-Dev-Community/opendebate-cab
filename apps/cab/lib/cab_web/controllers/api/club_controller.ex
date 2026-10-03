defmodule CabWeb.Api.ClubController do
  use CabWeb, :controller

  alias Cab.Clubs
  alias CabWeb.ClubScope

  action_fallback CabWeb.Api.FallbackController

  plug ClubScope, [source: :club, require: :public] when action == :show
  plug ClubScope, [source: :club, require: :member] when action == :members

  # GET /api/v1/clubs/:uuid — public profile + history (with winners)
  def show(conn, _params) do
    club = conn.assigns.club

    with {:ok, history} <- Clubs.club_history(club) do
      json(conn, %{
        uuid: club.uuid,
        name: club.name,
        city: club.city,
        history:
          Enum.map(history, fn event ->
            %{
              id: event["id"],
              name: event["name"],
              status: event["status"],
              winner: event["winner"]
            }
          end)
      })
    end
  end

  # GET /api/v1/clubs/:uuid/members — roster, members only
  def members(conn, _params) do
    members =
      Enum.map(Clubs.list_members(conn.assigns.club), fn membership ->
        %{
          username: membership.user.username,
          name: membership.user.name,
          role: membership.role
        }
      end)

    json(conn, %{members: members})
  end
end
