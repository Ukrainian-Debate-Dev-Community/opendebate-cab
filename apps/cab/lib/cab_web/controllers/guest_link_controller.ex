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

  # GET /l/:code — adopt the guest identity, land on P6
  def show(conn, %{"code" => code}) do
    case Links.get_active_by_code(code) do
      nil ->
        conn |> send_resp(404, "not found") |> halt()

      link ->
        conn
        |> adopt_identity(link)
        |> put_flash(
          :info,
          "You are here through your personal link, #{link.user.name}. " <>
            "Keep it — anyone with it acts as you."
        )
        |> redirect(to: ~p"/c/#{link.session.club.uuid}/s/#{link.session.uuid}")
    end
  end

  # the browser session follows the link's identity: whoever holds
  # the link acts as this guest — and ONLY as a guest (no membership
  # anywhere, so no member/owner tree ever opens from it)
  defp adopt_identity(conn, link) do
    if get_session(conn, :user_id) == link.user_id do
      conn
    else
      conn
      |> configure_session(renew: true)
      |> put_session(:user_id, link.user_id)
    end
  end
end
