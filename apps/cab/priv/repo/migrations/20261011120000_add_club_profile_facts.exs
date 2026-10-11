defmodule Cab.Repo.Migrations.AddClubProfileFacts do
  use Ecto.Migration

  def change do
    alter table(:clubs) do
      add :formats, {:array, :string}, null: false, default: []
      add :languages, {:array, :string}, null: false, default: []
      add :audiences, {:array, :string}, null: false, default: []
    end
  end
end
