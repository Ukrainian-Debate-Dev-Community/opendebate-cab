defmodule Public.Events.Event do
  use Ecto.Schema
  import Ecto.Changeset

  alias Cab.Text

  @kinds ~w(tournament training club other)
  @visibilities ~w(public private)
  @languages ~w(uk en other)

  schema "events" do
    field :title, :string
    field :kind, :string, default: "tournament"
    field :starts_on, :date
    field :ends_on, :date
    field :city, :string
    field :format, :string
    field :details, :string
    field :link, :string
    # uk, en or other; language_other names it (Polish) only for other
    field :language, :string
    field :language_other, :string
    # private events exist only under /manage
    field :visibility, :string, default: "public"
    field :created_by_user_id, :integer
    # private labels, loaded only under /manage
    many_to_many :tags, Public.Tags.Tag, join_through: "event_tags", on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds
  def languages, do: @languages

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :title,
      :kind,
      :starts_on,
      :ends_on,
      :city,
      :format,
      :details,
      :link,
      :visibility,
      :language,
      :language_other
    ])
    |> Text.clean_text(:title, required: true, max: 200)
    |> Text.clean_text([:city, :format], max: 80)
    |> Text.clean_text(:link, max: 255)
    |> Text.clean_text(:language_other, max: 60)
    |> Text.clean_text(:details, max: 5000, multiline: true)
    |> validate_required([:title, :kind, :starts_on, :visibility])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:language, @languages)
    |> clear_language_other()
    |> validate_inclusion(:visibility, @visibilities)
    |> validate_format(:link, ~r{^https?://}, message: "must start with http:// or https://")
    |> validate_end()
  end

  defp clear_language_other(changeset) do
    if get_field(changeset, :language) == "other",
      do: changeset,
      else: put_change(changeset, :language_other, nil)
  end

  defp validate_end(changeset) do
    with %Date{} = from <- get_field(changeset, :starts_on),
         %Date{} = to <- get_field(changeset, :ends_on),
         :lt <- Date.compare(to, from) do
      add_error(changeset, :ends_on, "must not be before the start")
    else
      _ -> changeset
    end
  end
end
