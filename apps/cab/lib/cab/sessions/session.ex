defmodule Cab.Sessions.Session do
  use Ecto.Schema
  import Ecto.Changeset

  schema "sessions" do
    field :uuid, Ecto.UUID
    # engine owns the debate data — NO stage column; stage is derived.
    # The gateway owns only the registration window: scheduled_at
    # (optional planned start) and signups_closed_at (set = closed).
    field :engine_event_id, :integer
    field :scheduled_at, :utc_datetime
    field :signups_closed_at, :utc_datetime

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
