defmodule Cab.Repo.Migrations.CreateClubLifecycle do
  use Ecto.Migration

  def change do
    # v2 rebuild: the v1 clubs directory table is replaced wholesale
    # (v1 data lives on branch v1-mvp; dev databases are disposable).
    drop_if_exists table(:clubs)

    create table(:clubs) do
      # public id - engine integer ids stay internal
      add :uuid, :uuid, null: false
      add :name, :string, null: false
      add :city, :string
      add :engine_organisation_id, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:clubs, [:uuid])

    create table(:memberships) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :club_id, references(:clubs, on_delete: :delete_all), null: false
      # "head" | "member"; a join request IS a pending membership
      add :role, :string, null: false
      add :status, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:memberships, [:user_id, :club_id])
    create index(:memberships, [:club_id])

    create table(:sessions) do
      add :uuid, :uuid, null: false
      add :club_id, references(:clubs, on_delete: :delete_all), null: false
      # engine owns all debate data; stage is DERIVED from engine state
      add :engine_event_id, :integer, null: false
      add :opened_by_user_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:sessions, [:uuid])
    create index(:sessions, [:club_id])
  end
end
