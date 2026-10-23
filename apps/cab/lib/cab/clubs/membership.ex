defmodule Cab.Clubs.Membership do
  use Ecto.Schema
  import Ecto.Changeset
  use Gettext, backend: CabWeb.Gettext

  @roles ~w(head member)
  @statuses ~w(pending approved)
  @message_max 2000
  @contact_max 200

  schema "memberships" do
    field :role, :string
    field :status, :string
    # the join form's answers (user params by design) - the head
    # reads them in Requests before approving
    field :message, :string
    field :contact, :string
    # the answers to the club form's member fields (Core.Forms
    # answers, label and type copied in); the member's defaults for
    # session registrations, seen by the head and admins only
    field :answers, {:array, :map}, default: []

    belongs_to :user, Cab.Accounts.User
    belongs_to :club, Cab.Clubs.Club

    timestamps(type: :utc_datetime)
  end

  @doc "The join form's answers with their most characters."
  def max_lengths, do: %{message: @message_max, contact: @contact_max}

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:role, :status])
    |> validate_required([:role, :status])
    |> validate_inclusion(:role, @roles)
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:user_id, :club_id],
      message: dgettext("errors", "already a member or pending join request")
    )
  end

  @doc """
  The join-request changeset: the pending-member row with the member's
  checked answers (Core.Forms, put by the caller) and, from older
  clients, an optional free message and contact.
  """
  def join_changeset(membership, attrs, answers \\ []) do
    membership
    |> changeset(attrs)
    |> cast(attrs, [:message, :contact])
    |> Cab.Text.clean_text(:message, max: @message_max, multiline: true)
    |> Cab.Text.clean_text(:contact, max: @contact_max)
    |> put_change(:answers, answers)
  end
end
