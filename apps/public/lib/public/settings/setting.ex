defmodule Public.Settings.Setting do
  use Ecto.Schema

  schema "settings" do
    field :key, :string
    field :value, :string
    field :updated_by_user_id, :integer
    timestamps(type: :utc_datetime)
  end
end
