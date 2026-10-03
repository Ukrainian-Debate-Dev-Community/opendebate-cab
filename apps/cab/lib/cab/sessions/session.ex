defmodule Cab.Sessions.Session do
  use Ecto.Schema
  import Ecto.Changeset

  schema "sessions" do
    field :uuid, Ecto.UUID
    # engine owns the debate data — NO stage column; stage is derived
    field :engine_event_id, :integer

    belongs_to :club, Cab.Clubs.Club
    belongs_to :opened_by_user, Cab.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [:engine_event_id])
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
