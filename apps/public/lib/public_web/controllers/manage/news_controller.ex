defmodule PublicWeb.Manage.NewsController do
  use PublicWeb, :controller

  alias Public.{News, Tags, Uploads}
  alias PublicWeb.Manage.HTML

  plug :put_view, PublicWeb.Manage.HTML

  def index(conn, params) do
    tag = Tags.find(params["tag"])

    render(conn, :news_index,
      manage_active: :news,
      page_title: gettext("News"),
      posts: News.list_all(tag),
      tags: Tags.list(),
      tag: tag
    )
  end

  def new(conn, _params), do: render_form(conn, nil, News.change())

  def create(conn, %{"post" => attrs}) do
    with {:ok, image} <- image_change(attrs),
         {:ok, post} <- News.create(attrs, conn.assigns.manager.id, image) do
      conn
      |> put_flash(:info, gettext("Saved as a draft."))
      |> redirect(to: ~p"/manage/news/#{post.id}/edit")
    else
      {:error, changeset} -> render_form(conn, nil, refused(changeset, nil, attrs), attrs)
    end
  end

  def edit(conn, %{"id" => id}) do
    post = News.get!(id)
    render_form(conn, post, News.change(post))
  end

  def update(conn, %{"id" => id, "post" => attrs}) do
    post = News.get!(id)

    with {:ok, image} <- image_change(attrs),
         {:ok, post} <- News.update(post, attrs, conn.assigns.manager.id, image) do
      conn
      |> put_flash(:info, gettext("Saved."))
      |> redirect(to: ~p"/manage/news/#{post.id}/edit")
    else
      {:error, changeset} -> render_form(conn, post, refused(changeset, post, attrs), attrs)
    end
  end

  def publish(conn, %{"id" => id}) do
    {:ok, _} = News.publish(News.get!(id), conn.assigns.manager.id)

    conn
    |> put_flash(:info, gettext("Published: everyone can read it now."))
    |> redirect(to: ~p"/manage/news")
  end

  def unpublish(conn, %{"id" => id}) do
    {:ok, _} = News.unpublish(News.get!(id), conn.assigns.manager.id)

    conn
    |> put_flash(:info, gettext("Back to draft: only content managers see it."))
    |> redirect(to: ~p"/manage/news")
  end

  @doc """
  The article as visitors will see it, from the editor's unsaved
  fields: nothing is stored. A newly chosen cover shows once saved.
  """
  def preview(conn, %{"post" => attrs} = params) do
    saved = if params["id"], do: News.get!(params["id"]), else: %News.Post{}

    post =
      saved
      |> News.change(attrs)
      |> Ecto.Changeset.apply_changes()
      |> Map.update!(:body, &Public.News.Html.sanitize/1)
      |> drop_cover(image_change(Map.delete(attrs, "image")))

    conn
    |> put_view(PublicWeb.NewsHTML)
    |> render(:show,
      active: :news,
      page_title: post.title || gettext("Preview"),
      post: post,
      body: post.body,
      photos: Public.News.Html.images?(post.body),
      more: News.related(%{post | id: post.id || 0}, 3),
      preview: true
    )
  end

  @doc """
  An image inside a post's text, from the editor: stored as a cover is
  (Public.Uploads, the same checks), answered as JSON {url} or {error}.
  The file stays even if the post is never saved with it.
  """
  def image(conn, %{"image" => %Plug.Upload{path: path}}) do
    case Uploads.store(path) do
      {:ok, name} ->
        json(conn, %{url: Uploads.url(name)})

      {:error, reason} ->
        conn
        |> put_status(if reason == :size, do: 413, else: 422)
        |> json(%{error: upload_error(reason)})
    end
  end

  def image(conn, _params) do
    conn |> put_status(422) |> json(%{error: upload_error(:type)})
  end

  # a new file goes into the uploads first; a refused one never reaches the post
  defp image_change(%{"image" => %Plug.Upload{path: path}}) do
    case Uploads.store(path) do
      {:ok, name} -> {:ok, {:new, name}}
      {:error, reason} -> {:error, {:image, upload_error(reason)}}
    end
  end

  defp image_change(%{"remove_image" => yes}) when yes in ["yes", "true"], do: {:ok, :remove}
  defp image_change(_attrs), do: {:ok, :keep}

  defp drop_cover(post, {:ok, :remove}), do: %{post | image: nil}
  defp drop_cover(post, _keep), do: post

  defp upload_error(:size), do: gettext("The image is larger than 3 MB.")
  defp upload_error(:type), do: gettext("Only JPEG, PNG or WebP images.")

  defp refused({:image, message}, post, attrs) do
    (post || %News.Post{})
    |> News.change(attrs)
    |> Ecto.Changeset.add_error(:image, message)
    |> Map.put(:action, :validate)
  end

  defp refused(%Ecto.Changeset{} = changeset, _post, _attrs), do: changeset

  defp render_form(conn, post, changeset, attrs \\ %{}) do
    render(conn, :news_form,
      manage_active: :news,
      page_title: if(post, do: post.title, else: gettext("Write news")),
      post: post,
      form: to_form(changeset, as: :post),
      tags: Tags.list(),
      selected_tags: HTML.selected_tag_ids(attrs, post),
      images: ~p"/manage/news/images",
      max_mb: div(Uploads.max_bytes(), 1024 * 1024)
    )
  end
end
