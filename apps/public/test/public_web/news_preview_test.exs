defmodule PublicWeb.NewsPreviewTest do
  @moduledoc """
  The editor's Preview: the form's unsaved fields sent to
  /manage/news/preview (a new post) or /manage/news/:id/preview (an
  edited one) come back as the article visitors will see, under a
  preview band; nothing is stored. Content managers only.
  """
  use PublicWeb.ConnCase

  alias Public.{News, Roles}

  defp editor do
    user = cab_user(%{name: "Iryna Editor"})
    {:ok, _} = Roles.grant(user.id)
    user
  end

  test "the form has a Preview button that sends it to a new tab", %{conn: conn} do
    signed = cab_sign_in(conn, editor())

    html = signed |> get(~p"/manage/news/new") |> html_response(200)

    assert html =~
             ~r/form="news-form"\s+formaction="\/manage\/news\/preview"\s+formtarget="_blank"/

    {:ok, post} = News.create(%{"title" => "Draft"}, 1)
    html = signed |> get(~p"/manage/news/#{post.id}/edit") |> html_response(200)
    assert html =~ ~s(formaction="/manage/news/#{post.id}/preview")
  end

  test "a new post's fields show as the article, nothing saved", %{conn: conn} do
    html =
      conn
      |> cab_sign_in(editor())
      |> post(~p"/manage/news/preview", %{
        "post" => %{
          "title" => "Season opens",
          "summary" => "Twelve clubs, one cup.",
          "rubric" => "results",
          "body" => "<p>Hello <b>all</b></p><script>alert(1)</script>"
        }
      })
      |> html_response(200)

    assert html =~ ~s(class="ua-preview")
    assert html =~ "<h1>Season opens</h1>"
    assert html =~ "Twelve clubs, one cup."
    assert html =~ "<p>Hello <b>all</b></p>"
    refute html =~ "<script>alert"
    refute html =~ "ua-share"
    assert News.list_all() == []
  end

  test "an edited post shows its unsaved changes, the saved post untouched", %{conn: conn} do
    {:ok, post} = News.create(%{"title" => "Old title", "body" => "<p>Old</p>"}, 1)
    {:ok, _} = News.publish(post, 1)

    html =
      conn
      |> cab_sign_in(editor())
      |> put(~p"/manage/news/#{post.id}/preview", %{
        "post" => %{"title" => "New title", "body" => "<p>New</p>"}
      })
      |> html_response(200)

    assert html =~ "<h1>New title</h1>"
    assert html =~ "<p>New</p>"
    refute html =~ "<h1>Old title</h1>"
    # the post itself is not offered among "more news"
    refute html =~ ~s(href="/news/old-title")

    saved = News.get!(post.id)
    assert {saved.title, saved.body} == {"Old title", "<p>Old</p>"}
  end

  test "an empty title still previews", %{conn: conn} do
    html =
      conn
      |> cab_sign_in(editor())
      |> post(~p"/manage/news/preview", %{"post" => %{"title" => "", "body" => "<p>Body</p>"}})
      |> html_response(200)

    assert html =~ "<p>Body</p>"
  end

  test "the preview is no one else's: 404 without the role or signed out", %{conn: conn} do
    attrs = %{"post" => %{"title" => "Leak"}}

    assert_error_sent 404, fn ->
      conn |> cab_sign_in(cab_user()) |> post(~p"/manage/news/preview", attrs)
    end

    assert_error_sent 404, fn -> post(conn, ~p"/manage/news/preview", attrs) end
  end
end
