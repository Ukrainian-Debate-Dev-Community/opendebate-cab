defmodule Cab.Repo.Migrations.CreateShortLinks do
  use Ecto.Migration

  # short links become a service (Cab.ShortLinks): one row per code,
  # pointing at a cab path, an absolute URL on an allowed host, or a
  # session (resolved when opened). Every session's existing code moves
  # over unchanged - printed room cards and shared links keep working.
  def up do
    create table(:short_links) do
      add :code, :string, size: 6, null: false
      add :path, :text
      add :url, :text
      add :session_id, references(:sessions, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:short_links, [:code])
    create unique_index(:short_links, [:path], where: "path IS NOT NULL")
    create unique_index(:short_links, [:url], where: "url IS NOT NULL")
    create unique_index(:short_links, [:session_id], where: "session_id IS NOT NULL")

    create constraint(:short_links, :one_target,
             check:
               "(path IS NOT NULL)::int + (url IS NOT NULL)::int + (session_id IS NOT NULL)::int = 1"
           )

    execute """
    INSERT INTO short_links (code, session_id, inserted_at, updated_at)
    SELECT short_code, id, now() AT TIME ZONE 'utc', now() AT TIME ZONE 'utc'
    FROM sessions WHERE short_code IS NOT NULL
    """

    drop unique_index(:sessions, [:short_code])

    alter table(:sessions) do
      remove :short_code
    end
  end

  def down do
    alter table(:sessions) do
      add :short_code, :string, size: 6
    end

    execute """
    UPDATE sessions SET short_code = l.code
    FROM short_links l WHERE l.session_id = sessions.id
    """

    flush()

    %{rows: rows} = repo().query!("SELECT id FROM sessions WHERE short_code IS NULL")

    for [id] <- rows do
      repo().query!("UPDATE sessions SET short_code = $1 WHERE id = $2", [
        Core.ShortCode.generate(),
        id
      ])
    end

    alter table(:sessions) do
      modify :short_code, :string, size: 6, null: false
    end

    create unique_index(:sessions, [:short_code])

    drop table(:short_links)
  end
end
