defmodule Public.Repo.Migrations.CreateEventRequests do
  use Ecto.Migration

  def change do
    # forms the site asks the public (Core.Forms definitions), by key
    create table(:site_forms) do
      add :key, :string, null: false
      add :definition, {:array, :map}, null: false, default: []
      add :updated_by_user_id, :integer
      timestamps(type: :utc_datetime)
    end

    create unique_index(:site_forms, [:key])

    # the public's requests for an event in the calendar
    create table(:event_requests) do
      add :email, :string, null: false
      add :answers, {:array, :map}, null: false, default: []
      add :locale, :string, null: false, default: "en"
      add :status, :string, null: false, default: "pending"
      add :reason, :text
      add :decided_by_user_id, :integer
      add :decided_at, :utc_datetime
      add :event_id, references(:events, on_delete: :nilify_all)
      timestamps(type: :utc_datetime)
    end

    create index(:event_requests, [:status, :inserted_at])
  end
end
