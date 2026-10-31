defmodule Public.EventRequests.SiteForm do
  @moduledoc "A form the site asks the public: a Core.Forms definition by key."
  use Ecto.Schema

  schema "site_forms" do
    field :key, :string
    field :definition, {:array, :map}, default: []
    field :updated_by_user_id, :integer
    timestamps(type: :utc_datetime)
  end
end
