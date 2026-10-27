defmodule CabWeb.Api.SignupController do
  use CabWeb, :controller

  alias Cab.Sessions
  alias CabWeb.ClubScope

  action_fallback CabWeb.Api.FallbackController

  plug ClubScope, source: :session, require: :member

  # POST /api/cab/v1/sessions/:uuid/signups {"username": optional - head
  # only, signs up any approved member}. No role: the head decides
  # who judges at allocation.
  def create(conn, %{"username" => username}) when is_binary(username) do
    with :ok <- require_owner(conn),
         {:ok, participant} <-
           Sessions.claim_place(conn.assigns.session, fn ->
             Sessions.signup_for(conn.assigns.current_user, conn.assigns.session, username)
           end) do
      conn
      |> put_status(201)
      |> json(%{participant_id: participant["id"], username: username})
    end
  end

  # self sign-up {"answers": {field id => value}}: the same club form
  # questions as the club page (Cab.Registrations), required ones
  # included
  def create(conn, params) do
    user = conn.assigns.current_user
    session = conn.assigns.session

    case Cab.Registrations.register(user, session, answer_params(params)) do
      {:ok, participant_id} ->
        conn
        |> put_status(201)
        |> json(%{participant_id: participant_id})

      {:error, {:answers, codes}} ->
        session = Cab.Repo.preload(session, :club)
        {_kind, fields, _values} = Cab.Registrations.form_for(session.club, user)
        {:error, answer_details(fields, codes)}

      error ->
        error
    end
  end

  defp answer_params(%{"answers" => answers}) when is_map(answers), do: answers
  defp answer_params(_params), do: %{}

  defp answer_details(fields, codes) do
    for field <- fields, code = codes[field["id"]], into: %{} do
      {field["id"], CabWeb.FormComponents.answer_error(code, field["type"])}
    end
  end

  # DELETE /api/cab/v1/sessions/:uuid/signups/:participant_id - the head
  # removes anyone, a member removes their own signup
  def delete(conn, %{"participant_id" => participant_id}) do
    with {:ok, participant_id} <- parse_id(participant_id),
         :ok <-
           Sessions.remove_signup(
             conn.assigns.current_user,
             conn.assigns.session,
             participant_id
           ) do
      json(conn, %{participant_id: participant_id, status: "removed"})
    end
  end

  # POST /api/cab/v1/sessions/:uuid/signups/remove {"participant_ids": [..]}
  # - head only: removes everyone who can go, answers who stayed and why
  def remove_many(conn, params) do
    with :ok <- require_owner(conn),
         {:ok, ids} <- participant_ids(params) do
      result = Sessions.remove_signups(conn.assigns.current_user, conn.assigns.session, ids)

      json(conn, %{
        removed: result.removed,
        refused: for({id, error} <- result.refused, do: %{participant_id: id, error: error})
      })
    end
  end

  @max_batch 200

  defp participant_ids(%{"participant_ids" => ids})
       when is_list(ids) and ids != [] and length(ids) <= @max_batch do
    if Enum.all?(ids, &(is_integer(&1) and &1 > 0)),
      do: {:ok, ids},
      else: {:error, %{participant_ids: "must be positive integers"}}
  end

  defp participant_ids(_params),
    do: {:error, %{participant_ids: "a list of 1 to #{@max_batch} participant ids is required"}}

  defp require_owner(conn) do
    if Cab.Clubs.covers?(conn.assigns.club_role, :owner), do: :ok, else: {:error, :forbidden}
  end

  defp parse_id(id) do
    case Integer.parse(id) do
      {int, ""} -> {:ok, int}
      _ -> {:error, "bad participant id"}
    end
  end
end
