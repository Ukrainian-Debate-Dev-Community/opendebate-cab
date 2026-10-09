defmodule Cab.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :username, :string
    field :name, :string
    field :email, :string
    field :avatar_url, :string
    field :is_admin, :boolean, default: false
    field :node_user_id, :integer
    # set per request: a personal-link identity, not an account
    field :guest, :boolean, virtual: true, default: false

    has_many :identities, Cab.Accounts.Identity

    timestamps(type: :utc_datetime)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :name, :email, :avatar_url])
    |> validate_required([:username])
    |> unique_constraint(:username)
  end

  # node_user_id links to the engine and is only ever set by the server
  def node_changeset(user, node_user_id) do
    user
    |> Ecto.Changeset.change(node_user_id: node_user_id)
    |> unique_constraint(:node_user_id)
  end
end
