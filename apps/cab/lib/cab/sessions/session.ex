defmodule Cab.Sessions.Session do
  use Ecto.Schema
  import Ecto.Changeset

  schema "sessions" do
    field :uuid, Ecto.UUID
    field :short_code, :string
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
    |> put_short_code()
    |> unique_constraint(:uuid)
    |> unique_constraint(:short_code)
  end

  @alphabet ~c"abcdefghjkmnpqrstuvwxyz23456789"
  @digits ~c"23456789"

  @doc """
  A fresh short code: six characters without look-alikes (no 0/o,
  1/l/i), always holding a digit so it never spells a page address.
  """
  def generate_short_code do
    code = for _ <- 1..6, into: "", do: <<Enum.random(@alphabet)>>

    if String.contains?(code, Enum.map(@digits, &<<&1>>)),
      do: code,
      else: generate_short_code()
  end

  @doc "Whether a path segment can be a short code at all."
  def short_code?(segment) when is_binary(segment) do
    String.match?(segment, ~r/^[a-hjkmnp-z2-9]{6}$/) and String.match?(segment, ~r/[2-9]/)
  end

  def short_code?(_segment), do: false

  defp put_short_code(changeset) do
    case get_field(changeset, :short_code) do
      nil -> put_change(changeset, :short_code, generate_short_code())
      _ -> changeset
    end
  end

  defp put_uuid(changeset) do
    case get_field(changeset, :uuid) do
      nil -> put_change(changeset, :uuid, Ecto.UUID.generate())
      _ -> changeset
    end
  end
end
