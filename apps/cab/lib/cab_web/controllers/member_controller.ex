defmodule CabWeb.MemberController do
  use CabWeb, :controller

  alias Cab.Sessions
  alias Cab.Sessions.Session

  plug CabWeb.ClubScope, source: :club, require: :member

  # GET /c/:club_uuid/member — sessions list + current session + signups
  def show(conn, _params) do
    club = conn.assigns.club
    sessions = Sessions.list_for_club(club)
    current = List.first(sessions)

    state =
      with %Session{} <- current,
           {:ok, state} <- Sessions.state(%{current | club: club}) do
        state
      else
        _ -> nil
      end

    render(conn, :show,
      sessions: sessions,
      current: current,
      state: state,
      page_title: "#{club.name} · member"
    )
  end

  # POST /c/:club_uuid/member/sessions/:session_uuid/signups
  def signup(conn, %{"session_uuid" => session_uuid} = params) do
    club = conn.assigns.club
    kind = params["as"]

    with %Session{} = session <- Sessions.get_for_club(club, session_uuid),
         true <- kind in ["speak", "judge"],
         {:ok, _participant} <- Sessions.signup(conn.assigns.current_user, session, kind) do
      conn
      |> put_flash(:info, "signed up to #{kind}")
      |> redirect(to: ~p"/c/#{club.uuid}/member")
    else
      nil ->
        conn |> send_resp(404, "not found") |> halt()

      false ->
        conn
        |> put_flash(:error, ~s(sign up "as" must be "speak" or "judge"))
        |> redirect(to: ~p"/c/#{club.uuid}/member")

      {:error, message} ->
        conn
        |> put_flash(:error, error_message(message))
        |> redirect(to: ~p"/c/#{club.uuid}/member")
    end
  end

  defp error_message(message) when is_binary(message), do: message
  defp error_message(_other), do: "could not sign up"
end
