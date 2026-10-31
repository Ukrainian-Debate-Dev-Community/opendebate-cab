defmodule Public.Roles.Role do
  use Ecto.Schema

  # who edits the public site: a cab account id with the content-manager
  # role, kept here so cab never learns about the site
  schema "roles" do
    field :user_id, :integer
    field :role, :string, default: "content_manager"
    field :granted_by_user_id, :integer

    timestamps(type: :utc_datetime)
  end
end
