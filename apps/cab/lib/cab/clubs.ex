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

    with {:ok, actor} <- require_node_user(head),
         {:ok, org} <- EngineApi.create_organisation(actor, name) do
      Repo.transaction(fn ->
        club =
          %Club{engine_organisation_id: org["id"]}
          |> Club.changeset(%{name: name, city: city})
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
  The viewer's actual role in a club: `:owner` (head membership),
  `:member` (approved membership) or `:public`.
  """
  def role_for(%Club{}, nil), do: :public

  def role_for(%Club{} = club, %User{} = user) do
    case Repo.get_by(Membership, club_id: club.id, user_id: user.id) do
      %Membership{role: "head", status: "approved"} -> :owner
      %Membership{status: "approved"} -> :member
      _ -> :public
    end
  end

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
      _ -> {:error, "club head has no engine counterpart"}
    end
  end

  # ---------------------------------------------------------------
  # Memberships / join requests
  # ---------------------------------------------------------------

  @doc "A signed-in user asks to join: a pending membership row."
  def request_join(%User{} = user, %Club{} = club) do
    %Membership{user_id: user.id, club_id: club.id}
    |> Membership.changeset(%{role: "member", status: "pending"})
    |> Repo.insert()
  end

  def get_membership(id), do: Repo.get(Membership, id) |> Repo.preload([:user, :club])

  def approve_join(%Membership{status: "pending"} = membership) do
    membership |> Membership.changeset(%{status: "approved"}) |> Repo.update()
  end

  def approve_join(%Membership{}), do: {:error, "join request is not pending"}

  def decline_join(%Membership{status: "pending"} = membership), do: Repo.delete(membership)
  def decline_join(%Membership{}), do: {:error, "join request is not pending"}

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
  Completed engine events of the club's organisation, each annotated
  with `"winner"` (winning team of the event's single round).
  """
  def club_history(%Club{} = club) do
    with {:ok, actor} <- club_actor(club),
         {:ok, events} <- EngineApi.list_organisation_events(actor, club.engine_organisation_id) do
      history =
        events
        |> Enum.filter(&(&1["status"] == "completed"))
        |> Enum.map(&Map.put(&1, "winner", Sessions.event_winner(actor, &1)))

      {:ok, history}
    end
  end

  defp require_node_user(%User{node_user_id: id}) when is_integer(id), do: {:ok, id}
  defp require_node_user(%User{}), do: {:error, "engine user could not be provisioned"}
end
