defmodule Cab.Repo.Migrations.AddLifecycleToSessions do
  use Ecto.Migration

  def change do
    alter table(:sessions) do
      # lifecycle facts cab itself performs, recorded as they happen so
      # lists and overviews never walk the engine: the event's name,
      # when rooms were made (and how many), when it finished, and the
      # winner copied verbatim from the engine's confirmed ballot
      add :name, :string
      add :started_at, :utc_datetime
      add :rooms_count, :integer, default: 0, null: false
      add :finished_at, :utc_datetime
      add :winner_name, :string
      add :winner_user_ids, {:array, :integer}, default: [], null: false
    end

    create index(:sessions, [:club_id, :finished_at])
  end
end
