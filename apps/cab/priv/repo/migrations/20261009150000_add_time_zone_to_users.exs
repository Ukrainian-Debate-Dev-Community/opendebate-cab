defmodule Cab.Repo.Migrations.AddTimeZoneToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # the IANA zone times are shown in; nil = the device's own zone.
      # The server keeps every instant in UTC.
      add :time_zone, :string
    end
  end
end
