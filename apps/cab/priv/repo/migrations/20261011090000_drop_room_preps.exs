defmodule Cab.Repo.Migrations.DropRoomPreps do
  use Ecto.Migration

  # the engine keeps when a room's prep ends (rooms.prep_ends_at); cab
  # keeps no debating data of its own
  def up do
    drop table(:room_preps)
  end

  def down do
    create table(:room_preps) do
      add :session_id, references(:sessions, on_delete: :delete_all), null: false
      add :room_id, :integer, null: false
      add :ends_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:room_preps, [:session_id, :room_id])
  end
end
