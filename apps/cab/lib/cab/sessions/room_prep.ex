defmodule Cab.Sessions.RoomPrep do
  @moduledoc "A room's prep timer: prep runs until `ends_at`."
  use Ecto.Schema

  schema "room_preps" do
    field :room_id, :integer
    field :ends_at, :utc_datetime
    belongs_to :session, Cab.Sessions.Session

    timestamps(type: :utc_datetime)
  end
end
