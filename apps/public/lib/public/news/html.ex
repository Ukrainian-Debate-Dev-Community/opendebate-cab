defmodule Public.News.Html do
  @moduledoc """
  A news body is HTML, written in the manage editor and kept safe here:
  `sanitize/1` keeps only paragraphs, line breaks, h2/h3 (other levels
  become one of them), bold, italic,
  strike, links, lists, quotes, rules, this site's own uploaded
  images and galleries of them, and drops every other tag and attribute
  (no style, class, on* handlers, scripts or frames). Links go only to
  http, https, mailto or a path on this site; links that leave the site
  open in a new tab with rel="noopener nofollow ugc". Images come only
  from /uploads/.

  A gallery is `<figure class="gallery">` holding only images and at
  most one `<figcaption>` (text with inline formatting) at its end; the
  figure keeps no other class or attribute. Anything else inside it is
  dropped; a figure that is no gallery gives up its frame (its images
  stay, its caption becomes a paragraph), and so does a caption outside
  a figure.

  `text/1` and `paragraphs/1` read a body as plain text (reading time,
  card excerpts); `from_markdown/1` converts the Markdown bodies posts
  had before the editor (the one-off migration).
  """

  defmodule Scrubber do
    @moduledoc false
    use HtmlSanitizeEx

    # tags whose content is no text for the reader: dropped whole
    @dropped ~w(script style iframe frame frameset object embed applet template noscript
                textarea select option button svg math head title)

    # an uploaded file as Public.Uploads names it
    @upload ~r{\A/uploads/[A-Za-z0-9_-]+\.(jpg|png|webp)\z}

    def scrub({:comment, _children}), do: ""
    def scrub({tag, _attributes, _children}) when tag in @dropped, do: ""
    # headings keep their place in the two levels an article has
    def scrub({"h1", _attributes, children}), do: {"h2", [], children}
    def scrub({tag, _attributes, children}) when tag in ~w(h4 h5 h6), do: {"h3", [], children}

    def scrub({"a", attributes, children}) do
      case List.keyfind(attributes, "href", 0) do
        {"href", href} ->
          case link(String.trim(href)) do
            {:external, href} ->
              {"a", [{"href", href}, {"rel", "noopener nofollow ugc"}, {"target", "_blank"}],
               children}

            {:plain, href} ->
              {"a", [{"href", href}], children}

            :refused ->
              children
          end

        nil ->
          children
      end
    end

    def scrub({"img", attributes, _children}) do
      with {"src", src} <- List.keyfind(attributes, "src", 0),
           true <- Regex.match?(@upload, src) do
        alt = with {"alt", alt} <- List.keyfind(attributes, "alt", 0), do: alt
        {"img", [{"src", src}, {"alt", alt || ""}], []}
      else
        _ -> ""
      end
    end

    def scrub({"figure", attributes, children}) do
      class = with {"class", class} <- List.keyfind(attributes, "class", 0), do: class

      if is_binary(class) and "gallery" in String.split(class) do
        gallery(children)
      else
        Enum.map(children, &unframe/1)
      end
    end

    def scrub({"figcaption", _attributes, children}), do: {"figcaption", [], inline(children)}

    allow_tag_with_these_attributes("p", [])
    allow_tag_with_these_attributes("br", [])
    allow_tag_with_these_attributes("h2", [])
    allow_tag_with_these_attributes("h3", [])
    allow_tag_with_these_attributes("strong", [])
    allow_tag_with_these_attributes("b", [])
    allow_tag_with_these_attributes("em", [])
    allow_tag_with_these_attributes("i", [])
    allow_tag_with_these_attributes("s", [])
    allow_tag_with_these_attributes("ul", [])
    allow_tag_with_these_attributes("ol", [])
    allow_tag_with_these_attributes("li", [])
    allow_tag_with_these_attributes("blockquote", [])
    allow_tag_with_these_attributes("hr", [])

    # a gallery's images in order and its first caption, if it has text;
    # no images, no gallery
    defp gallery(children) do
      images = for {"img", _, _} = image <- children, do: image

      caption =
        Enum.find(children, &match?({"figcaption", _, _}, &1))
        |> case do
          {"figcaption", _, inner} = caption -> if blank?(inner), do: [], else: [caption]
          nil -> []
        end

      if images == [], do: "", else: {"figure", [{"class", "gallery"}], images ++ caption}
    end

    defp unframe({"figcaption", _, inner}), do: {"p", [], inner}
    defp unframe(node), do: node

    # a caption's content: text, bold, italic, strike, links and line
    # breaks; other tags give up their frame, images go
    @inline ~w(strong b em i s a br)

    defp inline(nodes) when is_list(nodes), do: nodes |> Enum.map(&inline/1) |> List.flatten()
    defp inline({"img", _, _}), do: []

    defp inline({tag, attributes, children}) when tag in @inline,
      do: {tag, attributes, inline(children)}

    defp inline({_tag, _attributes, children}), do: inline(children)
    defp inline(text) when is_binary(text), do: text
    defp inline(_other), do: []

    defp blank?(nodes) do
      nodes
      |> List.flatten()
      |> Enum.all?(&(is_binary(&1) and String.trim(String.replace(&1, placeholders(), "")) == ""))
    end

    # what HtmlSanitizeEx's parser puts in for whitespace between tags
    defp placeholders do
      [
        HtmlSanitizeEx.Parser.replacement_for_linebreak(),
        HtmlSanitizeEx.Parser.replacement_for_space(),
        HtmlSanitizeEx.Parser.replacement_for_tab()
      ]
      |> Enum.map(&List.to_string/1)
    end

    # http(s) and mailto by their scheme, else a path on this site
    # ("/..." but not "//host"); anything else (javascript:, data:, a
    # scheme split by spaces or entities) is refused
    defp link(href) do
      lower = String.downcase(href)

      cond do
        String.starts_with?(lower, ["http://", "https://"]) and safe?(href) -> {:external, href}
        String.starts_with?(lower, "mailto:") and safe?(href) -> {:plain, href}
        Regex.match?(~r{\A/(?![/\\])}, href) and safe?(href) -> {:plain, href}
        true -> :refused
      end
    end

    defp safe?(href), do: not Regex.match?(~r/[\s<>"]/u, href)
  end

  @doc "The body with only the allowed markup left (see the moduledoc)."
  def sanitize(nil), do: ""

  def sanitize(""), do: ""

  def sanitize(html) when is_binary(html) do
    html
    |> Scrubber.before_scrub()
    |> HtmlSanitizeEx.Parser.parse()
    |> HtmlSanitizeEx.Traverser.traverse(Scrubber)
    |> captions(nil)
    |> HtmlSanitizeEx.Parser.to_html()
    |> String.replace(~r{(\s*<p>\s*</p>)+\s*\z}, "")
    |> String.trim()
  end

  # a caption stays only right inside a figure (a gallery, by then);
  # elsewhere it becomes a paragraph
  defp captions(nodes, parent) when is_list(nodes), do: Enum.map(nodes, &captions(&1, parent))

  defp captions({"figcaption", _attributes, children}, parent) when parent != "figure",
    do: {"p", [], captions(children, "p")}

  defp captions({tag, attributes, children}, _parent),
    do: {tag, attributes, captions(children, tag)}

  defp captions(other, _parent), do: other

  @doc "A Markdown body (before the editor) as sanitised HTML, rendered as the article did."
  def from_markdown(markdown), do: markdown |> Kernel.||("") |> MDEx.to_html!() |> sanitize()

  @doc "Whether the (sanitised) body shows any image."
  def images?(html), do: is_binary(html) and String.contains?(html, "<img ")

  @doc "The body's text, its blocks apart by blank lines, tags dropped, entities read."
  def text(html), do: html |> paragraphs() |> Enum.join("\n\n")

  @doc "The text of each paragraph (or heading, list item...) of the body, in order."
  def paragraphs(nil), do: []

  def paragraphs(html) do
    html
    |> String.replace(~r{<br\s*/?>}i, " ")
    |> String.split(~r{</?(p|h[1-6]|li|blockquote|ul|ol|hr|img|figure|figcaption)\b[^>]*>}i)
    |> Enum.map(&plain/1)
    |> Enum.reject(&(&1 == ""))
  end

  @doc "The body's first paragraph as plain text, or \"\"."
  def first_paragraph(html) do
    case Regex.run(~r{<p>(.*?)</p>}s, html || "", capture: :all_but_first) do
      [inner] -> inner |> String.replace(~r{<br\s*/?>}i, " ") |> plain()
      nil -> ""
    end
  end

  defp plain(fragment) do
    fragment
    |> String.replace(~r/<[^>]*>/, "")
    |> unescape()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  @entities %{
    "amp" => "&",
    "lt" => "<",
    "gt" => ">",
    "quot" => "\"",
    "apos" => "'",
    "nbsp" => " "
  }

  defp unescape(text) do
    Regex.replace(~r/&(#x[0-9a-fA-F]+|#[0-9]+|[a-z]+);/, text, fn whole, code ->
      case code do
        "#x" <> hex -> codepoint(String.to_integer(hex, 16), whole)
        "#" <> dec -> codepoint(String.to_integer(dec), whole)
        name -> Map.get(@entities, name, whole)
      end
    end)
  end

  defp codepoint(n, whole) do
    if n in 1..0x10FFFF and n not in 0xD800..0xDFFF, do: <<n::utf8>>, else: whole
  end
end
