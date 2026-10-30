defmodule Public.Repo.Migrations.CreateSiteTables do
  use Ecto.Migration

  def change do
    create table(:news_posts) do
      add :title, :string, null: false
      add :slug, :string, null: false
      add :rubric, :string, null: false, default: "community"
      add :summary, :text
      add :body, :text, null: false, default: ""
      add :published_at, :utc_datetime
      add :author_user_id, :integer
      add :editor_user_id, :integer
      timestamps(type: :utc_datetime)
    end

    create unique_index(:news_posts, [:slug])
    create index(:news_posts, [:published_at])

    create table(:events) do
      add :title, :string, null: false
      add :kind, :string, null: false, default: "tournament"
      add :starts_on, :date, null: false
      add :ends_on, :date
      add :city, :string
      add :format, :string
      add :details, :text
      add :link, :string
      add :visibility, :string, null: false, default: "public"
      add :created_by_user_id, :integer
      timestamps(type: :utc_datetime)
    end

    create index(:events, [:starts_on])

    create table(:roles) do
      add :user_id, :integer, null: false
      add :role, :string, null: false, default: "content_manager"
      add :granted_by_user_id, :integer
      timestamps(type: :utc_datetime)
    end

    create unique_index(:roles, [:user_id])
  end
end
