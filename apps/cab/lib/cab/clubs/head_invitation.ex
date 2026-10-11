defmodule Cab.Clubs.HeadInvitation do
  @moduledoc """
  An e-mailed invitation to head a club. Only the hash of its one-time
  token is stored; the address is kept only while it is pending.
  """
  use Ecto.Schema

  schema "head_invitations" do
    belongs_to :club, Cab.Clubs.Club
    field :email, :string
    field :name, :string
    field :token_hash, :binary
    field :invited_by_user_id, :integer
    field :interim_user_id, :integer
    field :accepted_by_user_id, :integer
    field :expires_at, :utc_datetime
    field :accepted_at, :utc_datetime
    field :cancelled_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
