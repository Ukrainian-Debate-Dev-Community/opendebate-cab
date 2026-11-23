defmodule PublicWeb.NewsPagesTest do
  @moduledoc """
  The news section: the newest post as the lead story over a grid of
  cards, the rubric filter, the article with its reading time and the
  posts to read next.
  """
  use PublicWeb.ConnCase

  alias Public.{News, Repo}
  alias PublicWeb.Site

  defp published(attrs, days_ago) do
    {:ok, post} = News.create(attrs, 1)
    at = DateTime.add(~U[2026-11-01 12:00:00Z], -days_ago, :day)
    post |> Ecto.Changeset.change(published_at: at) |> Repo.update!()
  end

  defp words(n), do: List.duplicate("word", n) |> Enum.join(" ")
  defp para(n), do: "<p>" <> words(n) <> "</p>"

  describe "reading time" do
    test "is the body's words at 200 a minute, rounded up, at least one" do
      assert Site.read_minutes(nil) == 1
      assert Site.read_minutes("") == 1
      assert Site.read_minutes(para(200)) == 1
      assert Site.read_minutes(para(201)) == 2
      assert Site.read_minutes(para(650)) == 4
    end

    test "counts the text of the HTML, not its tags" do
      # 200 words as text, but split by tags and attributes that would add more
      html =
        ~s(<h2>word word</h2><p><a href="https://x.org/a b c">word</a> <strong>word</strong> ) <>
          words(196) <> ~s(</p><img src="/uploads/a.png" alt="many words here" />)

      assert Site.read_minutes(html) == 1
      assert Site.read_minutes(html <> "<p>word</p>") == 2
    end

    test "reads in the page's language, one form per count" do
      assert Site.reading_time(para(650)) == "4 min read"
      assert Site.reading_time("short") == "1 min read"

      Gettext.with_locale(PublicWeb.Gettext, "uk", fn ->
        uk = Site.reading_time(para(650))
        assert uk =~ ~r/^4 \S+/u
        refute uk == "4 min read"
      end)
    end
  end

  test "a card's excerpt is the summary, else the body's first paragraph as plain text" do
    assert Site.excerpt(%{summary: "The summary.", body: "Body."}) == "The summary."

    body =
      ~s(<h2>A heading</h2><p>The <strong>first</strong> <a href="/calendar">club night</a> ) <>
        "of the season &amp; more.</p><ul><li>a list</li></ul>"

    assert Site.excerpt(%{summary: nil, body: body}) ==
             "The first club night of the season & more."

    long = Site.excerpt(%{summary: "", body: para(100)})
    assert String.length(long) <= 223
    assert String.ends_with?(long, "word...")
  end

  test "the newest post leads the list; the rest follow as cards", %{conn: conn} do
    published(%{"title" => "Older story", "rubric" => "tips"}, 5)
    published(%{"title" => "Newest story", "summary" => "The lead.", "body" => para(450)}, 1)
    published(%{"title" => "Middle story", "rubric" => "results"}, 3)

    html = conn |> get(~p"/news") |> html_response(200)

    [lead, grid] = String.split(html, ~s(class="cards"), parts: 2)
    assert lead =~ ~s(class="mcard mcard--featured news-card")
    assert lead =~ ~s(<h2 class="mcard-title"><a href="/news/newest-story">Newest story</a></h2>)
    assert lead =~ "The lead."
    assert lead =~ "3 min read"
    refute lead =~ "Middle story"

    assert grid =~ ~r/Middle story.*Older story/s
    assert length(String.split(grid, ~s(class="mcard news-card"))) == 3
  end

  test "the rubric filter shows the rubrics in use and narrows the list", %{conn: conn} do
    published(%{"title" => "A tip", "rubric" => "tips"}, 2)
    published(%{"title" => "A result", "rubric" => "results"}, 1)

    html = conn |> get(~p"/news") |> html_response(200)
    assert html =~ ~s(href="/news?rubric=tips")
    assert html =~ ~s(href="/news?rubric=results")
    refute html =~ ~s(href="/news?rubric=interviews")

    html = conn |> get(~p"/news?rubric=tips") |> html_response(200)
    assert html =~ ~s(class="on" href="/news?rubric=tips")
    assert html =~ "A tip"
    refute html =~ "A result"

    html = conn |> get(~p"/news?rubric=interviews") |> html_response(200)
    assert html =~ ~s(class="on" href="/news?rubric=interviews")
    assert html =~ "No news in this rubric yet."
    assert html =~ ~r{<a[^>]* href="/news">See all news</a>}
  end

  test "with no news at all the list says so", %{conn: conn} do
    html = conn |> get(~p"/news") |> html_response(200)
    assert html =~ "No news here yet."
    refute html =~ "mcard"
  end

  test "an article: its head, the body, a link to share and more news, same rubric first",
       %{conn: conn} do
    post =
      published(
        %{
          "title" => "Season opens",
          "rubric" => "results",
          "summary" => "Lead paragraph.",
          "body" =>
            "<h2>Rounds</h2><blockquote><p>A quote</p></blockquote>" <>
              para(390) <> ~s|<p onclick="x()">Safe<script>alert(1)</script></p>|
        },
        0
      )

    published(%{"title" => "Latest tip", "rubric" => "tips"}, -1)
    published(%{"title" => "Old result", "rubric" => "results"}, 30)
    published(%{"title" => "Another tip", "rubric" => "tips"}, 2)
    published(%{"title" => "Third tip", "rubric" => "tips"}, 3)

    html = conn |> get(~p"/news/#{post.slug}") |> html_response(200)

    assert html =~ "<h1>Season opens</h1>"
    assert html =~ ~s(<p class="article-lead">Lead paragraph.</p>)
    assert html =~ "2 min read"
    assert html =~ ~s(href="/news?rubric=results")
    assert html =~ "<h2>Rounds</h2>"
    assert html =~ "<blockquote><p>A quote</p></blockquote>"
    # sanitised when saved, shown as stored
    assert html =~ "<p>Safe</p>"
    refute html =~ "alert(1)"
    assert html =~ ~s(data-copy="#{PublicWeb.Endpoint.url()}/news/season-opens")
    # no image, no cover: the article starts with its text
    refute html =~ "article-cover"

    [_, more] = String.split(html, ~s(id="more-news"), parts: 2)
    assert more =~ ~r/Old result.*Latest tip.*Another tip/s
    refute more =~ "Third tip"
    refute more =~ "Season opens"
  end

  test "an article with images names the photo viewer and marks its body; one without does not",
       %{conn: conn} do
    with_photos =
      published(
        %{
          "title" => "Finals in photos",
          "body" =>
            "<p>Text.</p>" <>
              ~s(<figure class="gallery"><img src="/uploads/a1.jpg" alt="One" />) <>
              ~s(<img src="/uploads/b2.jpg" alt="Two" /><figcaption>The final</figcaption></figure>)
        },
        0
      )

    without = published(%{"title" => "Words only", "body" => para(20)}, 1)

    html = conn |> get(~p"/news/#{with_photos.slug}") |> html_response(200)

    assert html =~
             ~r{<meta[^>]* name="photo-viewer-src" content="/assets/js/photo-viewer.js"[^>]* data-close="Close"}

    assert html =~ ~s(data-of="of")
    assert html =~ ~s(<div class="article-body" data-photos>)

    # the gallery as stored: the collage is the stylesheet's
    assert html =~
             ~s(<figure class="gallery"><img src="/uploads/a1.jpg" alt="One" />) <>
               ~s(<img src="/uploads/b2.jpg" alt="Two" /><figcaption>The final</figcaption></figure>)

    html = conn |> get(~p"/news/#{without.slug}") |> html_response(200)
    refute html =~ "photo-viewer-src"
    refute html =~ "data-photos"
  end

  test "home shows the latest news as the same cards", %{conn: conn} do
    published(%{"title" => "Home story", "summary" => "On the home page."}, 1)

    # the newest leads the home page's news as the featured card
    html = conn |> get(~p"/") |> html_response(200)
    assert html =~ ~s(class="mcard mcard--featured news-card")
    assert html =~ "On the home page."
  end
end
