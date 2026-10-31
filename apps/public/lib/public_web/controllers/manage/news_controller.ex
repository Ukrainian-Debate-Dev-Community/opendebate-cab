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

  # a new file goes into the uploads first; a refused one never reaches the post
  defp image_change(%{"image" => %Plug.Upload{path: path}}) do
    case Uploads.store(path) do
      {:ok, name} -> {:ok, {:new, name}}
      {:error, :size} -> {:error, {:image, gettext("The image is larger than 3 MB.")}}
      {:error, :type} -> {:error, {:image, gettext("Only JPEG, PNG or WebP images.")}}
    end
  end

  defp image_change(%{"remove_image" => "true"}), do: {:ok, :remove}
  defp image_change(_attrs), do: {:ok, :keep}

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
      max_mb: div(Uploads.max_bytes(), 1024 * 1024)
    )
  end
end
