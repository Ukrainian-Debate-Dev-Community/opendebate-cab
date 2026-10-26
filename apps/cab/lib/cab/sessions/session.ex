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
    # the draft's room count set by hand; nil = automatic (see
    # Cab.Sessions.rooms_for/2)
    field :draft_rooms, :integer
    # the head's cap on sign-ups; nil = no limit (see
    # Cab.Sessions.claim_place/2). signups_count is cab's record of the
    # engine's sign-ups, for lists (Cab.Sessions.full?/1)
    field :max_participants, :integer
    field :signups_count, :integer, default: 0
    # lifecycle facts recorded when cab performs them (lists read these,
    # never the engine): see Cab.Sessions.stage_of/1
    field :name, :string
    field :started_at, :utc_datetime
    field :rooms_count, :integer, default: 0
    field :room_ids, {:array, :integer}, default: []
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
    |> validate_limit()
    |> put_uuid()
    |> unique_constraint(:uuid)
  end

  @doc "The head sets or clears the participant limit (`Cab.Sessions.set_max_participants/2`)."
  def limit_changeset(session, max_participants) do
    session
    |> change(max_participants: max_participants)
    |> validate_limit()
  end

  # the field's value, changed or not: changeset/1 casts nothing
  defp validate_limit(changeset) do
    case get_field(changeset, :max_participants) do
      max when is_integer(max) and max < 1 ->
        add_error(changeset, :max_participants, "must be greater than %{number}",
          validation: :number,
          kind: :greater_than,
          number: 0
        )

      _none_or_positive ->
        changeset
    end
    |> check_constraint(:max_participants, name: :max_participants_positive)
  end

  defp put_uuid(changeset) do
    case get_field(changeset, :uuid) do
      nil -> put_change(changeset, :uuid, Ecto.UUID.generate())
      _ -> changeset
    end
  end
end
