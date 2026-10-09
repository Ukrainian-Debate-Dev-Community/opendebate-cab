defmodule CabWeb.AccountController do
  @moduledoc """
  `/account` — the signed-in profile page, opened from the sidenav
  bottom only: display name (editable), provider/avatar info, sign
  out, and claiming a guest history by pasting its personal link.
  """

  use CabWeb, :controller

  import CabWeb.UserAuth, only: [require_account: 2]

  alias Cab.{Accounts, Links}

  plug :require_account

  def show(conn, _params) do
    render_account(conn)
  end

  # POST /account {"name"} — display name only
  def update(conn, params) do
    case Accounts.update_profile(conn.assigns.current_user, params) do
      {:ok, user} ->
        conn
        |> assign(:current_user, user)
        |> put_flash(:info, "profile saved")
        |> redirect(to: ~p"/account")

      {:error, %Ecto.Changeset{}} ->
        conn
        |> put_flash(:error, "could not save the profile")
        |> render_account()
    end
  end

  # POST /account/claim {"link"} — the pasted personal link's guest
  # history moves onto this account
  def claim(conn, params) do
    case Links.find_by_pasted(params["link"]) do
      nil ->
        conn
        |> put_flash(:error, "That personal link does not exist or no longer works.")
        |> redirect(to: ~p"/account")

      link ->
        case Links.claim(link, conn.assigns.current_user) do
          {:ok, _moved} ->
            conn
            |> put_flash(:info, "#{link.user.name}'s guest history is now on your account")
            |> redirect(to: ~p"/me")

          {:error, message} ->
            conn |> put_flash(:error, message) |> redirect(to: ~p"/account")
        end
    end
  end

  defp render_account(conn) do
    user = conn.assigns.current_user

    render(conn, :show,
      identities: Accounts.list_identities(user),
      page_title: "account"
    )
  end
end
