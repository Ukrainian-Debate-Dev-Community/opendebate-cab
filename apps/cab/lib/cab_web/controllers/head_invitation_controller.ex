defmodule CabWeb.HeadInvitationController do
  @moduledoc """
  `/head-invitations/:token` - the link in an invitation to head a
  club. Signed in: the account becomes the head at once. Signed out (or
  on a guest's personal link): the token waits in the session while the
  person signs in on /signin, and `accept_pending/2` finishes the job
  right after the sign-in.
  """

  use CabWeb, :controller

  alias Cab.HeadInvitations

  @session_key :head_invitation

  def show(conn, %{"token" => token}) do
    case HeadInvitations.by_token(token) do
      {:ok, _invitation} ->
        user = conn.assigns.current_user

        if user && not Cab.Links.guest?(user.id) do
          finish(conn, token, user)
        else
          # a guest's personal link cannot head a club: start a real sign-in
          conn
          |> configure_session(renew: true)
          |> delete_session(:user_id)
          |> put_session(@session_key, token)
          |> redirect(to: ~p"/signin")
        end

      {:error, reason} ->
        conn
        |> put_status(410)
        |> render(:invalid, reason: reason, page_title: gettext("Invitation"))
    end
  end

  @doc """
  After a sign-in: accepts a head invitation the person opened while
  signed out. Returns the conn and where to send them, or nil when no
  invitation was waiting.
  """
  def accept_pending(conn, user) do
    case get_session(conn, @session_key) do
      nil ->
        {conn, nil}

      token ->
        conn = delete_session(conn, @session_key)

        case HeadInvitations.accept(token, user) do
          {:ok, club} ->
            {put_flash(conn, :info, became_head(club)), ~p"/c/#{club.uuid}/owner"}

          {:error, reason} ->
            {put_flash(conn, :error, refusal(reason)), ~p"/"}
        end
    end
  end

  @doc "The club waiting for this sign-in, for the sign-in page's prompt."
  def pending_club(conn) do
    case get_session(conn, @session_key) do
      nil -> nil
      token -> HeadInvitations.club_for_token(token)
    end
  end

  defp finish(conn, token, user) do
    case HeadInvitations.accept(token, user) do
      {:ok, club} ->
        conn |> put_flash(:info, became_head(club)) |> redirect(to: ~p"/c/#{club.uuid}/owner")

      {:error, reason} ->
        conn |> put_flash(:error, refusal(reason)) |> redirect(to: ~p"/")
    end
  end

  defp became_head(club), do: gettext("You are now the head of %{club}.", club: club.name)

  defp refusal(:guest),
    do: gettext("A guest's personal link cannot head a club. Sign in with GitHub or Google.")

  defp refusal(reason) when reason in [:unknown, :expired, :used, :cancelled],
    do: gettext("This invitation link no longer works. Ask the admin for a new one.")

  defp refusal(message) when is_binary(message), do: message
  defp refusal(_reason), do: gettext("Something went wrong, try again.")
end
