defmodule Cab.Repo.Migrations.ClubFormatAus do
  use Ecto.Migration

  # a club's "apf" meant the three-a-side format cab runs as Australs
  # (Cab.Format "aus")
  def up do
    execute "UPDATE clubs SET formats = array_replace(formats, 'apf', 'aus') WHERE 'apf' = ANY(formats)"
  end

  def down do
    execute "UPDATE clubs SET formats = array_replace(formats, 'aus', 'apf') WHERE 'aus' = ANY(formats)"
  end
end
