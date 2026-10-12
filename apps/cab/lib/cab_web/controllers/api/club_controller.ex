defmodule CabWeb.Api.ClubController do
  use CabWeb, :controller

  alias Cab.Clubs
  alias CabWeb.ClubScope

  action_fallback CabWeb.Api.FallbackController

  plug ClubScope, [source: :club, require: :public] when action == :show
  plug ClubScope, [source: :club, require: :roster] when action == :members
  plug ClubScope, [source: :club, require: :owner] when action in [:update, :remove_member]

  # GET /api/v1/clubs - every club that is not archived, public profile
  # only: what other services read to list clubs (members-only clubs
  # too, since only their standings and roster are private)
  def index(conn, _params) do
    json(conn, %{clubs: Enum.map(Clubs.list_clubs(), &profile/1)})
  end

  # GET /api/v1/clubs/:uuid - public profile + history (with winners)
  def show(conn, _params) do
    club = conn.assigns.club

    with {:ok, history} <- Clubs.club_history(club) do
      json(
        conn,
        Map.put(
          profile(club),
          :history,
          Enum.map(history, fn row ->
            %{session_uuid: row.session_uuid, name: row.name, winner: row.winner}
          end)
        )
      )
    end
  end

  # PATCH /api/v1/clubs/:uuid {"name", "city", "meeting_info",
  # "description", "contacts", "is_private", "formats", "languages",
  # "audiences", "format_other", "language_other"} - head edits the
  # profile; fields left out stay
  def update(conn, params) do
    attrs =
      Map.take(
        params,
        ~w(name city meeting_info description contacts is_private formats languages audiences format_other language_other)
      )

    with {:ok, club} <- Clubs.update_club(conn.assigns.club, attrs) do
      json(conn, profile(club))
    end
  end

  defp profile(club) do
    %{
      uuid: club.uuid,
      name: club.name,
      city: club.city,
      meeting_info: club.meeting_info,
      description: club.description,
      contacts: club.contacts,
      formats: club.formats,
      format_other: club.format_other,
      languages: club.languages,
      language_other: club.language_other,
      audiences: club.audiences
    }
  end

  # GET /api/v1/clubs/:uuid/members - roster, members only
  def members(conn, _params) do
    members =
      Enum.map(Clubs.list_members(conn.assigns.club), fn membership ->
        %{
          user_id: membership.user.id,
          username: membership.user.username,
          name: membership.user.name,
          role: membership.role
        }
      end)

    json(conn, %{members: members})
  end

  # DELETE /api/v1/clubs/:uuid/members/:user_id - head removes a
  # member (gateway membership row only; the engine stays untouched)
  def remove_member(conn, %{"user_id" => user_id}) do
    with {:ok, user_id} <- parse_id(user_id),
         {:ok, _membership} <- Clubs.remove_member(conn.assigns.club, user_id) do
      json(conn, %{user_id: user_id, status: "removed"})
    end
  end

  defp parse_id(id) do
    case Integer.parse(id) do
      {int, ""} -> {:ok, int}
      _ -> {:error, "bad user id"}
    end
  end
end
