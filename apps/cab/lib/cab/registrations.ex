defmodule Cab.Registrations do
  @moduledoc """
  A signed-in person registers for a session on the club page with
  their answers to the club form: a member is asked the member fields
  (prefilled from their saved club answers), anyone else with an
  account the guest fields without the e-mail (cab has the account's
  address). The answers are kept for that session only - never
  written back to the member's saved answers - and only the head
  reads them (Responses). Guests register through `Cab.Links`.
  """

  import Ecto.Query

  alias Cab.{Clubs, Invitations, Repo, Sessions}
  alias Cab.Accounts.User
  alias Cab.Registrations.Registration
  alias Cab.Sessions.Session

  @doc """
  The fields this person is asked, and the values to prefill:
  `{:member, fields, values}` or `{:account, fields, %{}}`.
  """
  def form_for(%Clubs.Club{} = club, %User{} = user) do
    case Clubs.membership_of(club, user) do
      %{status: "approved", answers: answers} ->
        {:member, Clubs.member_fields(club), Core.Forms.answer_values(answers)}

      _none ->
        {:account, account_fields(club), %{}}
    end
  end

  # the guest fields without the built-in e-mail
  defp account_fields(club),
    do: Enum.reject(Clubs.guest_fields(club), &(&1["id"] == "email"))

  @doc """
  Registers the signed-in user with their answers (`params` keyed by
  field id): checks them, signs up in the engine (or accepts a pending
  invitation), keeps the answers. `{:ok, participant_id}`, `{:error,
  {:answers, codes}}` or the engine's refusal.
  """
  def register(%User{} = user, %Session{} = session, params) do
    session = Repo.preload(session, :club)
    {_kind, fields, _values} = form_for(session.club, user)

    with {:ok, answers} <- check(fields, params),
         {:ok, participant_id} <- sign_up(user, session) do
      %Registration{
        session_id: session.id,
        user_id: user.id,
        engine_participant_id: participant_id,
        answers: answers
      }
      |> Repo.insert(
        on_conflict: {:replace, [:answers, :engine_participant_id, :updated_at]},
        conflict_target: [:session_id, :user_id]
      )

      {:ok, participant_id}
    end
  end

  defp check(fields, params) do
    case Core.Forms.validate_answers(fields, params, Clubs.answer_opts()) do
      {:ok, answers} -> {:ok, answers}
      {:error, codes} -> {:error, {:answers, codes}}
    end
  end

  defp sign_up(user, session) do
    case Invitations.pending(session, user) do
      nil ->
        with {:ok, participant} <- Sessions.signup(user, session), do: {:ok, participant["id"]}

      invitation ->
        with {:ok, :accepted} <- Invitations.accept(invitation, user),
             do: {:ok, invitation.engine_participant_id}
    end
  end

  @doc "The session's registrations with their users, oldest first."
  def for_session(%Session{} = session) do
    Repo.all(
      from r in Registration,
        where: r.session_id == ^session.id,
        order_by: r.inserted_at,
        preload: [:user]
    )
  end

  @doc "A removed signup's answers go with it."
  def forget_participant(%Session{} = session, participant_id) do
    Repo.delete_all(
      from r in Registration,
        where: r.session_id == ^session.id and r.engine_participant_id == ^participant_id
    )

    :ok
  end
end
