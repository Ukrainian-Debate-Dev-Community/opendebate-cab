defmodule Public.Repo.Migrations.CreateTags do
  use Ecto.Migration

  def change do
    create table(:tags) do
      add :name, :string, null: false
      add :color, :string, null: false, default: "gray"
      timestamps(type: :utc_datetime)
    end

    create unique_index(:tags, [:name])

    create table(:event_tags, primary_key: false) do
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :tag_id, references(:tags, on_delete: :delete_all), null: false
    end

    create unique_index(:event_tags, [:event_id, :tag_id])
    create index(:event_tags, [:tag_id])

    create table(:news_tags, primary_key: false) do
      add :post_id, references(:news_posts, on_delete: :delete_all), null: false
      add :tag_id, references(:tags, on_delete: :delete_all), null: false
    end

    create unique_index(:news_tags, [:post_id, :tag_id])
    create index(:news_tags, [:tag_id])
  end
end
