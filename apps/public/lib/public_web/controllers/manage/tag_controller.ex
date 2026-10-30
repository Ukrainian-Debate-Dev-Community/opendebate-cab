defmodule PublicWeb.Manage.TagController do
  use PublicWeb, :controller

  alias Public.Tags

  plug :put_view, PublicWeb.Manage.HTML

  def index(conn, _params), do: render_index(conn, Tags.change())

  def create(conn, %{"tag" => attrs}) do
    case Tags.create(attrs) do
      {:ok, _tag} ->
        conn
        |> put_flash(:info, gettext("Tag saved."))
        |> redirect(to: ~p"/manage/tags")

      {:error, changeset} ->
        render_index(conn, changeset)
    end
  end

  def edit(conn, %{"id" => id}) do
    tag = Tags.get!(id)
    render_edit(conn, tag, Tags.change(tag))
  end

  def update(conn, %{"id" => id, "tag" => attrs}) do
    tag = Tags.get!(id)

    case Tags.update(tag, attrs) do
      {:ok, _tag} ->
        conn
        |> put_flash(:info, gettext("Tag saved."))
        |> redirect(to: ~p"/manage/tags")

      {:error, changeset} ->
        render_edit(conn, tag, changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    {:ok, _} = Tags.delete(Tags.get!(id))

    conn
    |> put_flash(:info, gettext("Tag deleted: it is gone from every event and news post."))
    |> redirect(to: ~p"/manage/tags")
  end

  defp render_index(conn, changeset) do
    render(conn, :tags,
      manage_active: :tags,
      page_title: gettext("Tags"),
      tags: Tags.list(),
      tag: nil,
      form: to_form(changeset, as: :tag)
    )
  end

  defp render_edit(conn, tag, changeset) do
    render(conn, :tags,
      manage_active: :tags,
      page_title: tag.name,
      tags: Tags.list(),
      tag: tag,
      form: to_form(changeset, as: :tag)
    )
  end
end
