defmodule Cab.Repo.Migrations.CreateHeadInvitations do
  use Ecto.Migration

  def change do
    create table(:head_invitations) do
      add :club_id, references(:clubs, on_delete: :delete_all), null: false
      # kept only while the invitation is pending
      add :email, :string
      add :name, :string, null: false
      add :token_hash, :binary, null: false
      add :invited_by_user_id, references(:users, on_delete: :nilify_all)
      # the admin who heads a new club until the invitee accepts
      add :interim_user_id, references(:users, on_delete: :nilify_all)
      add :accepted_by_user_id, references(:users, on_delete: :nilify_all)
      add :expires_at, :utc_datetime, null: false
      add :accepted_at, :utc_datetime
      add :cancelled_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:head_invitations, [:token_hash])
    create index(:head_invitations, [:club_id])
  end
end
