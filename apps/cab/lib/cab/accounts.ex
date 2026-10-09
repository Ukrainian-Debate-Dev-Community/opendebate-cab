defmodule Cab.Accounts do
  @moduledoc """
  OAuth-backed accounts. Users sign in only via external providers;
  an Identity row links each (provider, uid) pair to a User.
  """

  import Ecto.Query

  require Logger

  alias Cab.Accounts.{Identity, User}
  alias Cab.Repo

  def get_user(id), do: Repo.get(User, id)

  @doc "The user behind a browser session, marked when it is a personal-link guest."
  def get_viewer(id) do
    case get_user(id) do
      nil -> nil
      user -> %{user | guest: Cab.Links.guest?(user.id)}
    end
  end

  def get_user_by_username(username) when is_binary(username),
    do: Repo.get_by(User, username: username)

  def get_user_by_username(_username), do: nil

  def list_users, do: Repo.all(from u in User, order_by: u.username)

  @doc "The /account profile edit — display name only; identity fields stay provider-fed."
  # the zones offered on /account; "" = the device's own zone
  @time_zones ~w(Europe/Kyiv Europe/Warsaw Europe/Vilnius Europe/Riga Europe/Tallinn
                 Europe/Bucharest Europe/Chisinau Europe/Prague Europe/Berlin Europe/Paris
                 Europe/Madrid Europe/Rome Europe/Amsterdam Europe/London Europe/Lisbon
                 Europe/Istanbul Asia/Tbilisi Asia/Dubai America/New_York America/Chicago
                 America/Denver America/Los_Angeles America/Toronto Asia/Tokyo
                 Australia/Sydney UTC)

  def time_zones, do: @time_zones

  def update_profile(%User{} = user, attrs) do
    changes = %{name: attrs["name"] || attrs[:name]}

    changes =
      case attrs["time_zone"] || attrs[:time_zone] do
        nil -> changes
        "" -> Map.put(changes, :time_zone, nil)
        zone when zone in @time_zones -> Map.put(changes, :time_zone, zone)
        _unknown -> changes
      end

    user
    |> User.changeset(changes)
    |> Ecto.Changeset.cast(changes, [:time_zone])
    |> Repo.update()
  end

  @doc "The user's linked provider identities (the /account providers card)."
  def list_identities(%User{} = user) do
    Repo.all(from i in Identity, where: i.user_id == ^user.id, order_by: i.provider)
  end

  @doc """
  Finds the user for an Ueberauth result, creating user + identity on
  first login. Profile fields are refreshed from the provider each time.
  """
  def upsert_from_oauth(%Ueberauth.Auth{} = auth) do
    provider = to_string(auth.provider)
    uid = to_string(auth.uid)

    attrs = %{
      # a username is shown on rosters, so never the e-mail address
      username: auth.info.nickname || slug(auth.info.name) || "member",
      name: auth.info.name,
      email: auth.info.email,
      avatar_url: auth.info.image
    }

    case Repo.one(from i in Identity, where: [provider: ^provider, provider_uid: ^uid]) do
      %Identity{user_id: user_id} ->
        get_user(user_id)
        |> User.changeset(Map.delete(attrs, :username))
        |> Repo.update()

      nil ->
        create_from_oauth(provider, uid, attrs)
    end
  end

  defp create_from_oauth(provider, uid, attrs) do
    Repo.transaction(fn ->
      user =
        %User{}
        |> User.changeset(attrs)
        |> ensure_free_username()
        |> Repo.insert!()

      %Identity{user_id: user.id}
      |> Identity.changeset(%{provider: provider, provider_uid: uid})
      |> Repo.insert!()

      user
    end)
  end

  defp slug(nil), do: nil

  defp slug(name) do
    case name
         |> String.downcase()
         |> String.replace(~r/[^\p{L}\p{N}]+/u, "-")
         |> String.trim("-") do
      "" -> nil
      slug -> String.slice(slug, 0, 30)
    end
  end

  @doc """
  LINK: a signed-in account adds another sign-in method. Returns
  `{:ok, :linked}`, `{:ok, :already}` when it is already this account's,
  `{:other_account, user}` when that sign-in has its own cab account
  (the caller may offer to merge), or `{:error, message}`.
  """
  def link_identity(%User{} = user, %Ueberauth.Auth{} = auth) do
    provider = to_string(auth.provider)
    uid = to_string(auth.uid)

    case Repo.one(from i in Identity, where: [provider: ^provider, provider_uid: ^uid]) do
      %Identity{user_id: id} when id == user.id ->
        {:ok, :already}

      %Identity{user_id: other_id} ->
        {:other_account, get_user(other_id)}

      nil ->
        if Repo.exists?(
             from i in Identity, where: i.user_id == ^user.id and i.provider == ^provider
           ) do
          {:error, "This account already has a different #{provider} sign-in linked."}
        else
          %Identity{user_id: user.id}
          |> Identity.changeset(%{provider: provider, provider_uid: uid})
          |> Repo.insert()
          |> case do
            {:ok, _} -> {:ok, :linked}
            {:error, _} -> {:error, "Could not link that sign-in. Try again."}
          end
        end
    end
  end

  @doc "Removes a sign-in method, as long as another one is left."
  def unlink_identity(%User{} = user, provider) do
    identities = list_identities(user)

    case Enum.find(identities, &(&1.provider == provider)) do
      nil -> {:error, "That sign-in is not linked."}
      _ when length(identities) < 2 -> {:error, "Keep at least one way to sign in."}
      identity -> Repo.delete(identity)
    end
  end

  @doc """
  MERGE: two accounts of one person become one. The engine moves the
  other account's debate history onto this one (under this account's
  name); cab moves its sign-in methods, club memberships (the stronger
  of two in the same club stays) and invitations, then deletes it.
  The engine refuses when the other account heads a club, or when both
  took part in the same session.
  """
  def merge_accounts(%User{id: id}, %User{id: id}), do: {:error, "That is this account."}

  def merge_accounts(%User{} = target, %User{} = source) do
    target = ensure_node_user(target)

    with :ok <- merge_engine(target, source) do
      Repo.transaction(fn ->
        from(i in Identity, where: i.user_id == ^source.id)
        |> Repo.update_all(set: [user_id: target.id])

        merge_memberships(target, source)
        merge_invitations(target, source)

        from(s in Cab.Sessions.Session, where: s.opened_by_user_id == ^source.id)
        |> Repo.update_all(set: [opened_by_user_id: target.id])

        if source.is_admin and not target.is_admin do
          from(u in User, where: u.id == ^target.id) |> Repo.update_all(set: [is_admin: true])
        end

        Repo.delete!(source)
        get_user(target.id)
      end)
    end
  end

  defp merge_engine(_target, %User{node_user_id: nil}), do: :ok

  defp merge_engine(%User{node_user_id: target_node} = target, %User{node_user_id: source_node})
       when is_integer(target_node) do
    case Cab.EngineApi.merge_users(
           target_node,
           source_node,
           target_node,
           target.name || target.username
         ) do
      {:ok, _} ->
        :ok

      {:error, "The source user holds roles" <> _} ->
        {:error, "That account heads a club. Make someone else head first."}

      error ->
        error
    end
  end

  defp merge_engine(_target, _source),
    do: {:error, "Something went wrong, try again."}

  @rank %{{"head", "approved"} => 3, {"member", "approved"} => 2}

  defp merge_memberships(target, source) do
    mine =
      Repo.all(from m in Cab.Clubs.Membership, where: m.user_id == ^target.id)
      |> Map.new(&{&1.club_id, &1})

    for theirs <- Repo.all(from m in Cab.Clubs.Membership, where: m.user_id == ^source.id) do
      case mine[theirs.club_id] do
        nil ->
          theirs |> Ecto.Changeset.change(user_id: target.id) |> Repo.update!()

        ours ->
          if Map.get(@rank, {theirs.role, theirs.status}, 1) >
               Map.get(@rank, {ours.role, ours.status}, 1) do
            Repo.delete!(ours)
            theirs |> Ecto.Changeset.change(user_id: target.id) |> Repo.update!()
          else
            Repo.delete!(theirs)
          end
      end
    end
  end

  defp merge_invitations(target, source) do
    alias Cab.Invitations.Invitation
    taken = Repo.all(from i in Invitation, where: i.user_id == ^target.id, select: i.session_id)

    from(i in Invitation, where: i.user_id == ^source.id and i.session_id in ^taken)
    |> Repo.delete_all()

    from(i in Invitation, where: i.user_id == ^source.id)
    |> Repo.update_all(set: [user_id: target.id])

    from(i in Invitation, where: i.invited_by_user_id == ^source.id)
    |> Repo.update_all(set: [invited_by_user_id: target.id])
  end

  @doc """
  Makes sure the user has a counterpart in the Node engine, provisioning
  one on first need. Non-fatal by design: if the engine is unreachable
  the user is returned unchanged and provisioning happens lazily on the
  next engine-touching action.
  """
  def ensure_node_user(%User{node_user_id: nil} = user) do
    case Core.Engine.provision_user(user.username) do
      {:ok, engine_id} ->
        case set_node_user_id(user, engine_id) do
          {:ok, updated} ->
            updated

          {:error, changeset} ->
            Logger.warning("could not persist node_user_id: #{inspect(changeset.errors)}")
            user
        end

      {:error, reason} ->
        Logger.warning(
          "engine provisioning failed for #{user.username}: #{inspect(reason)} " <>
            "(continuing sign-in; will retry lazily)"
        )

        user
    end
  end

  def ensure_node_user(%User{} = user), do: user

  def set_node_user_id(%User{} = user, node_user_id) do
    user
    |> User.node_changeset(node_user_id)
    |> Repo.update()
  end

  defp ensure_free_username(changeset) do
    username = Ecto.Changeset.get_field(changeset, :username)

    if Repo.exists?(from u in User, where: u.username == ^username) do
      suffix = :crypto.strong_rand_bytes(3) |> Base.encode16(case: :lower)
      Ecto.Changeset.put_change(changeset, :username, "#{username}-#{suffix}")
    else
      changeset
    end
  end
end
