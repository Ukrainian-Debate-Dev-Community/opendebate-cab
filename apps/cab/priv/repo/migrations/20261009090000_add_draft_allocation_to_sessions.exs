defmodule Cab.Repo.Migrations.AddDraftAllocationToSessions do
  use Ecto.Migration

  def change do
    alter table(:sessions) do
      # the owner's allocator draft — slot key ("1:og:2", "1:judge")
      # => engine participant id. cab's own planning state: nothing
      # reaches the engine until Start session.
      add :draft_allocation, :map, default: %{}, null: false
    end
  end
end
