defmodule Cab.Repo.Migrations.AddAnswersToMemberships do
  use Ecto.Migration

  def change do
    alter table(:memberships) do
      # the member's answers to the club form's member fields (Core.Forms
      # answers): given with the join request, edited on My page,
      # prefilled on each session registration; the head reads them.
      # They live on the membership row, so they go when it goes
      # (declined, removed)
      add :answers, {:array, :map}, null: false, default: []
    end
  end
end
