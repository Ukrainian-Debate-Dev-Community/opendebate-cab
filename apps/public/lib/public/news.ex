defmodule Public.News do
  @moduledoc "The site's news: drafts for content managers, published posts for everyone."
  import Ecto.Query

  alias Public.News.Post
  alias Public.{Repo, Tags, Uploads}

  def list_published(opts \\ []) do
    from(p in Post, where: not is_nil(p.published_at), order_by: [desc: p.published_at])
    |> by_rubric(opts[:rubric])
    |> limit_to(opts[:limit])
    |> Repo.all()
  end

  def list_all(tag \\ nil) do
    from(p in Post,
      order_by: [desc_nulls_first: p.published_at, desc: p.updated_at],
      preload: :tags
    )
    |> Tags.only(tag, {"news_tags", :post_id})
    |> Repo.all()
  end

  def get_published(slug) do
    Repo.one(from p in Post, where: p.slug == ^slug and not is_nil(p.published_at))
  end

  def get!(id), do: Post |> Repo.get!(id) |> Repo.preload(:tags)

  def change(post \\ %Post{}, attrs \\ %{}), do: Post.changeset(post, attrs)

  @doc """
  `image` is :keep, :remove or {:new, name} for a file already in
  Public.Uploads; a replaced or removed file is deleted once the post
  is saved, a new one if it is not.
  """
  def create(attrs, user_id, image \\ :keep) do
    %Post{author_user_id: user_id, editor_user_id: user_id}
    |> Post.changeset(attrs)
    |> Tags.put(attrs)
    |> put_image(image)
    |> Repo.insert()
    |> settle_image(nil, image)
  end

  def update(%Post{} = post, attrs, user_id, image \\ :keep) do
    post
    |> Post.changeset(attrs)
    |> Tags.put(attrs)
    |> Ecto.Changeset.put_change(:editor_user_id, user_id)
    |> put_image(image)
    |> Repo.update()
    |> settle_image(post.image, image)
  end

  def publish(%Post{} = post, user_id) do
    post
    |> Ecto.Changeset.change(published_at: DateTime.utc_now(:second), editor_user_id: user_id)
    |> Repo.update()
  end

  def unpublish(%Post{} = post, user_id) do
    post
    |> Ecto.Changeset.change(published_at: nil, editor_user_id: user_id)
    |> Repo.update()
  end

  def count_drafts, do: Repo.aggregate(from(p in Post, where: is_nil(p.published_at)), :count)

  defp put_image(changeset, :keep), do: changeset
  defp put_image(changeset, :remove), do: Ecto.Changeset.put_change(changeset, :image, nil)
  defp put_image(changeset, {:new, name}), do: Ecto.Changeset.put_change(changeset, :image, name)

  defp settle_image({:ok, saved} = ok, old, _image) do
    if old && old != saved.image, do: Uploads.delete(old)
    ok
  end

  defp settle_image(error, _old, {:new, name}) do
    Uploads.delete(name)
    error
  end

  defp settle_image(error, _old, _image), do: error

  defp by_rubric(query, rubric) when rubric in [nil, ""], do: query
  defp by_rubric(query, rubric), do: from(p in query, where: p.rubric == ^rubric)

  defp limit_to(query, nil), do: query
  defp limit_to(query, n), do: from(p in query, limit: ^n)
end
