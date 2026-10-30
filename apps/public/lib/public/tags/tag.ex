defmodule Public.Tags.Tag do
  use Ecto.Schema
  import Ecto.Changeset

  # a fixed palette; each colour is a pair of CSS tokens for light and dark
  @colors ~w(gray red orange yellow green teal blue purple)

  schema "tags" do
    field :name, :string
    field :color, :string, default: "gray"

    timestamps(type: :utc_datetime)
  end

  def colors, do: @colors

  def changeset(tag, attrs) do
    tag
    |> cast(attrs, [:name, :color])
    |> Cab.Text.clean_text(:name, required: true, max: 40)
    |> validate_required([:color])
    |> validate_inclusion(:color, @colors)
    |> unique_constraint(:name)
  end
end
