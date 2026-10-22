defmodule CabWeb.RegistrationController do
  @moduledoc """
  `/r/:session_uuid`, the registration URL heads shared before
  registration moved onto the club page: it leads to the club page's
  registration section, which says whether the session still takes
  sign-ups.
  """

  use CabWeb, :controller

  alias Cab.Sessions
  alias Cab.Sessions.Session

  def show(conn, %{"session_uuid" => session_uuid}) do
    case Sessions.get_by_uuid(session_uuid) do
      %Session{} = session ->
        redirect(conn, to: CabWeb.ClubPublicController.register_path(session))

      nil ->
        CabWeb.ErrorHTML.respond(conn, 404)
    end
  end
end
