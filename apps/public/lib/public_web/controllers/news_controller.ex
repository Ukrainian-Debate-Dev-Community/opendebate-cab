defmodule PublicWeb.NewsController do
  use PublicWeb, :controller

  alias Public.News
  alias Public.News.Post

  def index(conn, params) do
    rubric = if params["rubric"] in Post.rubrics(), do: params["rubric"]
    posts = [rubric: rubric] |> News.list_published() |> localize(conn)
    used = News.published_rubrics()

    render(conn, :index,
      active: :news,
      page_title: gettext("News"),
      rubric: rubric,
      rubrics: Enum.filter(Post.rubrics(), &(&1 in used or &1 == rubric)),
      featured: List.first(posts),
      posts: Enum.drop(posts, 1)
    )
  end

  def show(conn, %{"slug" => slug}) do
    post = News.get_published(slug) || raise PublicWeb.NotFound
    post = News.localize(post, conn.assigns.locale)

    render(conn, :show,
      active: :news,
      page_title: post.title,
      post: post,
      # sanitised when saved (Public.News.Html)
      body: post.body,
      photos: Public.News.Html.images?(post.body),
      more: post |> News.related(3) |> localize(conn)
    )
  end

  defp localize(posts, conn), do: Enum.map(posts, &News.localize(&1, conn.assigns.locale))
end
