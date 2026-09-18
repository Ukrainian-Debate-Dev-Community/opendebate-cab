defmodule CabWeb.LiveAuth do
  @moduledoc """
  on_mount hook for the cab LiveViews: loads the session user (if any)
  and provides the `actor/1` helper resolving a gateway user to their
  engine user id, provisioning lazily when needed.
  """

  import Phoenix.Component, only: [assign: 2]

  alias Cab.Accounts

  # The fixed dev cast: one persona per role. Switching between these
  # three shows every perspective the app has — no user zoo.
  @dev_cast ~w(organiser judge speaker)

  def dev_cast, do: @dev_cast

  def on_mount(:current_user, _params, session, socket) do
    user = session["user_id"] && Accounts.get_user(session["user_id"])
    dev_routes = Application.get_env(:cab, :dev_routes, false)

    {:cont,
     assign(socket,
       current_user: user,
       error: nil,
       dev_routes: dev_routes,
       dev_users: if(dev_routes, do: @dev_cast, else: [])
     )}
  end

  @doc """
  Does `user` hold organiser-level privileges for the engine event
  (admin / org owner / organiser)? The engine is the authority
  (`GET /events/:id/access`); this only decides what UI to render —
  every action is still authorised server-side by the engine.
  """
  def privileged?(user, event_id) do
    with {:ok, actor} <- actor(user),
         {:ok, %{"isPrivileged" => privileged}} <- Cab.EngineApi.event_access(actor, event_id) do
      privileged
    else
      _ -> false
    end
  end

  @doc """
  Resolves the acting engine user id for `user`.
  """
  def actor(nil),
    do: {:error, "please sign in first (dev user switcher in the top bar, or GitHub)"}

  def actor(user) do
    case Accounts.ensure_node_user(user) do
      %{node_user_id: nil} ->
        {:error, "could not provision an engine user — is the engine running?"}

      %{node_user_id: node_user_id} ->
        {:ok, node_user_id}
    end
  end
end
