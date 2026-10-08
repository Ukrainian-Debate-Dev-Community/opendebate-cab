defmodule CabWeb.GuestLinkController do
  @moduledoc """
  The guest's permanent personal link: `/l/:code` is AUTH ONLY — the
  code resolves on every request (revoked or unknown is a plain 404),
  the browser session adopts the guest identity ("anyone with the
  link acts as you") and the guest lands on P6, their session's page,
  where cancel-registration and the judge ballot work through that
  identity. The identity holds no membership, so the member/owner
  trees and every other club stay closed to it.
  """

  use CabWeb, :controller

  alias Cab.Links

  # GET /l/:code — adopt the guest identity, land on P6. A signed-in
  # ACCOUNT is never replaced: opening someone's link (an owner
  # checking it, a shared device) must not log anyone out.
  def show(conn, %{"code" => code}) do
    case Links.get_active_by_code(code) do
      nil ->
        conn |> send_resp(404, "not found") |> halt()

      link ->
        session_page = ~p"/c/#{link.session.club.uuid}/s/#{link.session.uuid}"
        current = get_session(conn, :user_id)

        cond do
          current == link.user_id ->
            redirect(conn, to: session_page)

          is_nil(current) or Links.guest?(current) ->
            conn
            |> configure_session(renew: true)
            |> put_session(:user_id, link.user_id)
            |> put_flash(
              :info,
              "You are here through your personal link, #{link.user.name}. " <>
                "Keep it — anyone with it acts as you."
            )
            |> redirect(to: session_page)

          true ->
            conn
            |> put_flash(
              :error,
              "You are signed in with your own account — this personal link " <>
                "belongs to #{link.user.name}. Sign out first to use it."
            )
            |> redirect(to: session_page)
        end
    end
  end
end
