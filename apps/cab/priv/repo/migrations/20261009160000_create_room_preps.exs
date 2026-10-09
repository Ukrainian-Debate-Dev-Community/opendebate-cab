defmodule Cab.Repo.Migrations.CreateRoomPreps do
  use Ecto.Migration

  # the optional prep timer a room's motion starts; the engine keeps
  # the motion, cab keeps how long prep runs and since when
  def change do
    create table(:room_preps) do
      add :session_id, references(:sessions, on_delete: :delete_all), null: false
      add :room_id, :integer, null: false
      add :minutes, :integer, null: false
      add :started_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:room_preps, [:session_id, :room_id])
  end
end
