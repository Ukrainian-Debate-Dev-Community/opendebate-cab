defmodule Public.Repo.Migrations.NewsLanguages do
  use Ecto.Migration

  # A post gets the language it is written in and its translations. The
  # posts so far are in one language each: Ukrainian when the title has
  # Cyrillic letters, English otherwise.
  def change do
    alter table(:news_posts) do
      add :lang, :string, null: false, default: "en"
      add :translations, :jsonb, null: false, default: fragment("'[]'::jsonb")
    end

    execute(
      "UPDATE news_posts SET lang = 'uk' WHERE title ~ '[\\u0400-\\u04FF]'",
      "SELECT 1"
    )
  end
end
