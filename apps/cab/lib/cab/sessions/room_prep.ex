defmodule Cab.Sessions.RoomPrep do
  @moduledoc "A room's optional prep timer: `minutes` from `started_at`."
  use Ecto.Schema

  schema "room_preps" do
    field :room_id, :integer
    field :minutes, :integer
    field :started_at, :utc_datetime
    belongs_to :session, Cab.Sessions.Session

    timestamps(type: :utc_datetime)
  end
end
