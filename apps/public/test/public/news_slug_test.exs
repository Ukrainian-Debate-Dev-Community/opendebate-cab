defmodule Public.NewsSlugTest do
  @moduledoc """
  News slugs: Ukrainian titles romanised by the official table (KMU 2010),
  so a Ukrainian-only title gets a readable slug instead of none.
  """
  use PublicWeb.ConnCase

  alias Public.News
  alias Public.News.Post

  # Cyrillic as escapes: repo files stay ASCII
  @kyiv "\u041A\u0438\u0457\u0432, \u0425\u0430\u0440\u043A\u0456\u0432 \u0456 \u041B\u044C\u0432\u0456\u0432"
  @cup "\u041A\u0443\u0431\u043E\u043A \u043A\u043B\u0443\u0431\u0456\u0432: \u0440\u0435\u0454\u0441\u0442\u0440\u0430\u0446\u0456\u044E \u0432\u0456\u0434\u043A\u0440\u0438\u0442\u043E"
  # word starts: Yevhen, Yizhak, Yosyp, Yuliia, Yaroslav; then Gorgany, Zghurivka
  @starts "\u0404\u0432\u0433\u0435\u043D \u0407\u0436\u0430\u043A \u0419\u043E\u0441\u0438\u043F \u042E\u043B\u0456\u044F \u042F\u0440\u043E\u0441\u043B\u0430\u0432"
  @g_zgh "\u0490\u043E\u0440\u0491\u0430\u043D\u0438 \u0417\u0433\u0443\u0440\u0456\u0432\u043A\u0430"
  # an apostrophe drops and does not start a word: Znamianka, Podviria
  @apostrophes "\u0417\u043D\u0430\u043C'\u044F\u043D\u043A\u0430 \u041F\u043E\u0434\u0432\u0456\u0440\u2019\u044F"
  @school "\u0428\u043A\u043E\u043B\u0430 \u0449\u0443\u043A\u0438 \u0446\u0435 \u0445\u0430\u0442\u0430"

  test "Ukrainian titles follow the official romanisation" do
    assert Post.slugify(@kyiv) == "kyiv-kharkiv-i-lviv"
    assert Post.slugify(@cup) == "kubok-klubiv-reiestratsiiu-vidkryto"
    assert Post.slugify(@starts) == "yevhen-yizhak-yosyp-yuliia-yaroslav"
    assert Post.slugify(@g_zgh) == "gorgany-zghurivka"
    assert Post.slugify(@apostrophes) == "znamianka-podviria"
    assert Post.slugify(@school) == "shkola-shchuky-tse-khata"
  end

  test "Latin titles keep their words, accents dropped" do
    assert Post.slugify("Autumn Open 2026: the Final!") == "autumn-open-2026-the-final"
    assert Post.slugify("Caf\u00E9 d\u00E9bat") == "cafe-debat"
    assert Post.slugify("  --  ") == ""
  end

  test "a long title is cut to whole words" do
    slug = Post.slugify(String.duplicate("\u0449\u0443\u043A\u0430 ", 60))
    assert byte_size(slug) <= 100
    assert slug =~ ~r/^(shchuka-)+shchuka$/

    assert Post.slugify(String.duplicate("a", 150)) == String.duplicate("a", 100)
  end

  test "a Ukrainian-only title saves with its slug" do
    assert {:ok, post} = News.create(%{"title" => @cup}, 1)
    assert post.slug == "kubok-klubiv-reiestratsiiu-vidkryto"
  end
end
