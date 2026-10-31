defmodule PublicWeb.NewsController do
  use PublicWeb, :controller

  alias Public.News
  alias Public.News.Post

  def index(conn, params) do
    rubric = if params["rubric"] in Post.rubrics(), do: params["rubric"]

    render(conn, :index,
      active: :news,
      page_title: gettext("News"),
      rubric: rubric,
      posts: News.list_published(rubric: rubric)
    )
  end

  def show(conn, %{"slug" => slug}) do
    post = News.get_published(slug) || raise PublicWeb.NotFound

    render(conn, :show,
      active: :news,
      page_title: post.title,
      post: post,
      body: MDEx.to_html!(post.body),
      more: News.list_published(limit: 4) |> Enum.reject(&(&1.id == post.id)) |> Enum.take(3)
    )
  end
end
