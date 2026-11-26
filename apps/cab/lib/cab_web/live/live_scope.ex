defmodule CabWeb.LiveScope do
  @moduledoc """
  The live twin of `CabWeb.UserAuth.fetch_current_user/2` +
  `CabWeb.ClubScope`: same URLs, same ladder, same answers - 404 for
  an unknown or archived club, the /signin wall for anonymous, 403
  for a role that does not cover the tree.

      live_session :club, on_mount: [{CabWeb.LiveScope, :club}]
      live_session :owner, on_mount: [{CabWeb.LiveScope, :club}, {CabWeb.LiveScope, :owner}]
      live_session :guest_hub, on_mount: [{CabWeb.LiveScope, :guest_link}]
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
         |> assign(:nav_session, Sessions.focus_for_club(club))}
    end
  end

  # an account's own pages (My page): signed in, not a guest's link
  def on_mount(:account, _params, session, socket) do
    case session["user_id"] && Accounts.get_viewer(session["user_id"]) do
      %{guest: false} = user ->
        {:cont, assign(socket, :current_user, user)}

      %{guest: true} ->
        {:halt,
         socket
         |> put_flash(:error, gettext("Sign in with your own account first."))
         |> redirect(to: "/signin")}

      nil ->
        {:halt,
         socket |> put_flash(:error, gettext("Please sign in.")) |> redirect(to: "/signin")}
    end
  end

  # a guest's hub: the browser holds this link's identity (opening
  # /l/:code adopts it); anyone else goes through /l/:code first,
  # which adopts it or offers an account the claim
  def on_mount(:guest_link, %{"code" => code}, session, socket) do
    with %{} = link <- Cab.Links.get_active_by_code(code),
         true <- session["user_id"] == link.user_id,
         %{} = user <- Accounts.get_viewer(link.user_id) do
      {:cont, socket |> assign(:current_user, user) |> assign(:link, link)}
    else
      nil -> raise CabWeb.NotFoundError
      _other -> {:halt, redirect(socket, to: "/l/#{code}")}
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
