defmodule Cab.Repo.Migrations.AddRoomIdsToSessions do
  use Ecto.Migration

  def change do
    alter table(:sessions) do
      # the engine ids of the session's rooms in creation order, recorded
      # when cab makes them: room n of a short link resolves from here
      add :room_ids, {:array, :integer}, default: [], null: false
    end
  end
end
