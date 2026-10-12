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
    # what the club plays, in which language and for whom; one of each
    # at most, kept as lists
    field :formats, {:array, :string}, default: []
    field :languages, {:array, :string}, default: []
    field :audiences, {:array, :string}, default: []
    # the club's own words when "other" is ticked, e.g. "Karl Popper"
    field :format_other, :string
    field :language_other, :string
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
      :audiences,
      :format_other,
      :language_other
    ])
    |> validate_required([:name])
    |> one_at_most([:formats, :languages, :audiences])
    |> validate_subset(:formats, @formats)
    |> validate_subset(:languages, @languages)
    |> validate_subset(:audiences, @audiences)
    |> other_text(:formats, :format_other)
    |> other_text(:languages, :language_other)
    |> put_uuid()
    |> unique_constraint(:uuid)
  end

  # null means none chosen; more than one is refused, as on the club page
  defp one_at_most(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, acc ->
      acc
      |> update_change(field, &(&1 || []))
      |> validate_length(field, max: 1, message: "pick one at most")
    end)
  end

  # the typed text belongs to "other": trimmed, at most 60 characters,
  # and gone when "other" is not ticked
  defp other_text(changeset, list, field) do
    if "other" in (get_field(changeset, list) || []) do
      changeset
      |> update_change(field, &(&1 && String.trim(&1)))
      |> then(&if(get_field(&1, field) == "", do: put_change(&1, field, nil), else: &1))
      |> validate_length(field, max: 60)
    else
      put_change(changeset, field, nil)
    end
  end

  defp put_uuid(changeset) do
    case get_field(changeset, :uuid) do
      nil -> put_change(changeset, :uuid, Ecto.UUID.generate())
      _ -> changeset
    end
  end
end
