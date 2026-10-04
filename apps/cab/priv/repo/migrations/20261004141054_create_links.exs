defmodule Cab.Repo.Migrations.CreateLinks do
  use Ecto.Migration

  def change do
    create table(:links) do
      # the url-safe random code IS the credential (and, post-launch,
      # the claim token); generated server-side, never cast
      add :code, :string, null: false
      # the GUEST gateway user this link acts as
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :club_id, references(:clubs, on_delete: :delete_all), null: false
      # nullable = club-scoped links later; for now always set
      add :session_id, references(:sessions, on_delete: :delete_all)
      add :revoked_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:links, [:code])
    create index(:links, [:session_id])
    create index(:links, [:club_id])
  end
end
