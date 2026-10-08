defmodule Cab.Links do
  @moduledoc """
  Guest links (M6 / launch-timeline L2): people register for a club
  session WITHOUT an account via the shared `/r/:session_uuid` URL
  the head gives out. Each guest becomes a gateway user (no OAuth
  identity) with an engine shadow counterpart, signed up through the
  proven `Cab.Sessions.signup/3` path, and receives a permanent
  personal link row whose `code` IS their access to that club/session
  (and, post-launch, the claim token — redemption is out of scope).

  Link identity never satisfies the signed-in member/owner trees:
  guests hold no membership anywhere, so `Clubs.role_for/2` keeps
  them `:public` everywhere; inside their scoped session they are at
  most a participant.
  """

  import Ecto.Query

  alias Cab.Accounts.User
  alias Cab.Clubs.Club
  alias Cab.Links.Link
  alias Cab.Repo
  alias Cab.Sessions
  alias Cab.Sessions.Session

  @username_attempts 3

  # ---------------------------------------------------------------
  # Reads
  # ---------------------------------------------------------------

  @doc "The link behind a code, ONLY while not revoked — revoked is gone (404)."
  def get_active_by_code(code) when is_binary(code) do
    Repo.one(
      from l in Link,
        where: l.code == ^code and is_nil(l.revoked_at),
        preload: [:user, :club, session: :club]
    )
  end

  def get_active_by_code(_code), do: nil

  def get_link(id) when is_integer(id) do
    Repo.one(from l in Link, where: l.id == ^id, preload: [:user, :club, session: :club])
  end

  def get_link(_id), do: nil

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
  Is this user a link guest (holds any personal link)? A guest
  identity may be swapped for another guest's link on the same
  device; a real account never is.
  """
  def guest?(user_id) when is_integer(user_id),
    do: Repo.exists?(from l in Link, where: l.user_id == ^user_id)

  def guest?(_user_id), do: false

  @doc ~S(The link's guest role in the session signups: "speaker" | "adjudicator" | nil.)
  def role_in(%Link{user: %User{node_user_id: node_user_id}}, signups)
      when is_integer(node_user_id) do
    case Enum.find(signups, &(&1["user_id"] == node_user_id)) do
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
  username, the form's name as display name, NO oauth identity), the
  engine signup through `Sessions.signup/3` (which provisions the
  engine shadow user lazily and enforces the `:signup` stage gate),
  and the personal link row. Returns `{:ok, link}` with the user
  preloaded, `{:error, :conflict, message}` once sign-ups closed,
  `{:error, %{name: message}}` for a blank name, or `{:error, message}`.
  """
  def register_guest(%Session{} = session, name, kind) when kind in ["speak", "judge"] do
    with {:ok, name} <- validate_name(name),
         {:ok, guest} <- create_guest_user(name) do
      case Sessions.signup(guest, session, kind) do
        {:ok, _participant} ->
          issue(guest, session)

        error ->
          # no orphan gateway rows for refused registrations (the
          # engine shadow, if provisioned, stays — engine is frozen)
          Repo.delete(guest)
          error
      end
    end
  end

  def register_guest(%Session{}, _name, _kind),
    do: {:error, ~s(sign up "as" must be "speak" or "judge")}

  @doc "Revokes the link: the code stops resolving immediately."
  def revoke(%Link{} = link) do
    link
    |> Ecto.Changeset.change(revoked_at: DateTime.utc_now(:second))
    |> Repo.update()
  end

  defp issue(%User{} = guest, %Session{} = session) do
    %Link{user_id: guest.id, club_id: session_club(session).id, session_id: session.id}
    |> Link.changeset()
    |> Repo.insert()
    |> case do
      {:ok, link} -> {:ok, %{link | user: guest}}
      {:error, _changeset} -> {:error, "could not issue the link"}
    end
  end

  defp validate_name(name) when is_binary(name) do
    case String.trim(name) do
      "" -> {:error, %{name: "name is required"}}
      trimmed -> {:ok, trimmed}
    end
  end

  defp validate_name(_name), do: {:error, %{name: "name is required"}}

  defp create_guest_user(name, attempts \\ @username_attempts)

  defp create_guest_user(_name, 0), do: {:error, "could not create the guest user"}

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
