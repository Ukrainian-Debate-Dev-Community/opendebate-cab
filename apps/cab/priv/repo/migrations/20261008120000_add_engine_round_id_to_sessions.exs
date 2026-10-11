defmodule Cab.Repo.Migrations.AddEngineRoundIdToSessions do
  use Ecto.Migration

  def change do
    alter table(:sessions) do
      # club sessions have exactly one engine round - stamping its id at
      # creation saves a rounds lookup on every request (old rows stay
      # nil and fall back to the lookup)
      add :engine_round_id, :integer
    end
  end
end
