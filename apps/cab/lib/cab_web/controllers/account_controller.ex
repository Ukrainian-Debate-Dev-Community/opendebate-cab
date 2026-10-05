defmodule CabWeb.AccountController do
  @moduledoc """
  `/account` — the signed-in profile page, opened from the sidenav
  bottom only: display name (editable), provider/avatar info, sign
  out. Claim codes (guest history) land here later.
  """

  use CabWeb, :controller

  import CabWeb.UserAuth, only: [require_authenticated_user: 2]

  alias Cab.Accounts

  plug :require_authenticated_user

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

  defp render_account(conn) do
    user = conn.assigns.current_user

    render(conn, :show,
      identities: Accounts.list_identities(user),
      page_title: "account"
    )
  end
end
