defmodule Cab.Repo.Migrations.AddParticipantLimitToSessions do
  use Ecto.Migration

  # the head's cap on sign-ups (nil = no limit) and cab's record of the
  # engine's sign-up count, so lists show a full session without
  # reading the engine
  def change do
    alter table(:sessions) do
      add :max_participants, :integer
      add :signups_count, :integer, null: false, default: 0
    end

    create constraint(:sessions, :max_participants_positive, check: "max_participants > 0")
  end
end
