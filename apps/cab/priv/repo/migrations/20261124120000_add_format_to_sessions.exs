defmodule Cab.Repo.Migrations.AddFormatToSessions do
  use Ecto.Migration

  # the debate format a session runs (Cab.Format): every session so far
  # was British Parliamentary
  def change do
    alter table(:sessions) do
      add :format, :string, null: false, default: "bp"
    end

    create constraint(:sessions, :format_known, check: "format IN ('bp', 'aus')")
  end
end
