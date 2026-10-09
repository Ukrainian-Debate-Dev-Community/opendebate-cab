defmodule Cab.Repo.Migrations.RoomPrepsEndTime do
  use Ecto.Migration

  # prep is kept as the moment it ends, which the head can move
  def change do
    alter table(:room_preps) do
      add :ends_at, :utc_datetime
      remove :minutes, :integer
      remove :started_at, :utc_datetime
    end

    execute "DELETE FROM room_preps WHERE ends_at IS NULL", ""
  end
end
