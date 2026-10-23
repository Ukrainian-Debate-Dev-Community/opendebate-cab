defmodule Cab.ShortLinks.ShortLink do
  use Ecto.Schema
  import Ecto.Changeset

  # exactly one target: a cab path, an absolute URL on an allowed host,
  # or a session (resolved when the link is opened)
  schema "short_links" do
    field :code, :string
    field :path, :string
    field :url, :string
    belongs_to :session, Cab.Sessions.Session

    timestamps(type: :utc_datetime)
  end

  # all fields are server-derived; nothing is cast from params
  def changeset(link) do
    link
    |> change()
    |> validate_required([:code])
    |> unique_constraint(:code)
    |> unique_constraint(:path, name: :short_links_path_index)
    |> unique_constraint(:url, name: :short_links_url_index)
    |> unique_constraint(:session_id, name: :short_links_session_id_index)
    |> check_constraint(:path, name: :one_target)
    |> foreign_key_constraint(:session_id)
  end
end
