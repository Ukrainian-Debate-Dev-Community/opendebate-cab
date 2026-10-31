defmodule Public.Repo.Migrations.CreateSettings do
  use Ecto.Migration

  # site-wide switches only admins flip, e.g. whether the calendar is public
  def change do
    create table(:settings) do
      add :key, :string, null: false
      add :value, :string, null: false
      add :updated_by_user_id, :integer
      timestamps(type: :utc_datetime)
    end

    create unique_index(:settings, [:key])
  end
end
