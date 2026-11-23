defmodule PublicWeb.NewsLanguagesTest do
  @moduledoc """
  A news post in the site's languages: the editor writes each version
  under a language switch; the one with a title first is the post's own,
  the other its translation. Visitors read their page language when the
  post has it, else the post as written, marked as such - every post is
  listed either way.
  """
  use PublicWeb.ConnCase

  alias Public.{News, Roles}
  alias Public.News.Post

  # Cyrillic as escapes: repo files stay ASCII
  @uk_title "\u041A\u0443\u0431\u043E\u043A \u043A\u043B\u0443\u0431\u0456\u0432"
  @uk_body "<p>\u0422\u0443\u0440\u043D\u0456\u0440 \u0434\u043B\u044F \u0432\u0441\u0456\u0445</p>"

  defp editor do
    user = cab_user(%{name: "Iryna Editor"})
    {:ok, _} = Roles.grant(user.id)
    user
  end

  defp i18n(en, uk), do: %{"en" => en, "uk" => uk}

  defp version(title, body \\ ""),
    do: %{"title" => title, "summary" => "", "body" => body, "image_alt" => ""}

  defp blank, do: version("")

  defp in_uk(conn), do: put_req_cookie(conn, "public_locale", "uk")

  defp publish!(attrs) do
    {:ok, post} = News.create(attrs, 1)
    {:ok, post} = News.publish(post, 1)
    post
  end

  test "the site's languages are the posts' languages" do
    assert Post.langs() == PublicWeb.Locale.locales()
  end

  test "the form switches between the versions; the other one starts hidden", %{conn: conn} do
    signed = cab_sign_in(conn, editor())
    html = signed |> get(~p"/manage/news/new") |> html_response(200)

    assert html =~ ~s(data-switch="post[edit_lang]")
    assert html =~ ~r/name="post\[edit_lang\]" value="en" checked/
    assert html =~ ~r/data-group="en">\s*<label class="q">\s*Title/
    assert html =~ ~r/data-group="uk" hidden>\s*<label class="q">\s*Title/

    post = publish!(%{"i18n" => i18n(blank(), version(@uk_title, @uk_body))})
    html = signed |> get(~p"/manage/news/#{post.id}/edit") |> html_response(200)
    assert html =~ ~r/name="post\[edit_lang\]" value="uk" checked/
    assert html =~ ~r/data-group="en" hidden>/
    assert html =~ ~s(value="#{@uk_title}")
  end

  test "both versions: the first is the post's own, the other its translation", %{conn: conn} do
    cab_sign_in(conn, editor())
    |> post(~p"/manage/news", %{
      "post" => %{
        "i18n" => i18n(version("Season opens", "<p>Hello</p>"), version(@uk_title, @uk_body))
      }
    })

    [post] = News.list_all()
    assert {post.lang, post.title, post.body} == {"en", "Season opens", "<p>Hello</p>"}
    assert [%{lang: "uk", title: @uk_title, body: @uk_body}] = post.translations
    assert post.slug == "season-opens"
  end

  test "only one version: that is the post's language, nothing translated" do
    post = publish!(%{"i18n" => i18n(blank(), version(@uk_title, @uk_body))})

    assert {post.lang, post.title, post.translations} == {"uk", @uk_title, []}
    assert post.slug == "kubok-klubiv"
  end

  test "visitors read their language when the post has it", %{conn: conn} do
    post =
      publish!(%{
        "i18n" => i18n(version("Season opens", "<p>Hello</p>"), version(@uk_title, @uk_body))
      })

    en = conn |> get(~p"/news/#{post.slug}") |> html_response(200)
    assert en =~ "<h1>Season opens</h1>"
    refute en =~ ~s(id="untranslated")

    uk = conn |> in_uk() |> get(~p"/news/#{post.slug}") |> html_response(200)
    assert uk =~ "<h1>#{@uk_title}</h1>"
    assert uk =~ @uk_body
    refute uk =~ ~s(id="untranslated")

    for path <- [~p"/news", ~p"/"] do
      assert conn |> in_uk() |> get(path) |> html_response(200) =~ @uk_title
    end
  end

  test "a post without the visitor's language is listed and shown as written, marked",
       %{conn: conn} do
    post = publish!(%{"i18n" => i18n(blank(), version(@uk_title, @uk_body))})

    list = conn |> get(~p"/news") |> html_response(200)
    assert list =~ @uk_title
    assert list =~ ~r/class="lang-tag" lang="uk">\s*UA/

    html = conn |> get(~p"/news/#{post.slug}") |> html_response(200)
    assert html =~ ~r/<article[^>]* class="article" lang="uk">/
    assert html =~ "This article has not been translated yet"
  end

  test "a version cleared is dropped; clearing the own one makes the translation the post's",
       %{conn: conn} do
    signed = cab_sign_in(conn, editor())

    post =
      publish!(%{
        "i18n" => i18n(version("Season opens", "<p>Hello</p>"), version(@uk_title, @uk_body))
      })

    put(signed, ~p"/manage/news/#{post.id}", %{
      "post" => %{"i18n" => i18n(blank(), version(@uk_title, @uk_body))}
    })

    post = News.get!(post.id)
    assert {post.lang, post.title, post.translations} == {"uk", @uk_title, []}

    put(signed, ~p"/manage/news/#{post.id}", %{
      "post" => %{
        "i18n" => i18n(version("Season opens", "<p>Hello</p>"), version(@uk_title, @uk_body))
      }
    })

    post = News.get!(post.id)
    assert {post.lang, Enum.map(post.translations, & &1.lang)} == {"uk", ["en"]}
    # the address stays as first made
    assert post.slug == "season-opens"
  end

  test "a translation without a title is refused under its own version, which opens",
       %{conn: conn} do
    html =
      conn
      |> cab_sign_in(editor())
      |> post(~p"/manage/news", %{
        "post" => %{
          "edit_lang" => "en",
          "i18n" => i18n(version("Season opens"), version("", @uk_body))
        }
      })
      |> html_response(200)

    assert html =~ ~r/class="f-block err" data-group="uk">\s*<label class="q">\s*Title/
    assert html =~ ~r/name="post\[edit_lang\]" value="uk" checked/
    assert News.list_all() == []
  end

  test "the preview shows the version being edited, the page in its language", %{conn: conn} do
    html =
      conn
      |> cab_sign_in(editor())
      |> post(~p"/manage/news/preview", %{
        "post" => %{
          "edit_lang" => "uk",
          "i18n" => i18n(version("Season opens", "<p>Hello</p>"), version(@uk_title, @uk_body))
        }
      })
      |> html_response(200)

    assert html =~ ~r/<html[^>]* lang="uk">/
    assert html =~ "<h1>#{@uk_title}</h1>"
    refute html =~ ~s(id="untranslated")
  end
end
