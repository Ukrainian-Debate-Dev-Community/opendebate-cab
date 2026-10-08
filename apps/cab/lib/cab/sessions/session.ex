defmodule Cab.Sessions.Session do
  use Ecto.Schema
  import Ecto.Changeset

  schema "sessions" do
    field :uuid, Ecto.UUID
    # engine owns the debate data; the gateway owns the registration
    # window (scheduled_at, signups_closed_at) and the lifecycle facts
    # it performs itself (below).
    field :engine_event_id, :integer
    field :engine_round_id, :integer
    field :scheduled_at, :utc_datetime
    field :signups_closed_at, :utc_datetime
    # the allocator draft: slot key => participant id (see Cab.Sessions.place/3)
    field :draft_allocation, :map, default: %{}
    # lifecycle facts recorded when cab performs them (lists read these,
    # never the engine): see Cab.Sessions.stage_of/1
    field :name, :string
    field :started_at, :utc_datetime
    field :rooms_count, :integer, default: 0
    field :finished_at, :utc_datetime
    field :winner_name, :string
    field :winner_user_ids, {:array, :integer}, default: []

    belongs_to :club, Cab.Clubs.Club
    belongs_to :opened_by_user, Cab.Accounts.User

    timestamps(type: :utc_datetime)
  end

  # all fields are server-derived; nothing is cast from params
  def changeset(session) do
    session
    |> change()
    |> validate_required([:engine_event_id])
    |> put_uuid()
    |> unique_constraint(:uuid)
  end

  defp put_uuid(changeset) do
    case get_field(changeset, :uuid) do
      nil -> put_change(changeset, :uuid, Ecto.UUID.generate())
      _ -> changeset
    end
  end
end
