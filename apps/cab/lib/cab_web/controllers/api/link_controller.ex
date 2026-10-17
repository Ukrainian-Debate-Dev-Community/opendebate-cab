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

  # GET /api/cab/v1/sessions/:uuid/responses - head only: the guests'
  # answers to the club's registration form, the rows of the Responses
  # page. `columns` are the labels in form order (then labels only old
  # answers carry); each guest's `answers` map a label to the value.
  def responses(conn, _params) do
    %{columns: columns, rows: rows} = Links.responses(conn.assigns.session)

    json(conn, %{
      uuid: conn.assigns.session.uuid,
      columns: Enum.map(columns, & &1["label"]),
      responses:
        for row <- rows do
          %{
            name: row.name,
            registered_at: row.registered_at,
            answers: Map.new(row.answers, fn {label, answer} -> {label, answer["value"]} end)
          }
        end
    })
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
