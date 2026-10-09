defmodule CabWeb.GuestLinkController do
  @moduledoc """
  The guest's permanent personal link: `/l/:code` is AUTH ONLY — the
  code resolves on every request (revoked or unknown is a plain 404),
  the browser session adopts the guest identity ("anyone with the
  link acts as you") and the guest lands on P6, their session's page,
  where cancel-registration and the judge ballot work through that
  identity. The identity holds no membership, so the member/owner
  trees and every other club stay closed to it. Opened while signed in
  with a real account, the link offers to claim the guest's history.
  """

  use CabWeb, :controller

  alias Cab.Links

  # GET /l/:code — adopt the guest identity, land on P6. A signed-in
  # ACCOUNT is never replaced: opening someone's link (an owner
  # checking it, a shared device) must not log anyone out.
  def show(conn, %{"code" => code}) do
    case Links.get_active_by_code(code) do
      nil ->
        conn |> CabWeb.ErrorHTML.respond(404)

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
            render(conn, :claim,
              link: link,
              club: link.session.club,
              session: link.session,
              page_title: "Your guest history"
            )
        end
    end
  end

  # POST /l/:code/claim — a signed-in account takes over the guest's
  # history; the guest account and this link are gone afterwards
  def claim(conn, %{"code" => code}) do
    with %Cab.Accounts.User{} = account <- conn.assigns[:current_user],
         link when not is_nil(link) <- Links.get_active_by_code(code) do
      case Links.claim(link, account) do
        {:ok, _moved} ->
          conn
          |> put_flash(:info, "#{link.user.name}'s guest history is now on your account.")
          |> redirect(to: ~p"/me")

        {:error, message} ->
          conn
          |> put_flash(:error, message)
          |> redirect(to: ~p"/c/#{link.session.club.uuid}/s/#{link.session.uuid}")
      end
    else
      nil ->
        if conn.assigns[:current_user],
          do: CabWeb.ErrorHTML.respond(conn, 404),
          else: conn |> put_flash(:error, "Please sign in.") |> redirect(to: ~p"/signin")
    end
  end
end
