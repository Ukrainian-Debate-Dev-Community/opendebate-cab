defmodule Public.Roles do
  @moduledoc """
  The content-manager role, keyed by the cab account id. cab admins
  (is_admin, read from cab) may always manage the site and grant the
  role; nobody else sees that /manage exists.
  """
  import Ecto.Query

  alias Public.Repo
  alias Public.Roles.Role

  def content_manager?(nil), do: false
  def content_manager?(user_id), do: Repo.exists?(from r in Role, where: r.user_id == ^user_id)

  @doc "What a cab user may do here: :admin, :content_manager or nil."
  def access(nil), do: nil
  def access(%{is_admin: true}), do: :admin
  def access(%{id: id}), do: if(content_manager?(id), do: :content_manager)

  def list, do: Repo.all(from r in Role, order_by: r.inserted_at)

  def grant(user_id, granted_by \\ nil) do
    %Role{user_id: user_id, granted_by_user_id: granted_by}
    |> Repo.insert(on_conflict: :nothing, conflict_target: :user_id)
  end

  def revoke(user_id), do: Repo.delete_all(from r in Role, where: r.user_id == ^user_id)
end
