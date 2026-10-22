defmodule Cab.Registrations.Registration do
  use Ecto.Schema

  schema "registrations" do
    # the answers to the club form (Core.Forms answers, label and type
    # copied in), for this session only; seen by the club head only
    field :answers, {:array, :map}, default: []
    field :engine_participant_id, :integer

    belongs_to :user, Cab.Accounts.User
    belongs_to :session, Cab.Sessions.Session

    timestamps(type: :utc_datetime)
  end
end
