defmodule Cab.Clubs do
  @moduledoc """
  Club lifecycle: clubs, memberships and join requests.

  A club is a gateway row linked 1:1 to an engine organisation
  (`engine_organisation_id`). The club head owns that organisation in
  the engine, so every privileged engine call is made as the head's
  node user. A join request IS a pending membership row; approval
  flips its status.
  """

  import Ecto.Query
  use Gettext, backend: CabWeb.Gettext

  alias Cab.Accounts
  alias Cab.Accounts.User
  alias Cab.Clubs.{Club, Membership}
  alias Cab.{EngineApi, Repo, Sessions}

  # ---------------------------------------------------------------
  # Clubs
  # ---------------------------------------------------------------

  @doc """
  Creates a club with `head` as its head: an engine organisation owned
  by the head's node user (created with the gateway's admin token) plus
  the gateway club row and the head membership.
  """
  def create_club(name, city, %User{} = head) do
    head = Accounts.ensure_node_user(head)
    changeset = Club.changeset(%Club{}, %{name: name, city: city})

    # the name is checked before the engine names an organisation after it
    with {:ok, %Club{name: name}} <- Ecto.Changeset.apply_action(changeset, :insert),
         {:ok, actor} <- require_node_user(head),
         {:ok, org} <- EngineApi.create_organisation(actor, name) do
      Repo.transaction(fn ->
        club =
          changeset
          |> Ecto.Changeset.put_change(:engine_organisation_id, org["id"])
          |> Repo.insert!()

        %Membership{user_id: head.id, club_id: club.id}
        |> Membership.changeset(%{role: "head", status: "approved"})
        |> Repo.insert!()

        club
      end)
    end
  end

  def get_by_uuid(uuid) do
    case Ecto.UUID.cast(uuid) do
      {:ok, uuid} -> Repo.get_by(Club, uuid: uuid)
      :error -> nil
    end
  end

  @doc """
  All LIVE clubs, alphabetical - the public directory and every other
  public surface. Archived clubs never appear here.
  """
  def list_clubs do
    Repo.all(from c in Club, where: is_nil(c.archived_at), order_by: c.name)
  end

  @doc "Every club, archived included - the /admin table only."
  def list_all_clubs do
    Repo.all(from c in Club, order_by: c.name)
  end

  @doc """
  The head/admin edits the club profile - gateway row only. `logo` is
  :keep, :remove or {:file, path} (an upload, checked by its bytes in
  Cab.Uploads); a refused file returns {:error, :type | :size} and
  changes nothing. A replaced or removed logo's file is deleted once
  the row is saved.
  """
  def update_club(%Club{} = club, attrs, logo \\ :keep) do
    with {:ok, new_logo} <- take_logo(logo) do
      changeset =
        club
        |> Club.changeset(attrs)
        |> then(&if(logo == :keep, do: &1, else: Ecto.Changeset.put_change(&1, :logo, new_logo)))

      # the club's name is also its engine organisation's name: a valid
      # rename reaches the engine first, so the two never drift apart
      result =
        with {:ok, _} <- Ecto.Changeset.apply_action(changeset, :update),
             {:ok, _} <- rename_in_engine(club, Ecto.Changeset.get_change(changeset, :name)) do
          Repo.update(changeset)
        end

      case result do
        {:ok, updated} ->
          if updated.logo != club.logo, do: Cab.Uploads.delete(club.logo)
          {:ok, updated}

        error ->
          Cab.Uploads.delete(new_logo)
          error
      end
    end
  end

  defp take_logo(:keep), do: {:ok, nil}
  defp take_logo(:remove), do: {:ok, nil}
  defp take_logo({:file, path}), do: Cab.Uploads.store(path)

  @doc "The club's guest registration form, its locked fields (Club.guest_form_locked/0) first."
  def guest_form(%Club{} = club),
    do: Core.Forms.with_locked(club.guest_form, Club.guest_form_locked(), Club.form_attrs())

  @doc "The registration form's fields a guest is asked (scope guests or both)."
  def guest_fields(%Club{} = club),
    do: Enum.reject(guest_form(club), &(Club.scope(&1) == "members"))

  @doc "The registration form's fields a member is asked (scope members or both)."
  def member_fields(%Club{} = club),
    do: Enum.reject(guest_form(club), &(Club.scope(&1) == "guests"))

  @doc """
  The head edits the club's guest registration form: `edit` gets the
  current `Core.Forms` definition and returns `{:ok, definition}` (then
  saved) or an error, passed through. Gateway row only.
  """
  def edit_registration_form(%Club{} = club, edit) when is_function(edit, 1) do
    with {:ok, definition} <- edit.(guest_form(club)) do
      club |> Ecto.Changeset.change(guest_form: definition) |> Repo.update()
    end
  end

  defp rename_in_engine(_club, nil), do: {:ok, :unchanged}
  defp rename_in_engine(%Club{engine_organisation_id: nil}, _name), do: {:ok, :no_engine}

  defp rename_in_engine(%Club{} = club, name) do
    with {:ok, actor} <- club_actor(club) do
      EngineApi.rename_organisation(actor, club.engine_organisation_id, name)
    end
  end

  @doc """
  Admin archives a club: the gateway `archived_at` flag only - the
  engine organisation and all debate history stay untouched. Archived
  clubs disappear from every public surface.
  """
  def archive_club(%Club{} = club) do
    club
    |> Ecto.Changeset.change(archived_at: DateTime.utc_now(:second))
    |> Repo.update()
  end

  @doc "The club's current head user, or nil."
  def head_of(%Club{} = club) do
    Repo.one(
      from u in User,
        join: m in Membership,
        on: m.user_id == u.id,
        where: m.club_id == ^club.id and m.role == "head" and m.status == "approved",
        limit: 1
    )
  end

  @doc """
  Admin hands the club to a new head: the engine organisation gains
  the new head as owner (so `club_actor/1` keeps working), the old
  head membership becomes a plain member and the new head's
  membership becomes the head row.
  """
  def change_head(%Club{} = club, %User{} = new_head) do
    new_head = Accounts.ensure_node_user(new_head)

    old_heads =
      Repo.all(
        from m in Membership,
          join: u in assoc(m, :user),
          where: m.club_id == ^club.id and m.role == "head" and u.id != ^new_head.id,
          select: u.node_user_id
      )

    with {:ok, actor} <- require_node_user(new_head),
         {:ok, _} <- add_engine_owner(actor, club.engine_organisation_id) do
      # the old head stops owning the engine organisation too, so the
      # account can later be merged; a miss only leaves a spare owner
      for old when is_integer(old) <- old_heads,
          do: EngineApi.remove_owner(actor, club.engine_organisation_id, old)

      Repo.transaction(fn ->
        from(m in Membership, where: m.club_id == ^club.id and m.role == "head")
        |> Repo.update_all(set: [role: "member"])

        case Repo.get_by(Membership, club_id: club.id, user_id: new_head.id) do
          nil ->
            %Membership{user_id: new_head.id, club_id: club.id}
            |> Membership.changeset(%{role: "head", status: "approved"})
            |> Repo.insert!()

          membership ->
            membership
            |> Membership.changeset(%{role: "head", status: "approved"})
            |> Repo.update!()
        end

        club
      end)
    end
  end

  defp add_engine_owner(actor, org) do
    case EngineApi.add_owner(actor, org, actor) do
      {:error, "User is already an owner" <> _} -> {:ok, :already}
      result -> result
    end
  end

  @doc """
  The viewer's actual role in a club: `:admin` (platform admin),
  `:owner` (head membership), `:member` (approved membership) or
  `:public`. One strict ladder - see `covers?/2`.
  """
  def role_for(%Club{}, nil), do: :public

  def role_for(%Club{} = club, %User{} = user) do
    if user.is_admin do
      :admin
    else
      case Repo.get_by(Membership, club_id: club.id, user_id: user.id) do
        %Membership{role: "head", status: "approved"} -> :owner
        %Membership{status: "approved"} -> :member
        _ -> :public
      end
    end
  end

  @doc """
  The role ladder: public -> participant/judge (session-scoped, not a
  club role) -> member -> owner -> admin. Every step keeps all pages
  and rights of the steps below it and adds its own.
  """
  @role_rank %{public: 0, member: 1, owner: 2, admin: 3}
  def covers?(role, required),
    do: Map.fetch!(@role_rank, role) >= Map.fetch!(@role_rank, required)

  @doc """
  The node user every club-scoped engine read/write-as-the-club runs
  as: the head's. Deterministic and always privileged for the club's
  organisation.
  """
  def club_actor(%Club{} = club) do
    head =
      Repo.one(
        from u in User,
          join: m in Membership,
          on: m.user_id == u.id,
          where: m.club_id == ^club.id and m.role == "head",
          limit: 1
      )

    case head && Accounts.ensure_node_user(head) do
      %User{node_user_id: id} when is_integer(id) -> {:ok, id}
      _ -> {:error, dgettext("errors", "Something went wrong, try again.")}
    end
  end

  # ---------------------------------------------------------------
  # Memberships / join requests
  # ---------------------------------------------------------------

  @doc """
  A signed-in user asks to join: a pending membership row with their
  answers to the club form's member fields (`attrs["answers"]`, keyed
  by field id) - saved as their defaults for this club - and, from
  older clients, an optional message and contact. `{:error, {:answers,
  codes}}` (field id => Core.Forms code) when an answer is refused.
  """
  def request_join(%User{} = user, %Club{} = club, attrs \\ %{}) do
    with {:ok, answers} <- check_member_answers(club, attrs) do
      %Membership{user_id: user.id, club_id: club.id}
      |> Membership.join_changeset(
        %{
          role: "member",
          status: "pending",
          message: attrs["message"] || attrs[:message],
          contact: attrs["contact"] || attrs[:contact]
        },
        answers
      )
      |> Repo.insert()
    end
  end

  @doc """
  The member changes their saved answers for the club (My page ->
  My clubs -> Edit); session registrations start from them.
  """
  def update_member_answers(%Membership{} = membership, params) do
    with {:ok, answers} <- check_member_answers(membership.club, %{"answers" => params}) do
      membership |> Ecto.Changeset.change(answers: answers) |> Repo.update()
    end
  end

  @doc "The user's membership row in the club (pending included), with the club, or nil."
  def membership_of(%Club{} = club, %User{} = user) do
    Repo.one(
      from m in Membership,
        where: m.club_id == ^club.id and m.user_id == ^user.id,
        preload: [:club]
    )
  end

  @doc """
  The options every club form's answers are checked with: the deploy's
  phone country (`:default_phone_country`), for numbers typed without
  their +code.
  """
  def answer_opts, do: [phone_region: Application.get_env(:cab, :default_phone_country)]

  defp check_member_answers(club, attrs) do
    params = attrs["answers"] || attrs[:answers]

    case Core.Forms.validate_answers(member_fields(club), params, answer_opts()) do
      {:ok, answers} -> {:ok, answers}
      {:error, codes} -> {:error, {:answers, codes}}
    end
  end

  def get_membership(id), do: Repo.get(Membership, id) |> Repo.preload([:user, :club])

  def approve_join(%Membership{status: "pending"} = membership) do
    membership |> Membership.changeset(%{status: "approved"}) |> Repo.update()
  end

  def approve_join(%Membership{}),
    do: {:error, dgettext("errors", "This join request was already answered.")}

  def decline_join(%Membership{status: "pending"} = membership), do: Repo.delete(membership)

  def decline_join(%Membership{}),
    do: {:error, dgettext("errors", "This join request was already answered.")}

  @doc """
  The head removes a member: the gateway membership row goes away
  (the engine shadow user and any past participations stay - history
  is debate data and the engine owns it). The head's own row is
  protected; removing a pending row is the same as declining it.
  """
  def remove_member(%Club{} = club, user_id) when is_integer(user_id) do
    case Repo.get_by(Membership, club_id: club.id, user_id: user_id) do
      nil ->
        {:error, dgettext("errors", "That person is not a member of this club.")}

      %Membership{role: "head"} ->
        {:error, dgettext("errors", "The club head cannot be removed.")}

      membership ->
        Repo.delete(membership)
    end
  end

  @doc "Approved memberships with users, head first."
  def list_members(%Club{} = club) do
    Repo.all(
      from m in Membership,
        join: u in assoc(m, :user),
        where: m.club_id == ^club.id and m.status == "approved",
        order_by: [desc: m.role == "head", asc: u.username],
        preload: [user: u]
    )
  end

  @doc "The user's memberships (pending ones included) with clubs, oldest first."
  def list_user_memberships(%User{} = user) do
    Repo.all(
      from m in Membership,
        where: m.user_id == ^user.id,
        order_by: m.inserted_at,
        preload: [:club]
    )
  end

  @doc "Approved-member counts for the given club ids, as `%{club_id => count}`."
  def member_counts(club_ids) do
    Repo.all(
      from m in Membership,
        where: m.club_id in ^club_ids and m.status == "approved",
        group_by: m.club_id,
        select: {m.club_id, count(m.id)}
    )
    |> Map.new()
  end

  @doc "Pending join requests with users, oldest first."
  def list_join_requests(%Club{} = club) do
    Repo.all(
      from m in Membership,
        join: u in assoc(m, :user),
        where: m.club_id == ^club.id and m.status == "pending",
        order_by: m.inserted_at,
        preload: [user: u]
    )
  end

  # ---------------------------------------------------------------
  # History
  # ---------------------------------------------------------------

  @doc """
  The club's finished sessions with their recorded winners - cab's
  own rows (the winner was copied from the engine at finish).
  """
  def club_history(%Club{} = club), do: {:ok, Sessions.archive(club)}

  defp require_node_user(%User{node_user_id: id}) when is_integer(id), do: {:ok, id}

  defp require_node_user(%User{}),
    do: {:error, dgettext("errors", "Something went wrong, try again.")}
end
