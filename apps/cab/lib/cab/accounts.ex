defmodule Cab.Accounts do
  @moduledoc """
  OAuth-backed accounts. Users sign in only via external providers;
  an Identity row links each (provider, uid) pair to a User.
  """

  import Ecto.Query
  use Gettext, backend: CabWeb.Gettext

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

  @doc """
  The account with exactly this username or e-mail (case-insensitive),
  or nil. Guests (personal-link identities) are never returned.
  """
  def get_user_by_login(login) when is_binary(login) do
    case String.downcase(String.trim(login)) do
      "" ->
        nil

      q ->
        Repo.one(
          from u in User,
            as: :user,
            where: fragment("lower(?)", u.username) == ^q or fragment("lower(?)", u.email) == ^q,
            where: not exists(from l in Cab.Links.Link, where: l.user_id == parent_as(:user).id),
            limit: 1
        )
    end
  end

  def get_user_by_login(_login), do: nil

  def list_users, do: Repo.all(from u in User, order_by: u.username)

  @doc "The /account profile edit - display name only; identity fields stay provider-fed."
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
  Finds the user for an Ueberauth result. A known sign-in returns
  `{:ok, user}` with the profile refreshed from the provider. A new
  sign-in creates user + identity, unless the provider vouches for an
  e-mail address an existing account already has: then it returns
  `{:existing, user, pending}` and the person chooses between adding
  this sign-in to that account and a separate one (`create_pending/1`).
  """
  def upsert_from_oauth(%Ueberauth.Auth{} = auth) do
    pending = pending_identity(auth)

    case Repo.one(
           from i in Identity,
             where: [provider: ^pending.provider, provider_uid: ^pending.uid]
         ) do
      %Identity{user_id: user_id} ->
        get_user(user_id)
        |> User.changeset(Map.delete(pending.attrs, :username))
        |> Repo.update()

      nil ->
        case account_with_email(verified_email(auth)) do
          nil -> create_pending(pending)
          user -> {:existing, user, pending}
        end
    end
  end

  @doc "Creates the account a pending sign-in describes (see `upsert_from_oauth/1`)."
  def create_pending(%{provider: provider, uid: uid, attrs: attrs}) do
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

  defp pending_identity(auth) do
    %{
      provider: to_string(auth.provider),
      uid: to_string(auth.uid),
      attrs: %{
        # a username is shown on rosters, so never the e-mail address
        username: auth.info.nickname || slug(auth.info.name) || "member",
        name: auth.info.name,
        email: auth.info.email,
        avatar_url: auth.info.image
      }
    }
  end

  # the address only when the provider vouches for it: Google says so
  # outright; GitHub shows only verified addresses on a profile and
  # flags each address in the list it hands over
  defp verified_email(%Ueberauth.Auth{info: %{email: email}} = auth) when is_binary(email) do
    user = raw_user(auth)

    verified? =
      case to_string(auth.provider) do
        "google" ->
          user["email_verified"] in [true, "true"]

        "github" ->
          user["email"] == email or
            Enum.any?(List.wrap(user["emails"]), &(&1["email"] == email and &1["verified"]))

        _ ->
          false
      end

    if verified?, do: email
  end

  defp verified_email(_auth), do: nil

  defp raw_user(%Ueberauth.Auth{extra: %{raw_info: %{user: user}}}) when is_map(user), do: user
  defp raw_user(_auth), do: %{}

  defp account_with_email(nil), do: nil

  defp account_with_email(email) do
    Repo.one(
      from u in User,
        where: fragment("lower(?)", u.email) == ^String.downcase(email),
        order_by: [asc: u.inserted_at, asc: u.id],
        limit: 1
    )
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
  def link_identity(%User{} = user, %Ueberauth.Auth{} = auth),
    do: link_identity(user, pending_identity(auth))

  def link_identity(%User{} = user, %{provider: provider, uid: uid}) do
    case Repo.one(from i in Identity, where: [provider: ^provider, provider_uid: ^uid]) do
      %Identity{user_id: id} when id == user.id ->
        {:ok, :already}

      %Identity{user_id: other_id} ->
        {:other_account, get_user(other_id)}

      nil ->
        if Repo.exists?(
             from i in Identity, where: i.user_id == ^user.id and i.provider == ^provider
           ) do
          {:error,
           dgettext("errors", "This account already has a different %{provider} sign-in linked.",
             provider: provider
           )}
        else
          %Identity{user_id: user.id}
          |> Identity.changeset(%{provider: provider, provider_uid: uid})
          |> Repo.insert()
          |> case do
            {:ok, _} -> {:ok, :linked}
            {:error, _} -> {:error, dgettext("errors", "Could not link that sign-in. Try again.")}
          end
        end
    end
  end

  @doc "Removes a sign-in method, as long as another one is left."
  def unlink_identity(%User{} = user, provider) do
    identities = list_identities(user)

    case Enum.find(identities, &(&1.provider == provider)) do
      nil ->
        {:error, dgettext("errors", "That sign-in is not linked.")}

      _ when length(identities) < 2 ->
        {:error, dgettext("errors", "Keep at least one way to sign in.")}

      identity ->
        Repo.delete(identity)
    end
  end

  @doc """
  MERGE: two accounts of one person become one. The account that
  heads a club is kept, or else the older one, whichever was signed
  in; `{:ok, kept}` names it. The engine moves the other account's
  debate history onto the kept one (under its name) after the clubs
  that account heads change hands; cab moves its sign-in methods, club
  memberships (the stronger of two in the same club stays) and
  invitations, then deletes it. Refused, with nothing changed, when
  both took part in the same session. A merge that stopped halfway
  finishes when run again.
  """
  def merge_accounts(%User{id: id}, %User{id: id}),
    do: {:error, dgettext("errors", "That is this account.")}

  def merge_accounts(%User{} = one, %User{} = other) do
    {target, source} = keep_and_fold(one, other)
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

  @doc "The account `merge_accounts/2` keeps for these two."
  def kept_in_merge(one, other), do: one |> keep_and_fold(other) |> elem(0)

  # {kept, folded}: a head over a non-head, else the older account
  defp keep_and_fold(one, other) do
    case {heads_a_club?(one), heads_a_club?(other)} do
      {true, false} -> {one, other}
      {false, true} -> {other, one}
      _ -> if older?(other, one), do: {other, one}, else: {one, other}
    end
  end

  defp heads_a_club?(user) do
    Repo.exists?(
      from m in Cab.Clubs.Membership,
        where: m.user_id == ^user.id and m.role == "head" and m.status == "approved"
    )
  end

  defp older?(a, b) do
    case NaiveDateTime.compare(a.inserted_at, b.inserted_at) do
      :lt -> true
      :gt -> false
      :eq -> a.id < b.id
    end
  end

  defp merge_engine(_target, %User{node_user_id: nil}), do: :ok

  defp merge_engine(%User{node_user_id: target_node} = target, %User{} = source)
       when is_integer(target_node) do
    with {:ok, handed} <- hand_over_clubs(target, source) do
      case Cab.EngineApi.merge_users(
             target_node,
             source.node_user_id,
             target_node,
             target.name || target.username
           ) do
        {:ok, _} ->
          :ok

        # an earlier run got this far before stopping
        {:error, "Source user not found."} ->
          :ok

        {:error, message} ->
          take_back_clubs(target, source, handed)
          {:error, merge_message(message)}
      end
    end
  end

  defp merge_engine(_target, _source),
    do: {:error, dgettext("errors", "Something went wrong, try again.")}

  defp merge_message("Both users are registered in event" <> _),
    do:
      dgettext(
        "errors",
        "Both accounts took part in the same session. Ask the club head to remove one of them from it first."
      )

  defp merge_message("The source user holds roles" <> _),
    do:
      dgettext(
        "errors",
        "That account still holds a role in a club. Ask a platform admin to merge them."
      )

  defp merge_message(message), do: message

  # The engine merges only an account that owns no organisation, so
  # the clubs the folded account heads get the kept account as owner
  # first, and the folded account stops owning every club it belongs
  # to (a former head may still own one). Returns what changed, to
  # undo it should the merge itself be refused.
  defp hand_over_clubs(target, source) do
    memberships =
      Repo.all(
        from m in Cab.Clubs.Membership,
          join: c in assoc(m, :club),
          where: m.user_id == ^source.id and not is_nil(c.engine_organisation_id),
          select: {m.role, m.status, c.engine_organisation_id}
      )

    led = for {"head", "approved", org} <- memberships, uniq: true, do: org
    belonged = memberships |> Enum.map(&elem(&1, 2)) |> Enum.uniq()
    actor = target.node_user_id

    added =
      Enum.flat_map(led, fn org ->
        case Cab.EngineApi.add_owner(actor, org, actor) do
          {:ok, _} -> [org]
          {:error, "User is already an owner" <> _} -> []
          {:error, _} -> [{:failed, org}]
        end
      end)

    removed =
      Enum.flat_map(belonged, fn org ->
        case Cab.EngineApi.remove_owner(actor, org, source.node_user_id) do
          {:ok, _} -> [org]
          {:error, _} -> []
        end
      end)

    handed = %{added: Enum.reject(added, &match?({:failed, _}, &1)), removed: removed}

    if Enum.any?(added, &match?({:failed, _}, &1)) do
      take_back_clubs(target, source, handed)
      {:error, dgettext("errors", "Something went wrong, try again.")}
    else
      {:ok, handed}
    end
  end

  defp take_back_clubs(target, source, %{added: added, removed: removed}) do
    actor = target.node_user_id
    for org <- removed, do: Cab.EngineApi.add_owner(actor, org, source.node_user_id)
    for org <- added, do: Cab.EngineApi.remove_owner(actor, org, actor)
    :ok
  end

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
