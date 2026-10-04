defmodule CabWeb.ClubScope do
  @moduledoc """
  The role-scoped URL tree plug chain: resolve the club behind the
  request, derive the current user's ACTUAL role in it, and assert
  the role covers the requested tree — else 403.

  Used by both the JSON controllers and the HTML role trees; the
  engine enforces again on its side, but the gateway never skips its
  own check.

      plug CabWeb.ClubScope, source: :club, require: :owner

  Sources (how the club is found):
    * `:club` — `club_uuid`/`uuid` path param is a club uuid
    * `:session` — `session_uuid`/`uuid` path param is a session uuid
      (assigns `:session` too)
    * `:join_request` — `id` path param is a membership id
      (assigns `:join_request` too)
    * `:link` — `id` path param is a guest-link id
      (assigns `:link` too; link identity itself NEVER satisfies a
      tree — guests hold no membership, so their role stays :public)
    * `:room_session` — `session_uuid` body param names the session
      the room belongs to (assigns `:session` too)

  Requirements (what the tree demands):
    * `:public` — anyone, resolution only
    * `:authenticated` — any signed-in user
    * `:member` — approved membership (head included)
    * `:owner` — head membership
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2, get_format: 1]

  alias Cab.{Clubs, Sessions}

  def init(opts) do
    %{
      source: Keyword.fetch!(opts, :source),
      require: Keyword.get(opts, :require, :public)
    }
  end

  def call(conn, %{source: source, require: required}) do
    case resolve(conn, source) do
      {:ok, assigns} ->
        club = Keyword.fetch!(assigns, :club)
        role = Clubs.role_for(club, conn.assigns[:current_user])

        Enum.reduce(assigns, conn, fn {key, value}, conn -> assign(conn, key, value) end)
        |> assign(:club_role, role)
        |> enforce(role, required)

      :error ->
        halt_with(conn, 404, "not found")
    end
  end

  # ---------------------------------------------------------------
  # Resolution
  # ---------------------------------------------------------------

  defp resolve(conn, :club) do
    case Clubs.get_by_uuid(conn.path_params["club_uuid"] || conn.path_params["uuid"] || "") do
      nil -> :error
      club -> {:ok, [club: club]}
    end
  end

  defp resolve(conn, :session) do
    resolve_session(conn.path_params["session_uuid"] || conn.path_params["uuid"] || "")
  end

  defp resolve(conn, :room_session) do
    case conn.params["session_uuid"] do
      uuid when is_binary(uuid) -> resolve_session(uuid)
      _ -> :error
    end
  end

  defp resolve(conn, :join_request) do
    with id when is_binary(id) <- conn.path_params["id"],
         {id, ""} <- Integer.parse(id),
         membership when not is_nil(membership) <- Clubs.get_membership(id) do
      {:ok, [club: membership.club, join_request: membership]}
    else
      _ -> :error
    end
  end

  defp resolve(conn, :link) do
    with id when is_binary(id) <- conn.path_params["id"],
         {id, ""} <- Integer.parse(id),
         link when not is_nil(link) <- Cab.Links.get_link(id) do
      {:ok, [club: link.club, link: link]}
    else
      _ -> :error
    end
  end

  defp resolve_session(uuid) do
    case Sessions.get_by_uuid(uuid) do
      nil -> :error
      session -> {:ok, [club: session.club, session: session]}
    end
  end

  # ---------------------------------------------------------------
  # Enforcement
  # ---------------------------------------------------------------

  defp enforce(conn, _role, :public), do: conn

  defp enforce(conn, _role, :authenticated) do
    if conn.assigns[:current_user], do: conn, else: unauthenticated(conn)
  end

  defp enforce(conn, role, required) when required in [:member, :owner] do
    cond do
      covers?(role, required) -> conn
      conn.assigns[:current_user] == nil -> unauthenticated(conn)
      true -> halt_with(conn, 403, "forbidden")
    end
  end

  defp covers?(:owner, _required), do: true
  defp covers?(:member, :member), do: true
  defp covers?(_role, _required), do: false

  defp unauthenticated(conn) do
    case get_format(conn) do
      "json" -> halt_with(conn, 401, "unauthenticated")
      _ -> halt_with(conn, 403, "forbidden")
    end
  end

  defp halt_with(conn, status, message) do
    conn =
      case get_format(conn) do
        "json" -> conn |> put_status(status) |> json(%{error: message})
        _ -> send_resp(conn, status, message)
      end

    halt(conn)
  end
end
