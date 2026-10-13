defmodule CabWeb.Api.LinkController do
  use CabWeb, :controller

  alias Cab.{Links, Sessions}
  alias CabWeb.ClubScope

  action_fallback CabWeb.Api.FallbackController

  plug ClubScope, source: :session, require: :owner

  # GET /api/cab/v1/sessions/:uuid/links - head only: the session's
  # active guest links with each guest's name, signed-up role and
  # answers to the club's registration form
  def index(conn, _params) do
    session = conn.assigns.session

    with {:ok, state} <- Sessions.state(session) do
      links =
        for link <- Links.list_for_session(session) do
          link_json(link) |> Map.put(:role, Links.role_in(link, state.signups))
        end

      json(conn, %{links: links})
    end
  end

  # POST /api/cab/v1/sessions/:uuid/links {"name"} - the head
  # issues a guest registration + personal link by hand
  def create(conn, params) do
    with {:ok, link} <-
           Links.register_guest(conn.assigns.session, params["name"]) do
      conn |> put_status(201) |> json(link_json(link))
    end
  end

  defp link_json(link) do
    %{
      id: link.id,
      name: link.user.name,
      username: link.user.username,
      code: link.code,
      url: url(~p"/l/#{link.code}"),
      # the guest's answers to the club's registration form (head only,
      # as this whole controller is)
      answers: Enum.map(link.answers || [], &Map.take(&1, ~w(id label type value)))
    }
  end
end
