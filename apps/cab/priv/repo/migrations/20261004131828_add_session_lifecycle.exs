defmodule Cab.Repo.Migrations.AddSessionLifecycle do
  use Ecto.Migration

  def change do
    alter table(:sessions) do
      # gateway-owned lifecycle flags: registration windows are gateway
      # domain; debate data stays engine-derived
      add :scheduled_at, :utc_datetime
      add :signups_closed_at, :utc_datetime
    end
  end
end
