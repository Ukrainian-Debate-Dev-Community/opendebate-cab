defmodule CabWeb.GuestLinkController do
  @moduledoc """
  The guest's permanent personal link (M6): everything under
  `/l/:code` authenticates by the code alone — the plug resolves it
  on EVERY request (revoked or unknown is a plain 404) and pins the
  guest's identity and scope to that one club+session. Opening the
  page also signs the browser session in as the guest ("anyone with
  the link acts as you"), but that identity holds no membership, so
  the member/owner trees and every other club stay closed to it.
  """

  use CabWeb, :controller

  alias Cab.Accounts.User
  alias Cab.{Links, Sessions}
  alias CabWeb.BallotForm

  plug :resolve_link

  # GET /l/:code — the guest view of their session: registration,
  # cancel while :signup, rooms when running, the chaired ballot
  def show(conn, _params) do
    session = conn.assigns.session

    case Sessions.state(session) do
      {:ok, state} ->
        conn
        |> adopt_identity()
        |> render(:show,
          state: state,
          my_signup: my_signup(state, conn.assigns.current_user),
          my_ballot_room: my_ballot_room(state, conn.assigns.current_user),
          personal_url: url(~p"/l/#{conn.assigns.link.code}"),
          page_title: "#{conn.assigns.club.name} · my session"
        )

      {:error, message} ->
        conn
        |> put_flash(:error, error_message(message))
        |> render(:show,
          state: nil,
          my_signup: nil,
          my_ballot_room: nil,
          personal_url: url(~p"/l/#{conn.assigns.link.code}"),
          page_title: "#{conn.assigns.club.name} · my session"
        )
    end
  end

  # POST /l/:code/signups/:participant_id/remove — the guest cancels
  # their OWN registration while :signup (the context authorises:
  # only the signup carrying their engine user id may go)
  def cancel_signup(conn, %{"participant_id" => participant_id}) do
    with {pid, ""} <- Integer.parse(participant_id),
         :ok <- Sessions.remove_signup(conn.assigns.current_user, conn.assigns.session, pid) do
      conn
      |> put_flash(:info, "registration cancelled")
      |> redirect(to: ~p"/l/#{conn.assigns.link.code}")
    else
      {:error, :forbidden} ->
        conn |> send_resp(403, "forbidden") |> halt()

      {:error, :conflict, message} ->
        bounce(conn, message)

      {:error, message} ->
        bounce(conn, error_message(message))

      _ ->
        conn |> send_resp(404, "not found") |> halt()
    end
  end

  # GET /l/:code/rooms/:id/ballot — ONLY the room's chair (the guest
  # judge); rooms outside the scoped session do not exist here (404)
  def ballot(conn, %{"id" => id}) do
    with_chaired_room(conn, id, fn conn, room ->
      render_ballot(conn, room, nil, nil)
    end)
  end

  # POST /l/:code/rooms/:id/ballot — redirect + flash, amber re-render
  def submit_ballot(conn, %{"id" => id} = params) do
    with_chaired_room(conn, id, fn conn, room ->
      scores = BallotForm.scores_from_params(params["ballot"])

      case Sessions.submit_ballot(conn.assigns.current_user, conn.assigns.session, room["id"], scores) do
        :ok ->
          conn
          |> put_flash(:info, "ballot submitted — the room is confirmed")
          |> redirect(to: ~p"/l/#{conn.assigns.link.code}")

        {:error, :forbidden} ->
          conn |> send_resp(403, "forbidden") |> halt()

        {:error, %{scores: message}} ->
          conn |> put_status(422) |> render_ballot(room, params["ballot"], message)

        {:error, message} ->
          conn |> put_status(422) |> render_ballot(room, params["ballot"], error_message(message))
      end
    end)
  end

  defp render_ballot(conn, room, ballot_params, error) do
    render(conn, :ballot,
      room: room,
      teams: BallotForm.teams(room, ballot_params),
      error: error,
      page_title: "ballot · R#{room["id"]}"
    )
  end

  # ---------------------------------------------------------------
  # Link resolution: the code is the credential and the scope
  # ---------------------------------------------------------------

  defp resolve_link(conn, _opts) do
    case Links.get_active_by_code(conn.path_params["code"]) do
      nil ->
        conn |> send_resp(404, "not found") |> halt()

      link ->
        conn
        |> assign(:link, link)
        |> assign(:current_user, link.user)
        |> assign(:session, link.session)
        |> assign(:club, link.session.club)
    end
  end

  # the browser session follows the link's identity: whoever holds
  # the link acts as this guest — and ONLY as a guest (no membership
  # anywhere, so no member/owner tree ever opens from it)
  defp adopt_identity(conn) do
    if get_session(conn, :user_id) == conn.assigns.link.user_id do
      conn
    else
      conn
      |> configure_session(renew: true)
      |> put_session(:user_id, conn.assigns.link.user_id)
    end
  end

  # resolves the room INSIDE the scoped session and gates it on the
  # guest chairing it — no owner fall-through for link identities
  defp with_chaired_room(conn, id, fun) do
    with {room_id, ""} <- Integer.parse(id),
         {:ok, state} <- Sessions.state(conn.assigns.session),
         %{} = room <- Enum.find(state.rooms, &(&1["id"] == room_id)) do
      if Sessions.room_chair?(room, conn.assigns.current_user) do
        fun.(conn, room)
      else
        conn |> send_resp(403, "forbidden") |> halt()
      end
    else
      _ -> conn |> send_resp(404, "not found") |> halt()
    end
  end

  defp my_signup(%{signups: signups}, %User{node_user_id: node_user_id})
       when is_integer(node_user_id) do
    Enum.find(signups, &(&1["user_id"] == node_user_id))
  end

  defp my_signup(_state, _user), do: nil

  defp my_ballot_room(%{stage: :running, rooms: rooms}, user) do
    Enum.find(rooms, fn room ->
      room["status"] in ["pending", "judging"] and Sessions.room_chair?(room, user)
    end)
  end

  defp my_ballot_room(_state, _user), do: nil

  defp bounce(conn, message) do
    conn
    |> put_flash(:error, message)
    |> redirect(to: ~p"/l/#{conn.assigns.link.code}")
  end

  defp error_message(message) when is_binary(message), do: message
  defp error_message(_other), do: "the session is unavailable right now"
end
