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

  describe "galleries" do
    test "a gallery from the editor is kept as it is" do
      html =
        ~s(<figure class="gallery"><img src="/uploads/a1.jpg" alt="One" />) <>
          ~s(<img src="/uploads/b2.png" alt="" /><figcaption>The <em>final</em>, <a href="/news">more</a></figcaption></figure>)

      assert Html.sanitize(html) == html

      assert Html.sanitize(~s(<figure class="gallery"><img src="/uploads/a1.webp"></figure>)) ==
               ~s(<figure class="gallery"><img src="/uploads/a1.webp" alt="" /></figure>)
    end

    test "the figure keeps only class gallery; other classes and attributes go" do
      assert Html.sanitize(
               ~s|<figure class="wide gallery big" id="g" style="color:red" onclick="x()" data-x="1">| <>
                 ~s(<img src="/uploads/a1.jpg" alt="A"></figure>)
             ) == ~s(<figure class="gallery"><img src="/uploads/a1.jpg" alt="A" /></figure>)
    end

    test "a figure that is no gallery loses its frame; its caption becomes a paragraph" do
      assert Html.sanitize(
               ~s(<figure class="other"><img src="/uploads/a1.jpg" alt="A"><figcaption>Cap</figcaption></figure>)
             ) == ~s(<img src="/uploads/a1.jpg" alt="A" /><p>Cap</p>)

      assert Html.sanitize(
               ~s(<p>x</p><figcaption>stray</figcaption><ul><li><figcaption>y</figcaption></li></ul>)
             ) ==
               "<p>x</p><p>stray</p><ul><li><p>y</p></li></ul>"
    end

    test "foreign images in a gallery are dropped; without images there is no gallery" do
      assert Html.sanitize(
               ~s(<figure class="gallery"><img src="https://evil.example/x.jpg" alt="X">) <>
                 ~s(<img src="/uploads/a1.jpg" alt="A"><img src="/uploads/../x.jpg"></figure>)
             ) == ~s(<figure class="gallery"><img src="/uploads/a1.jpg" alt="A" /></figure>)

      assert Html.sanitize(
               ~s(<figure class="gallery"><img src="data:image/png;base64,AAAA"><figcaption>Only</figcaption></figure><p>after</p>)
             ) == "<p>after</p>"
    end

    test "nested junk in a gallery is stripped: only its direct images and one caption stay" do
      html =
        Html.sanitize(
          ~s(<figure class="gallery">\n  <img src="/uploads/a1.jpg" alt="A">\n  <p>text<img src="/uploads/b2.jpg"></p>) <>
            ~s(<figure class="gallery"><img src="/uploads/c3.jpg"></figure><div>d</div><ul><li>e</li></ul>) <>
            ~s(<img src="/uploads/d4.jpg" alt="D"><figcaption>One</figcaption><figcaption>Two</figcaption></figure>)
        )

      assert html ==
               ~s(<figure class="gallery"><img src="/uploads/a1.jpg" alt="A" /><img src="/uploads/d4.jpg" alt="D" />) <>
                 ~s(<figcaption>One</figcaption></figure>)
    end

    test "a caption keeps inline formatting only; scripts, blocks and images in it go" do
      html =
        Html.sanitize(
          ~s|<figure class="gallery"><img src="/uploads/a1.jpg" alt="A"><figcaption onclick="x()">| <>
            ~s|<strong>Bold</strong> <script>alert(1)</script><h2>head</h2><img src="/uploads/b2.jpg">| <>
            ~s|<a href="javascript:alert(1)">link</a></figcaption></figure>|
        )

      assert html ==
               ~s(<figure class="gallery"><img src="/uploads/a1.jpg" alt="A" />) <>
                 ~s(<figcaption><strong>Bold</strong> headlink</figcaption></figure>)

      assert Html.sanitize(
               ~s(<figure class="gallery"><img src="/uploads/a1.jpg"><figcaption> <script>x</script> </figcaption></figure>)
             ) == ~s(<figure class="gallery"><img src="/uploads/a1.jpg" alt="" /></figure>)
    end

    test "a caption reads as text; images? sees galleries and single images" do
      html =
        ~s(<p>a</p><figure class="gallery"><img src="/uploads/a1.jpg" alt="" /><figcaption>cap</figcaption></figure>)

      assert Html.paragraphs(html) == ["a", "cap"]
      assert Html.images?(html)
      assert Html.images?(~s(<img src="/uploads/a1.jpg" alt="" />))
      refute Html.images?("<p>no images</p>")
      refute Html.images?(nil)
    end
  end
end
