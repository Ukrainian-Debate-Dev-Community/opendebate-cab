defmodule Cab.Clubs.Club do
  use Ecto.Schema
  import Ecto.Changeset

  schema "clubs" do
    field :uuid, Ecto.UUID
    field :name, :string
    field :city, :string
    field :engine_organisation_id, :integer

    has_many :memberships, Cab.Clubs.Membership
    has_many :sessions, Cab.Sessions.Session

    timestamps(type: :utc_datetime)
  end

  def changeset(club, attrs) do
    club
    |> cast(attrs, [:name, :city])
    |> validate_required([:name])
    |> put_uuid()
    |> unique_constraint(:uuid)
  end

  defp put_uuid(changeset) do
    case get_field(changeset, :uuid) do
      nil -> put_change(changeset, :uuid, Ecto.UUID.generate())
      _ -> changeset
    end
  end
end
