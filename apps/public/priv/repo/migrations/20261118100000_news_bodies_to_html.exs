defmodule Public.Repo.Migrations.NewsBodiesToHtml do
  use Ecto.Migration

  import Ecto.Query

  # News bodies were Markdown, rendered when an article was shown; the
  # editor writes HTML. Every body is converted once, rendered as the
  # article rendered it and sanitised as the editor's saves are
  # (Public.News.Html.from_markdown/1). There is no way back: the old
  # code would show the HTML as Markdown.
  def up do
    flush()

    for {id, body} <- repo().all(from p in "news_posts", select: {p.id, p.body}) do
      html = Public.News.Html.from_markdown(body)

      repo().update_all(from(p in "news_posts", where: p.id == ^id), set: [body: html])
    end
  end

  def down, do: raise(Ecto.MigrationError, "news bodies stay HTML")
end
