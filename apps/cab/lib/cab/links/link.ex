defmodule Cab.Links.Link do
  use Ecto.Schema
  import Ecto.Changeset

  @code_bytes 24

  schema "links" do
    # the code IS the credential (and, post-launch, the claim token):
    # >= 24 bytes of url-safe randomness, generated server-side
    field :code, :string
    field :revoked_at, :utc_datetime

    belongs_to :user, Cab.Accounts.User
    belongs_to :club, Cab.Clubs.Club
    belongs_to :session, Cab.Sessions.Session

    timestamps(type: :utc_datetime)
  end

  # every field is server-derived; nothing is ever cast from params
  def changeset(link) do
    link
    |> change()
    |> put_code()
    |> validate_required([:code, :user_id, :club_id])
    |> unique_constraint(:code)
  end

  defp put_code(changeset) do
    case get_field(changeset, :code) do
      nil -> put_change(changeset, :code, generate_code())
      _code -> changeset
    end
  end

  def generate_code do
    @code_bytes |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end
end
