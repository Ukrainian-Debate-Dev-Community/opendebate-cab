defmodule Cab.HeadInvitations do
  @moduledoc """
  Invitations to head a club, sent by a platform admin to an e-mail
  address no account uses yet. The link carries a one-time token; the
  person signs in with any account and becomes the head through
  `Clubs.change_head/2`. A club has at most one pending invitation: a
  new one cancels the previous. The address is kept only while the
  invitation is pending.
  """

  import Ecto.Query
  use Gettext, backend: CabWeb.Gettext

  alias Cab.{Clubs, Links, Repo}
  alias Cab.Accounts.User
  alias Cab.Clubs.{Club, HeadInvitation, Membership}

  @valid_days 14
  @name_max 120

  @doc "How long a link works, in days."
  def valid_days, do: @valid_days

  @doc "The most characters the invitee's name has."
  def name_max, do: @name_max

  @doc """
  Invites `name` at `email` to head `club`. `interim` is the admin who
  heads a club created for this invitation until it is accepted.
  Returns `{:ok, invitation, token}`; the token exists only in the link.
  """
  def invite(%Club{} = club, email, name, %User{} = inviter, interim \\ nil) do
    case check_invitee(email, name) do
      {:error, message} ->
        {:error, message}

      {:ok, email, name} ->
        token = new_token()
        now = DateTime.utc_now(:second)

        Repo.transaction(fn ->
          cancel_pending(club, now)

          Repo.insert!(%HeadInvitation{
            club_id: club.id,
            email: email,
            name: name,
            token_hash: hash(token),
            invited_by_user_id: inviter.id,
            interim_user_id: interim && interim.id,
            expires_at: expires(now)
          })
        end)
        |> case do
          {:ok, invitation} -> {:ok, Repo.preload(invitation, :club), token}
          {:error, _} -> {:error, dgettext("errors", "The invitation was not saved. Try again.")}
        end
    end
  end

  @doc """
  The invitee's address and name as they are stored: `{:ok, email,
  name}` or `{:error, message}` - checked before anything is created.
  """
  def check_invitee(email, name) do
    email = Core.Text.trim(email)

    with true <- email?(email) || {:error, :email},
         {:ok, name} when is_binary(name) <-
           Cab.Text.check(name,
             required: true,
             max: @name_max,
             message: dgettext("errors", "Type their name for the invitation.")
           ) do
      {:ok, email, name}
    else
      {:error, :email} ->
        {:error, dgettext("errors", "Type an e-mail address to invite someone new.")}

      {:error, message} ->
        {:error, message}
    end
  end

  @doc "An address worth sending to; see Core.Forms.email?/1."
  def email?(text) when is_binary(text), do: Core.Forms.email?(text)
  def email?(_text), do: false

  @doc """
  The pending invitation behind a token, or why there is none:
  `:unknown`, `:expired`, `:used` or `:cancelled`.
  """
  def by_token(token) when is_binary(token) do
    case Repo.get_by(HeadInvitation, token_hash: hash(token)) do
      nil ->
        {:error, :unknown}

      %HeadInvitation{accepted_at: %DateTime{}} ->
        {:error, :used}

      %HeadInvitation{cancelled_at: %DateTime{}} ->
        {:error, :cancelled}

      invitation ->
        if expired?(invitation),
          do: {:error, :expired},
          else: {:ok, Repo.preload(invitation, :club)}
    end
  end

  def by_token(_token), do: {:error, :unknown}

  @doc """
  The signed-in `user` accepts: they become the head (the previous head
  stays a member; an admin who headed the club only for the invitation
  leaves it). The link is the proof, so any account may accept, but a
  guest (a personal-link account) cannot head a club.
  """
  def accept(token, %User{} = user) do
    with {:ok, invitation} <- by_token(token),
         :ok <- not_a_guest(user),
         {:ok, club} <- Clubs.change_head(invitation.club, user) do
      now = DateTime.utc_now(:second)

      invitation
      |> Ecto.Changeset.change(
        accepted_at: now,
        accepted_by_user_id: user.id,
        email: nil
      )
      |> Repo.update!()

      if invitation.interim_user_id && invitation.interim_user_id != user.id do
        Repo.delete_all(
          from m in Membership,
            where: m.club_id == ^club.id and m.user_id == ^invitation.interim_user_id
        )
      end

      {:ok, club}
    end
  end

  @doc "A new link for a pending invitation; the old one stops working."
  def resend(%HeadInvitation{} = invitation) do
    if pending?(invitation) or expired_unused?(invitation) do
      token = new_token()

      invitation =
        invitation
        |> Ecto.Changeset.change(
          token_hash: hash(token),
          expires_at: expires(DateTime.utc_now(:second))
        )
        |> Repo.update!()
        |> Repo.preload(:club)

      {:ok, invitation, token}
    else
      {:error, dgettext("errors", "That invitation is no longer pending.")}
    end
  end

  @doc "Withdraws a pending invitation and forgets its address."
  def cancel(%HeadInvitation{} = invitation) do
    invitation
    |> Ecto.Changeset.change(cancelled_at: DateTime.utc_now(:second), email: nil)
    |> Repo.update()
  end

  def get(id), do: Repo.get(HeadInvitation, id) |> then(&(&1 && Repo.preload(&1, :club)))

  @doc """
  The pending invitations, newest first, with their clubs. Expired ones
  lose their address on the way: nobody can accept them any more.
  """
  def list_pending do
    forget_expired()

    Repo.all(
      from i in HeadInvitation,
        where: is_nil(i.accepted_at) and is_nil(i.cancelled_at) and not is_nil(i.email),
        order_by: [desc: i.inserted_at],
        preload: :club
    )
  end

  @doc "Clears the address of every invitation that expired unused."
  def forget_expired do
    now = DateTime.utc_now(:second)

    from(i in HeadInvitation,
      where: is_nil(i.accepted_at) and is_nil(i.cancelled_at) and i.expires_at < ^now
    )
    |> Repo.update_all(set: [email: nil, cancelled_at: now])
  end

  @doc "The club a token would hand over, for the sign-in page's prompt."
  def club_for_token(token) do
    case by_token(token) do
      {:ok, invitation} -> invitation.club
      _ -> nil
    end
  end

  defp cancel_pending(%Club{} = club, now) do
    from(i in HeadInvitation,
      where: i.club_id == ^club.id and is_nil(i.accepted_at) and is_nil(i.cancelled_at)
    )
    |> Repo.update_all(set: [cancelled_at: now, email: nil])
  end

  defp not_a_guest(%User{id: id}) do
    if Links.guest?(id),
      do: {:error, :guest},
      else: :ok
  end

  defp pending?(i), do: is_nil(i.accepted_at) and is_nil(i.cancelled_at) and not expired?(i)
  defp expired_unused?(i), do: is_nil(i.accepted_at) and is_nil(i.cancelled_at) and expired?(i)
  defp expired?(i), do: DateTime.compare(i.expires_at, DateTime.utc_now()) == :lt

  defp expires(now), do: DateTime.add(now, @valid_days, :day)

  defp new_token, do: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  defp hash(token), do: :crypto.hash(:sha256, token)
end
