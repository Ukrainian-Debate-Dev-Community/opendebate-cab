defmodule Public.EventRequests.Request do
  @moduledoc """
  A request from the public for an event in the calendar: the answers
  to the request form (Core.Forms), the requester's e-mail, the page's
  language for the e-mails, and the content manager's decision.
  """
  use Ecto.Schema

  @statuses ~w(pending accepted declined)

  schema "event_requests" do
    field :email, :string
    field :answers, {:array, :map}, default: []
    field :locale, :string, default: "en"
    field :status, :string, default: "pending"
    field :reason, :string
    field :decided_by_user_id, :integer
    field :decided_at, :utc_datetime
    field :event_id, :integer
    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses
end
