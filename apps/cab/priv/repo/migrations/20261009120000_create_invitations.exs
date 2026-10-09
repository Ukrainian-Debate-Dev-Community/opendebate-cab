defmodule Cab.Repo.Migrations.CreateInvitations do
  use Ecto.Migration

  def change do
    # the head adds a registered non-member to a session at once; the
    # engine participant has no user until they accept (with the
    # engine's one-time claim token), which they may do any time
    create table(:invitations) do
      add :session_id, references(:sessions, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :invited_by_user_id, references(:users, on_delete: :nilify_all)
      add :engine_participant_id, :integer, null: false
      add :claim_token, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:invitations, [:session_id, :user_id])
    create index(:invitations, [:user_id])
  end
end
