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
    # what the club plays, in which languages and for whom; any of each
    field :formats, {:array, :string}, default: []
    field :languages, {:array, :string}, default: []
    field :audiences, {:array, :string}, default: []
    # private = standings only (excluded from global standings, own
    # standings members-only); everything else stays public
    field :is_private, :boolean, default: false
    # admin archive flag - set server-side, never cast
    field :archived_at, :utc_datetime
    field :engine_organisation_id, :integer

    has_many :memberships, Cab.Clubs.Membership
    has_many :sessions, Cab.Sessions.Session

    timestamps(type: :utc_datetime)
  end

  @formats ~w(bp apf other)
  @languages ~w(uk en other)
  @audiences ~w(school university open)

  def formats, do: @formats
  def languages, do: @languages
  def audiences, do: @audiences

  def changeset(club, attrs) do
    club
    |> cast(attrs, [
      :name,
      :city,
      :meeting_info,
      :description,
      :contacts,
      :is_private,
      :formats,
      :languages,
      :audiences
    ])
    |> validate_required([:name])
    |> validate_subset(:formats, @formats)
    |> validate_subset(:languages, @languages)
    |> validate_subset(:audiences, @audiences)
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
