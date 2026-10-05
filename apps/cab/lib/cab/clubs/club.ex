defmodule Cab.Clubs.Club do
  use Ecto.Schema
  import Ecto.Changeset

  schema "clubs" do
    field :uuid, Ecto.UUID
    field :name, :string
    field :city, :string
    # the public profile card (P4), owner/admin editable in place
    field :meeting_info, :string
    field :description, :string
    field :contacts, :string
    # admin archive flag — set server-side, never cast
    field :archived_at, :utc_datetime
    field :engine_organisation_id, :integer

    has_many :memberships, Cab.Clubs.Membership
    has_many :sessions, Cab.Sessions.Session

    timestamps(type: :utc_datetime)
  end

  def changeset(club, attrs) do
    club
    |> cast(attrs, [:name, :city, :meeting_info, :description, :contacts])
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
