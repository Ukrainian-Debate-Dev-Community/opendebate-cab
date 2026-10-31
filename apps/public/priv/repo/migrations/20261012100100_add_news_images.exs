defmodule Public.Repo.Migrations.AddNewsImages do
  use Ecto.Migration

  def change do
    alter table(:news_posts) do
      add :image, :string
      add :image_alt, :string
    end
  end
end
