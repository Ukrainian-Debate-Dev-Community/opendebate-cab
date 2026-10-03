defmodule Cab.Clubs.Membership do
  use Ecto.Schema
  import Ecto.Changeset

  @roles ~w(head member)
  @statuses ~w(pending approved)

  schema "memberships" do
    field :role, :string
    field :status, :string

    belongs_to :user, Cab.Accounts.User
    belongs_to :club, Cab.Clubs.Club

    timestamps(type: :utc_datetime)
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:role, :status])
    |> validate_required([:role, :status])
    |> validate_inclusion(:role, @roles)
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:user_id, :club_id],
      message: "already a member or pending join request"
    )
  end
end
