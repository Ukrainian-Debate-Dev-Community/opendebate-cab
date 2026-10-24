defmodule CabWeb.SigninController do
  @moduledoc """
  P1 `/signin` - the ONLY auth entry. Every "Sign in" link and every
  auth-required redirect lands here; `/auth/:provider` stays as the
  provider hop this page's buttons point at. When a new sign-in's
  verified address already has an account, the page offers that
  account's sign-in methods (which add the new one to it) or a
  separate account.
  """

  use CabWeb, :controller

  alias Cab.Accounts

  def show(conn, %{"start_over" => _}) do
    conn |> delete_session(:pending_identity) |> redirect(to: ~p"/signin")
  end

  def show(conn, params) do
    conn = remember_return(conn, params["return_to"])

    case {conn.assigns.current_user, existing(conn)} do
      {nil, nil} ->
        render(conn, :show,
          existing: nil,
          providers: ["GitHub", "Google"],
          head_club: CabWeb.HeadInvitationController.pending_club(conn),
          page_title: gettext("Sign in")
        )

      {nil, existing} ->
        render(conn, :show,
          existing: existing,
          providers: existing.providers,
          head_club: CabWeb.HeadInvitationController.pending_club(conn),
          page_title: gettext("Sign in")
        )

      # already signed in: straight back to whoever sent them here
      _signed_in ->
        case CabWeb.ReturnTo.accept(params["return_to"]) do
          nil -> redirect(conn, to: ~p"/")
          back -> conn |> delete_session(:return_to) |> CabWeb.ReturnTo.redirect_to(back)
        end
    end
  end

  # POST /signin/separate - the person wants a separate account after all
  def separate(conn, _params) do
    case get_session(conn, :pending_identity) do
      %{pending: pending} ->
        conn = delete_session(conn, :pending_identity)

        case Accounts.create_pending(pending) do
          {:ok, user} ->
            CabWeb.AuthController.signed_in(conn, user)

          {:error, _} ->
            conn |> put_flash(:error, gettext("Sign-in failed.")) |> redirect(to: ~p"/signin")
        end

      _ ->
        redirect(conn, to: ~p"/signin")
    end
  end

  defp existing(conn) do
    with %{pending: pending, user_id: user_id} <- get_session(conn, :pending_identity),
         %Accounts.User{} = user <- Accounts.get_user(user_id) do
      %{
        email: pending.attrs.email,
        adding: provider_name(pending.provider),
        providers: user |> Accounts.list_identities() |> Enum.map(&provider_name(&1.provider))
      }
    else
      _ -> nil
    end
  end

  defp provider_name("github"), do: "GitHub"
  defp provider_name("google"), do: "Google"
  defp provider_name(other), do: other

  # a page that sent the visitor here ("Have an account? Sign in" on
  # a club page, a sibling site's editors) gets them back after signing
  # in: local paths and the deployment's return hosts (CabWeb.ReturnTo)
  defp remember_return(conn, value) do
    case CabWeb.ReturnTo.accept(value) do
      nil -> conn
      back -> put_session(conn, :return_to, back)
    end
  end
end
