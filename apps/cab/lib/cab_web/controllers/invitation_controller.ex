defmodule CabWeb.InvitationController do
  @moduledoc """
  The invited user answers from their cabinet: accept makes the
  session place theirs (any time, the session may be over), decline
  gives it up and removes their name.
  """
  use CabWeb, :controller

  import CabWeb.UserAuth, only: [require_authenticated_user: 2]

  alias Cab.Invitations

  plug :require_authenticated_user

  # POST /invitations/:id/accept
  def accept(conn, %{"id" => id}) do
    with_invitation(conn, id, fn invitation ->
      case Invitations.accept(invitation, conn.assigns.current_user) do
        {:ok, _} ->
          session = invitation.session

          conn
          |> put_flash(
            :info,
            "you are in #{session.name || "the session"} at #{session.club.name}"
          )
          |> redirect(to: ~p"/c/#{session.club.uuid}/s/#{session.uuid}")

        {:error, message} ->
          conn |> put_flash(:error, message) |> redirect(to: ~p"/")
      end
    end)
  end

  # POST /invitations/:id/decline
  def decline(conn, %{"id" => id}) do
    with_invitation(conn, id, fn invitation ->
      case Invitations.decline(invitation) do
        :ok ->
          conn
          |> put_flash(:info, "invitation declined, your name is removed")
          |> redirect(to: ~p"/")

        {:error, message} ->
          conn |> put_flash(:error, message) |> redirect(to: ~p"/")
      end
    end)
  end

  defp with_invitation(conn, id, fun) do
    with {id, ""} <- Integer.parse(id),
         invitation when not is_nil(invitation) <-
           Invitations.get_for_user(id, conn.assigns.current_user) do
      fun.(invitation)
    else
      _ -> CabWeb.ErrorHTML.respond(conn, 404)
    end
  end
end
