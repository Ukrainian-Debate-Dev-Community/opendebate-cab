defmodule Cab.Invitations do
  @moduledoc """
  The head adds people to a session from one search field:

    * club members match as the head types and are signed up at once;
    * any other registered user is found only by their exact username
      or email and is INVITED: the engine seats them right away under
      their name with no user attached, so the head can allocate them;
      they accept from their cabinet whenever they like (after the
      session too) and the engine's one-time claim token makes the
      place theirs, or they decline and their name is removed;
    * anything else becomes a guest by that name (`Cab.Links`).
  """

  import Ecto.Query
  use Gettext, backend: CabWeb.Gettext

  alias Cab.{Accounts, Clubs, EngineApi, Repo, Sessions}
  alias Cab.Accounts.User
  alias Cab.Clubs.Club
  alias Cab.Invitations.Invitation
  alias Cab.Links.Link
  alias Cab.Sessions.Session

  @member_hits 8

  @doc """
  What the head's search field offers for `query`: every member not
  signed up yet while nothing is typed, then the matching ones, a registered non-member on an exact username or
  email match, and the typed text as a guest name. Returns
  `%{members: [user], users: [user], guest: name | nil}`.
  """
  def search(%Club{} = club, %Session{} = session, signups, query) do
    query = Core.Text.trim(query)
    taken = taken_ids(session, signups)

    if query == "" do
      # the dropdown before typing: every member not in the session yet
      members =
        for membership <- Clubs.list_members(club),
            user = membership.user,
            not MapSet.member?(taken, user.id),
            do: user

      %{
        members: Enum.sort_by(members, &String.downcase(&1.name || &1.username)),
        users: [],
        guest: nil
      }
    else
      members =
        for membership <- Clubs.list_members(club),
            user = membership.user,
            not MapSet.member?(taken, user.id),
            prefix?(user, query),
            do: user

      member_ids = MapSet.new(members, & &1.id)
      club_member_ids = MapSet.new(Clubs.list_members(club), & &1.user_id)

      users =
        for user <- exact_users(query),
            not MapSet.member?(member_ids, user.id),
            not MapSet.member?(club_member_ids, user.id),
            not MapSet.member?(taken, user.id),
            do: user

      # a guest only for a name nobody in cab answers to
      guest? = members == [] and users == [] and not String.contains?(query, "@")

      %{
        members: Enum.take(members, @member_hits),
        users: users,
        guest: if(guest?, do: query)
      }
    end
  end

  @doc """
  One typed value to one action, for the form without JavaScript and
  the API: an exact member username or the one member the text
  matches, an exact registered user (username or email), otherwise a
  guest by that name.
  """
  def resolve(%Club{} = club, %Session{} = session, signups, query) do
    query = Core.Text.trim(query)
    hits = search(club, session, signups, query)
    q = String.downcase(query)

    cond do
      query == "" -> nil
      member = Enum.find(hits.members, &(String.downcase(&1.username) == q)) -> {:member, member}
      match?([_], hits.members) -> {:member, hd(hits.members)}
      user = List.first(hits.users) -> {:user, user}
      hits.guest -> {:guest, hits.guest}
      true -> nil
    end
  end

  # cab user ids already in the session: signed up or invited
  defp taken_ids(session, signups) do
    node_ids = for p <- signups, is_integer(p["user_id"]), do: p["user_id"]

    signed =
      Repo.all(from u in User, where: u.node_user_id in ^node_ids, select: u.id)

    invited =
      Repo.all(from i in Invitation, where: i.session_id == ^session.id, select: i.user_id)

    MapSet.new(signed ++ invited)
  end

  defp prefix?(user, query) do
    q = String.downcase(query)

    [user.username | String.split(user.name || "")]
    |> Enum.any?(&String.starts_with?(String.downcase(&1), q))
  end

  # exact, case-insensitive username or email; guests (personal-link
  # identities) are never offered
  defp exact_users(query) do
    q = String.downcase(query)

    Repo.all(
      from u in User,
        as: :user,
        where: fragment("lower(?)", u.username) == ^q or fragment("lower(?)", u.email) == ^q,
        where: not exists(from l in Link, where: l.user_id == parent_as(:user).id),
        limit: 2
    )
  end

  @doc """
  The head invites a registered user: the engine seats them at once
  (no user attached) and cab keeps the claim token for their accept.
  """
  def invite(%User{} = head, %Session{} = session, %User{} = user) do
    if Cab.Links.guest?(user.id) do
      {:error, dgettext("errors", "Guests join through their personal link.")}
    else
      do_invite(head, session, user)
    end
  end

  defp do_invite(head, session, user) do
    if Repo.exists?(
         from i in Invitation, where: i.session_id == ^session.id and i.user_id == ^user.id
       ) do
      {:error, dgettext("errors", "%{name} is already invited.", name: display_name(user))}
    else
      with {:ok, %{"id" => pid, "raw_claim_token" => token}} <-
             Sessions.add_unclaimed(head, session, display_name(user)) do
        %Invitation{
          session_id: session.id,
          user_id: user.id,
          invited_by_user_id: head.id,
          engine_participant_id: pid,
          claim_token: token
        }
        |> Repo.insert()
      end
    end
  end

  @doc "The user's open invitations, newest first, with session, club and inviter."
  def for_user(%User{} = user) do
    Repo.all(
      from i in Invitation,
        where: i.user_id == ^user.id,
        order_by: [desc: i.inserted_at],
        preload: [:invited_by, session: :club]
    )
  end

  @doc "The session's open invitations, keyed by engine participant id."
  def for_session(%Session{} = session) do
    Repo.all(from i in Invitation, where: i.session_id == ^session.id, preload: [:user])
    |> Map.new(&{&1.engine_participant_id, &1})
  end

  @doc "The user's open invitation to this session, or nil."
  def pending(%Session{} = session, %User{} = user) do
    Repo.one(
      from i in Invitation,
        where: i.session_id == ^session.id and i.user_id == ^user.id,
        preload: [session: :club]
    )
  end

  def get_for_user(id, %User{} = user) do
    Repo.one(
      from i in Invitation,
        where: i.id == ^id and i.user_id == ^user.id,
        preload: [session: :club]
    )
  end

  @doc "Accept: the engine place becomes the user's (any time, the session may be over)."
  def accept(%Invitation{} = invitation, %User{} = user) do
    with %User{node_user_id: actor} when is_integer(actor) <- Accounts.ensure_node_user(user),
         {:ok, _participant} <-
           EngineApi.claim_participant(
             actor,
             invitation.engine_participant_id,
             invitation.claim_token
           ) do
      Repo.delete(invitation)
      Sessions.broadcast(invitation.session)
      {:ok, :accepted}
    else
      %User{} -> {:error, dgettext("errors", "Something went wrong, try again.")}
      error -> error
    end
  end

  @doc "Decline: the place is given up and the name removed; the invitation goes."
  def decline(%Invitation{} = invitation) do
    case Sessions.release_unclaimed(invitation.session, invitation.engine_participant_id) do
      :ok ->
        Repo.delete(invitation)
        :ok

      # the head already removed the place
      {:error, "participant " <> _} ->
        Repo.delete(invitation)
        :ok

      error ->
        error
    end
  end

  @doc "A removed participant takes their open invitation with them."
  def forget_participant(%Session{} = session, participant_id) do
    Repo.delete_all(
      from i in Invitation,
        where: i.session_id == ^session.id and i.engine_participant_id == ^participant_id
    )

    :ok
  end

  defp display_name(%User{} = user) do
    case user.name && String.trim(user.name) do
      name when is_binary(name) and name != "" -> name
      _ -> user.username
    end
  end
end
