defmodule Cab.Repo.Migrations.AddEngineParticipantToLinks do
  use Ecto.Migration

  # a guest is an engine participant with no engine account: the link
  # keeps which participant it is and the one-time token that hands it
  # to the person's own account when they sign up
  def change do
    alter table(:links) do
      add :engine_participant_id, :integer
      add :claim_token, :string
    end

    create index(:links, [:engine_participant_id])
  end
end
