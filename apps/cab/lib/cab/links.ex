defmodule Cab.Links do
  @moduledoc """
  Guest links: people register for a club session WITHOUT an account
  via the shared `/r/:session_uuid` URL the head gives out, or the
  head adds them by name. Each guest is an engine participant with no
  engine account behind it, and a gateway user (no OAuth identity)
  holding a personal link whose `code` IS their access to that
  session. The link keeps the participant id and the engine's
  one-time claim token, which hands the participant to the person's
  own account once they sign up.

  Link identity never satisfies the signed-in member/owner trees:
  guests hold no membership anywhere, so `Clubs.role_for/2` keeps
  them `:public` everywhere; inside their scoped session they are at
  most a participant.
  """

  import Ecto.Query

  use Gettext, backend: CabWeb.Gettext

  alias Cab.Accounts.User
  alias Cab.Clubs.Club
  alias Cab.Links.Link
  alias Cab.Repo
  alias Cab.Sessions
  alias Cab.Sessions.Session

  @username_attempts 3
  @name_max 120

  @doc "The most characters a guest's name has."
  def name_max, do: @name_max

  # ---------------------------------------------------------------
  # Reads
  # ---------------------------------------------------------------

  @doc "The link behind a code, ONLY while not revoked - revoked is gone (404)."
  def get_active_by_code(code) when is_binary(code) do
    Repo.one(
      from l in Link,
        where: l.code == ^code and is_nil(l.revoked_at),
        preload: [:user, :club, session: :club]
    )
  end

  def get_active_by_code(_code), do: nil

  @doc "The finished sessions of `club` this guest has a personal link for, newest first."
  def finished_session_uuids(%User{id: user_id}, %Club{id: club_id}) do
    Repo.all(
      from l in Link,
        join: s in assoc(l, :session),
        where:
          l.user_id == ^user_id and l.club_id == ^club_id and is_nil(l.revoked_at) and
            not is_nil(s.finished_at),
        order_by: [desc: s.finished_at],
        select: s.uuid
    )
  end

  @doc "The session's active (not revoked) guest links, oldest first, with users."
  def list_for_session(%Session{} = session) do
    Repo.all(
      from l in Link,
        where: l.session_id == ^session.id and is_nil(l.revoked_at),
        order_by: l.id,
        preload: [:user]
    )
  end

  @doc """
  The session's form responses, for the head: one row per guest with
  an active personal link, oldest first, as
  `%{columns: [field], rows: [%{name, registered_at, answers}]}`.
  Columns go by the label each answer was given under (answers keep
  a copy), so answers stay readable after the form changed: the
  club's form fields in form order, then labels only old answers
  carry. A column is `%{"id", "label"}`; `answers` maps a column's
  label to the answer (`Core.Forms` shape). Gateway rows only.
  """
  def responses(%Session{} = session) do
    links = list_for_session(session)
    answers = Enum.flat_map(links, &(&1.answers || []))

    columns =
      (Cab.Clubs.guest_form(session_club(session)) ++ answers)
      |> Enum.map(&Map.take(&1, ["id", "label"]))
      |> Enum.uniq_by(& &1["label"])

    rows =
      for link <- links do
        %{
          name: link.user.name,
          registered_at: link.inserted_at,
          answers:
            (link.answers || [])
            |> Enum.reverse()
            |> Map.new(&{&1["label"], &1})
        }
      end

    %{columns: columns, rows: rows}
  end

  @doc """
  Is this user a link guest (holds any personal link)? A guest
  identity may be swapped for another guest's link on the same
  device; a real account never is.
  """
  def guest?(user_id) when is_integer(user_id),
    do: Repo.exists?(from l in Link, where: l.user_id == ^user_id)

  def guest?(_user_id), do: false

  @doc """
  CLAIM: a signed-in account takes over a guest's place. The engine
  hands the guest's participant to the account with the link's
  one-time token, and the place takes the account's name; cab then
  deletes the guest account, and the personal link with it.
  Returns `{:ok, 1}` or `{:error, message}`.
  """
  def claim(%Link{user: %User{} = guest} = link, %User{} = account) do
    cond do
      guest.id == account.id or guest?(account.id) ->
        {:error, dgettext("errors", "Sign in with your own account to claim a guest history.")}

      is_nil(link.engine_participant_id) or is_nil(link.claim_token) ->
        {:error, dgettext("errors", "This personal link cannot be claimed.")}

      true ->
        with %User{node_user_id: actor} when is_integer(actor) <-
               Cab.Accounts.ensure_node_user(account),
             {:ok, _participant} <-
               Cab.EngineApi.claim_participant(
                 actor,
                 link.engine_participant_id,
                 link.claim_token
               ) do
          rename(link, account)
          Sessions.credit_claimed_win(link.session, link.engine_participant_id, actor)
          Repo.delete(guest)
          Sessions.broadcast(link.session)
          {:ok, 1}
        else
          %User{} -> {:error, dgettext("errors", "Something went wrong, try again.")}
          error -> error
        end
    end
  end

  # the claimed place carries the account's name from now on
  defp rename(%Link{session: %Session{} = session} = link, account) do
    with {:ok, head_actor} <- Cab.Clubs.club_actor(session_club(session)) do
      Cab.EngineApi.update_participant(
        head_actor,
        session.engine_event_id,
        link.engine_participant_id,
        %{display_name: account.name || account.username}
      )
    end
  end

  @doc "The link behind a pasted personal link (full URL or bare code)."
  def find_by_pasted(text) when is_binary(text) do
    text
    |> String.trim()
    |> String.split(["/l/", "?", "#"])
    |> case do
      [_before, code | _rest] -> code
      [code] -> code
      _ -> nil
    end
    |> then(&if &1, do: get_active_by_code(String.trim(&1, "/")))
  end

  def find_by_pasted(_text), do: nil

  @doc ~S(The link's guest role in the session signups: "speaker" | "adjudicator" | nil.)
  def role_in(%Link{engine_participant_id: participant_id}, signups)
      when is_integer(participant_id) do
    case Enum.find(signups, &(&1["id"] == participant_id)) do
      %{"role" => role} -> role
      nil -> nil
    end
  end

  def role_in(%Link{}, _signups), do: nil

  # ---------------------------------------------------------------
  # Registration (the shared URL's POST and the head's issue-by-hand)
  # ---------------------------------------------------------------

  @doc """
  Registers a guest for the session: a guest gateway user (generated
  username, the form's name as display name, NO oauth identity), an
  engine participant with no engine account (`Cab.Sessions.add_guest/2`,
  which enforces the `:signup` stage gate), and the personal link row
  keeping the participant and its claim token. `answer_params` are
  the shared URL's answers to the club's registration form (keyed by
  field id, `Core.Forms.validate_answers/2` against the club's
  `guest_form`), checked with the name and kept
  on the link; nil (the head adding a guest by hand) asks nothing.
  Returns `{:ok, link}` with the user preloaded,
  `{:error, :conflict, message}` once sign-ups closed,
  `{:error, %{name: message}}` for a blank, over-long or garbled name (plus
  `{:answer, field_id} => message` for each refused answer), or
  `{:error, message}`.
  """
  def register_guest(%Session{} = session, name, answer_params \\ nil) do
    with {:ok, name, answers} <- validate_guest(session, name, answer_params),
         {:ok, guest} <- create_guest_user(name) do
      case Sessions.add_guest(session, name) do
        {:ok, participant} ->
          issue(guest, session, participant, answers)

        error ->
          # no orphan gateway rows for refused registrations
          Repo.delete(guest)
          error
      end
    end
  end

  @doc "The engine participants a guest holds through their active personal links."
  def participant_ids(user_id) when is_integer(user_id) do
    Repo.all(
      from l in Link,
        where:
          l.user_id == ^user_id and is_nil(l.revoked_at) and not is_nil(l.engine_participant_id),
        select: l.engine_participant_id
    )
  end

  def participant_ids(_user_id), do: []

  @doc "Does this guest hold a personal link for that session?"
  def holds_session?(user_id, %Session{id: session_id}) when is_integer(user_id) do
    Repo.exists?(
      from l in Link,
        where: l.user_id == ^user_id and l.session_id == ^session_id and is_nil(l.revoked_at)
    )
  end

  def holds_session?(_user_id, _session), do: false

  @doc """
  Deletes a removed guest's cab account - their personal links go with
  it (the foreign key cascades) - so nothing personal stays behind. A
  real account is never touched: only a user holding links and no
  sign-in identity is a guest.
  """
  def purge_guest(participant_id) when is_integer(participant_id) do
    guest =
      Repo.one(
        from u in User,
          as: :user,
          where:
            exists(
              from l in Link,
                where:
                  l.user_id == parent_as(:user).id and l.engine_participant_id == ^participant_id
            ) and
              not exists(from i in Cab.Accounts.Identity, where: i.user_id == parent_as(:user).id)
      )

    if guest, do: Repo.delete(guest)
    :ok
  end

  def purge_guest(_participant_id), do: :ok

  defp issue(%User{} = guest, %Session{} = session, participant, answers) do
    %Link{
      user_id: guest.id,
      club_id: session_club(session).id,
      session_id: session.id,
      engine_participant_id: participant["id"],
      claim_token: participant["raw_claim_token"],
      answers: answers
    }
    |> Link.changeset()
    |> Repo.insert()
    |> case do
      {:ok, link} ->
        {:ok, %{link | user: guest}}

      {:error, _changeset} ->
        {:error, dgettext("errors", "Could not create the personal link. Try again.")}
    end
  end

  # the name and every answer are checked together, so one re-render
  # shows all that is wrong
  defp validate_guest(_session, name, nil) do
    with {:ok, name} <- validate_name(name), do: {:ok, name, []}
  end

  defp validate_guest(session, name, answer_params) do
    answers =
      case Core.Forms.validate_answers(
             Cab.Clubs.guest_form(session_club(session)),
             answer_params
           ) do
        {:ok, answers} -> {:ok, answers}
        {:error, errors} -> {:error, Map.new(errors, fn {id, msg} -> {{:answer, id}, msg} end)}
      end

    case {validate_name(name), answers} do
      {{:ok, name}, {:ok, answers}} -> {:ok, name, answers}
      {{:ok, _name}, {:error, errors}} -> {:error, errors}
      {{:error, errors}, {:ok, _answers}} -> {:error, errors}
      {{:error, name_errors}, {:error, errors}} -> {:error, Map.merge(errors, name_errors)}
    end
  end

  defp validate_name(name) do
    case Cab.Text.check(name,
           required: true,
           max: @name_max,
           message: dgettext("errors", "Enter a name.")
         ) do
      {:ok, name} -> {:ok, name}
      {:error, message} -> {:error, %{name: message}}
    end
  end

  defp create_guest_user(name, attempts \\ @username_attempts)

  defp create_guest_user(_name, 0),
    do: {:error, dgettext("errors", "Something went wrong, try again.")}

  defp create_guest_user(name, attempts) do
    suffix = :crypto.strong_rand_bytes(5) |> Base.encode32(case: :lower, padding: false)

    %User{}
    |> User.changeset(%{username: "guest-#{suffix}", name: name})
    |> Repo.insert()
    |> case do
      {:ok, guest} -> {:ok, guest}
      {:error, _changeset} -> create_guest_user(name, attempts - 1)
    end
  end

  defp session_club(%Session{club: %Club{} = club}), do: club
  defp session_club(%Session{club_id: club_id}), do: Repo.get!(Club, club_id)
end
