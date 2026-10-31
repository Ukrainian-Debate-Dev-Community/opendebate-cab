defmodule Public.Repo.Migrations.AddEventLanguage do
  use Ecto.Migration

  def change do
    alter table(:events) do
      add :language, :string
      add :language_other, :string
    end
  end
end
