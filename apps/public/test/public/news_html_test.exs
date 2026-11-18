defmodule Public.News.HtmlTest do
  @moduledoc """
  News bodies are HTML from the editor, kept to an allow-list: scripts,
  handlers, styles, foreign images and javascript: links never survive;
  the markup the editor makes does. Markdown bodies from before the
  editor convert once, as the article rendered them.
  """
  use ExUnit.Case, async: true

  alias Public.News.Html

  test "scripts, frames and their content are dropped" do
    html =
      Html.sanitize(
        "<p>Hi<script>alert(1)</script></p><iframe src=\"https://x.org\">x</iframe>" <>
          "<style>p{color:red}</style><object data=\"x\"></object>"
      )

    assert html == "<p>Hi</p>"
  end

  test "on* handlers, style and class attributes are stripped" do
    html =
      Html.sanitize(
        ~s|<p onclick="x()" style="color:red" class="big">a <strong onmouseover="y()">b</strong></p>| <>
          ~s|<img src="/uploads/abc.png" onerror="z()" style="width:1px" alt="A">|
      )

    assert html == ~s(<p>a <strong>b</strong></p><img src="/uploads/abc.png" alt="A" />)
    refute html =~ ~r/\son[a-z]+=/
  end

  test "javascript:, data: and look-alike links lose their link, keep their text" do
    for href <- [
          "javascript:alert(1)",
          "JavaScript:alert(1)",
          " javascript:alert(1)",
          "java&#115;cript:alert(1)",
          "java\tscript:alert(1)",
          "data:text/html;base64,PHNjcmlwdD4=",
          "//evil.example/x",
          "vbscript:x",
          "ftp://x.org/a"
        ] do
      assert Html.sanitize(~s(<p><a href="#{href}">click</a></p>)) == "<p>click</p>", href
    end
  end

  test "http(s) links open in a new tab with our rel; mailto and site paths stay plain" do
    assert Html.sanitize(~s(<a href="https://x.org/a?b=1&amp;c=2" target="_self" rel="me">x</a>)) ==
             ~s(<a href="https://x.org/a?b=1&amp;c=2" rel="noopener nofollow ugc" target="_blank">x</a>)

    assert Html.sanitize(~s(<a href="mailto:team@example.org">m</a>)) ==
             ~s(<a href="mailto:team@example.org">m</a>)

    assert Html.sanitize(~s(<a href="/calendar">c</a>)) == ~s(<a href="/calendar">c</a>)
  end

  test "images only from this site's uploads; others are dropped" do
    assert Html.sanitize(~s(<img src="https://evil.example/x.png" alt="x">)) == ""
    assert Html.sanitize(~s(<img src="/uploads/../secret.png">)) == ""
    assert Html.sanitize(~s(<img src="/uploads/a.gif">)) == ""
    assert Html.sanitize(~s(<img src="data:image/png;base64,AAAA">)) == ""

    assert Html.sanitize(~s(<img src="/uploads/Ab_9-x.webp" title="t">)) ==
             ~s(<img src="/uploads/Ab_9-x.webp" alt="" />)
  end

  test "the editor's markup is kept as it is" do
    html =
      "<p>One <strong>b</strong> <b>b</b> <em>i</em> <i>i</i> <s>s</s><br />two</p>" <>
        "<h2>H2</h2><h3>H3</h3><ul><li><p>a</p></li></ul><ol><li><p>b</p></li></ol>" <>
        "<blockquote><p>q</p></blockquote><hr />" <>
        ~s(<img src="/uploads/abc.jpg" alt="A picture" />)

    assert Html.sanitize(html) == html
  end

  test "other headings take one of the two levels; unknown tags leave their text" do
    assert Html.sanitize("<h1>A</h1><h4>B</h4><h6>C</h6>") == "<h2>A</h2><h3>B</h3><h3>C</h3>"
    assert Html.sanitize("<div><span>text</span> <u>u</u></div>") == "text u"
    assert Html.sanitize("<p>a</p><!-- note -->") == "<p>a</p>"
  end

  test "trailing empty paragraphs go; nil is empty" do
    assert Html.sanitize("<p>a</p><p></p><p> </p>") == "<p>a</p>"
    assert Html.sanitize(nil) == ""
  end

  test "a Markdown body converts as the article rendered it, then sanitised" do
    markdown = """
    The first **club night** of the [season](/calendar).

    ## The rounds

    - one
    - two

    > A quote.

    ---

    <script>alert(1)</script>

    Links: [bad](javascript:alert(1)) [site](https://example.org)
    """

    html = Html.from_markdown(markdown)

    assert html =~
             ~s(<p>The first <strong>club night</strong> of the <a href="/calendar">season</a>.</p>)

    assert html =~ "<h2>The rounds</h2>"
    assert html =~ ~r{<ul>\s*<li>one</li>\s*<li>two</li>\s*</ul>}
    assert html =~ ~r{<blockquote>\s*<p>A quote.</p>\s*</blockquote>}
    assert html =~ "<hr />"
    refute html =~ "script"
    refute html =~ "javascript"

    assert html =~
             ~s(<a href="https://example.org" rel="noopener nofollow ugc" target="_blank">site</a>)

    assert Html.from_markdown(nil) == ""
  end

  test "text and the first paragraph read the HTML as plain text" do
    html =
      "<h2>Head</h2><p>The <strong>first</strong> &amp; best<br />line.</p><ul><li>a</li></ul>"

    assert Html.paragraphs(html) == ["Head", "The first & best line.", "a"]
    assert Html.text(html) == "Head\n\nThe first & best line.\n\na"
    assert Html.first_paragraph(html) == "The first & best line."
    assert Html.first_paragraph("<h2>Only a heading</h2>") == ""
    assert Html.text(nil) == ""
  end
end
