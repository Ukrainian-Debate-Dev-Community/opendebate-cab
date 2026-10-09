defmodule Cab.Invitations.Invitation do
  use Ecto.Schema

  schema "invitations" do
    field :engine_participant_id, :integer
    field :claim_token, :string, redact: true

    belongs_to :session, Cab.Sessions.Session
    belongs_to :user, Cab.Accounts.User
    belongs_to :invited_by, Cab.Accounts.User, foreign_key: :invited_by_user_id

    timestamps(type: :utc_datetime)
  end
end
