defmodule Cab.Repo.Migrations.CreateRegistrations do
  use Ecto.Migration

  def change do
    # a signed-in person's answers to the club form for one session
    # (guests keep theirs on their personal link); the head reads them
    # in Responses. Gone with the session, the account, or the signup
    create table(:registrations) do
      add :session_id, references(:sessions, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :engine_participant_id, :integer
      add :answers, {:array, :map}, null: false, default: []

      timestamps(type: :utc_datetime)
    end

    create unique_index(:registrations, [:session_id, :user_id])
  end
end
