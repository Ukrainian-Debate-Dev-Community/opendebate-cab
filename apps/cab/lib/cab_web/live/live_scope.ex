defmodule CabWeb.LiveScope do
  @moduledoc """
  The live twin of `CabWeb.UserAuth.fetch_current_user/2` +
  `CabWeb.ClubScope`: same URLs, same ladder, same answers — 404 for
  an unknown or archived club, the /signin wall for anonymous, 403
  for a role that does not cover the tree.

      live_session :club, on_mount: [{CabWeb.LiveScope, :club}]
      live_session :owner, on_mount: [{CabWeb.LiveScope, :club}, {CabWeb.LiveScope, :owner}]
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, redirect: 2]
  use Gettext, backend: CabWeb.Gettext

  alias Cab.{Accounts, Clubs, Sessions}

  def on_mount(:club, params, session, socket) do
    user = session["user_id"] && Accounts.get_viewer(session["user_id"])

    case Clubs.get_by_uuid(params["club_uuid"] || "") do
      nil ->
        raise CabWeb.NotFoundError

      club ->
        if club.archived_at != nil and not (user != nil and user.is_admin) do
          raise CabWeb.NotFoundError
        end

        {:cont,
         socket
         |> assign(:current_user, user)
         |> assign(:club, club)
         |> assign(:club_role, Clubs.role_for(club, user))
         |> assign(:nav_session, List.first(Sessions.list_for_club(club)))}
    end
  end

  def on_mount(required, _params, _session, socket) when required in [:member, :owner] do
    cond do
      Clubs.covers?(socket.assigns.club_role, required) ->
        {:cont, socket}

      socket.assigns.current_user == nil ->
        {:halt,
         socket |> put_flash(:error, gettext("Please sign in.")) |> redirect(to: "/signin")}

      true ->
        raise CabWeb.ForbiddenError
    end
  end
end
