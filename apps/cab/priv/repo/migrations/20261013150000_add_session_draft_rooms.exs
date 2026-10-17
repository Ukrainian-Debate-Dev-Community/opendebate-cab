defmodule Cab.Repo.Migrations.AddSessionDraftRooms do
  use Ecto.Migration

  # the allocator's room count when the head sets it by hand; nil (the
  # default) = automatic, following the sign-ups
  def change do
    alter table(:sessions) do
      add :draft_rooms, :integer
    end
  end
end
