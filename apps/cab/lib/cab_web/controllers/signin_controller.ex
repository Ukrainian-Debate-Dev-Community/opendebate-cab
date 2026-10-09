defmodule CabWeb.SigninController do
  @moduledoc """
  P1 `/signin` — the ONLY auth entry. Every "Sign in" link and every
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

  def show(conn, _params) do
    case {conn.assigns.current_user, existing(conn)} do
      {nil, nil} ->
        render(conn, :show, existing: nil, providers: ["GitHub", "Google"], page_title: "Sign in")

      {nil, existing} ->
        render(conn, :show,
          existing: existing,
          providers: existing.providers,
          page_title: "Sign in"
        )

      _signed_in ->
        redirect(conn, to: ~p"/")
    end
  end

  # POST /signin/separate — the person wants a separate account after all
  def separate(conn, _params) do
    case get_session(conn, :pending_identity) do
      %{pending: pending} ->
        conn = delete_session(conn, :pending_identity)

        case Accounts.create_pending(pending) do
          {:ok, user} -> CabWeb.AuthController.signed_in(conn, user)
          {:error, _} -> conn |> put_flash(:error, "Sign-in failed.") |> redirect(to: ~p"/signin")
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
end
