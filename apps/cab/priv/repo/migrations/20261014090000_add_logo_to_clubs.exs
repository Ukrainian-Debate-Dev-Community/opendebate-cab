defmodule Cab.Repo.Migrations.AddLogoToClubs do
  use Ecto.Migration

  # the stored file's name in the uploads folder (Cab.Uploads); null = no logo
  def change do
    alter table(:clubs) do
      add :logo, :string
    end
  end
end
