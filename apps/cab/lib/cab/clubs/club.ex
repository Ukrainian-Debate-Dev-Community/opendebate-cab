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
    # the club's logo: a file in Cab.Uploads, set by
    # Cab.Clubs.update_club/3, never cast; nil = no logo
    field :logo, :string
    # the guest registration form: a Core.Forms definition guests
    # answer after their name; the head edits it on its own page
    # (Cab.Clubs.edit_registration_form/2) - never cast here
    field :guest_form, {:array, :map}, default: []
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

  @name_max 120
  @city_max 80
  @meeting_info_max 300
  @description_max 5000
  @contacts_max 500
  @other_max 60

  @doc "The profile's text fields with their most characters, for the form."
  def max_lengths do
    %{
      name: @name_max,
      city: @city_max,
      meeting_info: @meeting_info_max,
      description: @description_max,
      contacts: @contacts_max,
      format_other: @other_max,
      language_other: @other_max
    }
  end

  def formats, do: @formats
  def languages, do: @languages
  def audiences, do: @audiences

  @doc """
  The guest registration form's locked fields, always asked after the
  built-in name (Core.Forms.with_locked/2 puts them in front when the
  form is read, so every club has them): the e-mail the personal link
  goes to. Guests only: members are reached through their account.
  The head may only make it optional and give it a hint.
  """
  def guest_form_locked do
    [
      %{
        "id" => "email",
        "type" => "email",
        "label" => "Your e-mail",
        "hint" => nil,
        "required" => true,
        "options" => [],
        "scope" => "guests"
      }
    ]
  end

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
    |> Cab.Text.clean_text(:name, required: true, max: @name_max)
    |> Cab.Text.clean_text(:city, max: @city_max)
    |> Cab.Text.clean_text(:meeting_info, max: @meeting_info_max, multiline: true)
    |> Cab.Text.clean_text(:description, max: @description_max, multiline: true)
    |> Cab.Text.clean_text(:contacts, max: @contacts_max, multiline: true)
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
      Cab.Text.clean_text(changeset, field, max: @other_max)
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
