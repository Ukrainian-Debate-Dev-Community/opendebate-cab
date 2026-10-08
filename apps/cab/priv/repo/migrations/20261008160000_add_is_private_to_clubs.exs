defmodule Cab.Repo.Migrations.AddIsPrivateToClubs do
  use Ecto.Migration

  def change do
    alter table(:clubs) do
      # private = standings only: the club stays public everywhere,
      # but it never feeds the global standings and its own standings
      # are members-only (guests keep their own session)
      add :is_private, :boolean, default: false, null: false
    end
  end
end
