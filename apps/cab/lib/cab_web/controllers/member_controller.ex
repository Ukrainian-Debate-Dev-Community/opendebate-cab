defmodule CabWeb.MemberController do
  use CabWeb, :controller

  alias Cab.Accounts.User
  alias Cab.Sessions
  alias Cab.Sessions.Session

  plug CabWeb.ClubScope, source: :club, require: :member

  # GET /c/:club_uuid/member — P5, my club page ONLY: tonight's
  # session + Register/cancel, my role, my results here. The roster,
  # rooms and draw live on P6.
  def show(conn, _params) do
    club = conn.assigns.club
    current = List.first(Sessions.list_for_club(club))

    state =
      with %Session{} <- current,
           {:ok, state} <- Sessions.state(%{current | club: club}) do
        state
      else
        _ -> nil
      end

    # a finished session is history (P6/P7), not tonight
    {current, state} =
      case state do
        %{stage: :done} -> {nil, nil}
        _ -> {current, state}
      end

    render(conn, :show,
      current: current,
      state: state,
      my_signup: my_signup(state, conn.assigns.current_user),
      my_results: Sessions.user_club_history(club, conn.assigns.current_user),
      page_title: "#{club.name} · me"
    )
  end

  # my registration in tonight's session, if any
  defp my_signup(%{signups: signups}, %User{node_user_id: node_user_id})
       when is_integer(node_user_id) do
    Enum.find(signups, &(&1["user_id"] == node_user_id))
  end

  defp my_signup(_state, _user), do: nil

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
          |> redirect(to: ~p"/c/#{club.uuid}/member")
      end
    else
      nil ->
        conn |> send_resp(404, "not found") |> halt()

      {:error, message} ->
        conn
        |> put_flash(:error, error_message(message))
        |> redirect(to: ~p"/c/#{club.uuid}/member")
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
      |> redirect(to: ~p"/c/#{club.uuid}/member")
    else
      nil ->
        conn |> send_resp(404, "not found") |> halt()

      {:error, :forbidden} ->
        conn |> send_resp(403, "forbidden") |> halt()

      {:error, message} ->
        conn
        |> put_flash(:error, error_message(message))
        |> redirect(to: ~p"/c/#{club.uuid}/member")

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
      |> redirect(to: ~p"/c/#{club.uuid}/member")
    else
      nil ->
        conn |> send_resp(404, "not found") |> halt()

      false ->
        conn
        |> put_flash(:error, ~s(sign up "as" must be "speak" or "judge"))
        |> redirect(to: ~p"/c/#{club.uuid}/member")

      {:error, :conflict, message} ->
        conn
        |> put_flash(:error, message)
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
