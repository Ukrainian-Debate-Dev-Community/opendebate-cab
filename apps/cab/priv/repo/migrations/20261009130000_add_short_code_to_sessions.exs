defmodule Cab.Repo.Migrations.AddShortCodeToSessions do
  use Ecto.Migration

  # the session's short link, cab.uadebate.com/<code>: six characters
  # from an unambiguous alphabet, always with a digit, so a code can
  # never collide with a page address
  def up do
    alter table(:sessions) do
      add :short_code, :string, size: 6
    end

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
  end

  def down do
    alter table(:sessions) do
      remove :short_code
    end
  end
end
