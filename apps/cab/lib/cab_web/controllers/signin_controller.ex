defmodule CabWeb.SigninController do
  @moduledoc """
  P1 `/signin` — the ONLY auth entry. Every "Sign in" link and every
  auth-required redirect lands here; `/auth/:provider` stays as the
  provider hop this page's buttons point at.
  """

  use CabWeb, :controller

  def show(conn, _params) do
    case conn.assigns.current_user do
      nil -> render(conn, :show, page_title: "Sign in")
      _user -> redirect(conn, to: ~p"/")
    end
  end
end
