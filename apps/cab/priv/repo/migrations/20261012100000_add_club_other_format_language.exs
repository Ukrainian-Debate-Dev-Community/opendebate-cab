defmodule Cab.Repo.Migrations.AddClubOtherFormatLanguage do
  use Ecto.Migration

  def change do
    alter table(:clubs) do
      add :format_other, :string
      add :language_other, :string
    end
  end
end
