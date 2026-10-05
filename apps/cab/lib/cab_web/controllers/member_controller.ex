defmodule CabWeb.MemberController do
  use CabWeb, :controller

  alias Cab.{Clubs, Sessions}
  alias Cab.Sessions.Session

  plug CabWeb.ClubScope, [source: :club, require: :member] when action != :legacy_home

  # GET /c/:club_uuid/member — the M7 "my club page" is gone; the
  # old URL lands on the club page
  def legacy_home(conn, %{"club_uuid" => club_uuid}) do
    redirect(conn, to: ~p"/c/#{club_uuid}")
  end

  # GET /c/:club_uuid/member/sessions — the archive: previous
  # (finished) sessions only; the live one lives under Rooms
  def sessions(conn, _params) do
    club = conn.assigns.club

    render(conn, :sessions,
      archive: Sessions.archive(club),
      page_title: "#{club.name} · sessions"
    )
  end

  # GET /c/:club_uuid/member/members — the roster (the owner's view
  # with requests and revoke lives in the owner tree)
  def members(conn, _params) do
    club = conn.assigns.club

    render(conn, :members,
      members: Clubs.list_members(club),
      page_title: "#{club.name} · members"
    )
  end

  # GET /c/:club_uuid/member/sessions/:session_uuid/register — the ONE
  # registration entry: a form with role pills (Speaker | Judge)
  def register(conn, %{"session_uuid" => session_uuid}) do
    club = conn.assigns.club

    with %Session{} = session <- Sessions.get_for_club(club, session_uuid),
         {:ok, state} <- Sessions.state(%{session | club: club}) do
      case state.stage do
        :signup ->
          render(conn, :register, session: session, page_title: "#{club.name} · register")

        _stage ->
          conn
          |> put_flash(:error, "sign-ups are closed for this session")
          |> redirect(to: ~p"/c/#{club.uuid}/s/#{session.uuid}")
      end
    else
      nil ->
        conn |> send_resp(404, "not found") |> halt()

      {:error, message} ->
        conn
        |> put_flash(:error, error_message(message))
        |> redirect(to: ~p"/c/#{club.uuid}")
    end
  end

  # POST /c/:club_uuid/member/sessions/:session_uuid/signups/:participant_id/remove
  # — the member cancels their own registration (the head removes
  # anyone from the owner tree; the context authorises)
  def cancel_signup(conn, %{"session_uuid" => session_uuid, "participant_id" => participant_id}) do
    club = conn.assigns.club

    with %Session{} = session <- Sessions.get_for_club(club, session_uuid),
         {pid, ""} <- Integer.parse(participant_id),
         :ok <- Sessions.remove_signup(conn.assigns.current_user, session, pid) do
      conn
      |> put_flash(:info, "registration cancelled")
      |> redirect(to: ~p"/c/#{club.uuid}/s/#{session.uuid}")
    else
      nil ->
        conn |> send_resp(404, "not found") |> halt()

      {:error, :forbidden} ->
        conn |> send_resp(403, "forbidden") |> halt()

      {:error, message} ->
        conn
        |> put_flash(:error, error_message(message))
        |> redirect(to: ~p"/c/#{club.uuid}/s/#{session_uuid}")

      _ ->
        conn |> send_resp(404, "not found") |> halt()
    end
  end

  # POST /c/:club_uuid/member/sessions/:session_uuid/signups
  def signup(conn, %{"session_uuid" => session_uuid} = params) do
    club = conn.assigns.club
    kind = params["as"]

    with %Session{} = session <- Sessions.get_for_club(club, session_uuid),
         true <- kind in ["speak", "judge"],
         {:ok, _participant} <- Sessions.signup(conn.assigns.current_user, session, kind) do
      conn
      |> put_flash(:info, "registered to #{kind}")
      |> redirect(to: ~p"/c/#{club.uuid}/s/#{session.uuid}")
    else
      nil ->
        conn |> send_resp(404, "not found") |> halt()

      false ->
        conn
        |> put_flash(:error, ~s(sign up "as" must be "speak" or "judge"))
        |> redirect(to: ~p"/c/#{club.uuid}/s/#{session_uuid}")

      {:error, :conflict, message} ->
        conn
        |> put_flash(:error, message)
        |> redirect(to: ~p"/c/#{club.uuid}/s/#{session_uuid}")

      {:error, message} ->
        conn
        |> put_flash(:error, error_message(message))
        |> redirect(to: ~p"/c/#{club.uuid}/s/#{session_uuid}")
    end
  end

  defp error_message(message) when is_binary(message), do: message
  defp error_message(_other), do: "could not sign up"
end
