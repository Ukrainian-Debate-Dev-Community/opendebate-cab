defmodule Public.News.Post do
  use Ecto.Schema
  import Ecto.Changeset

  alias Cab.Text

  @rubrics ~w(announcements results interviews tips community)
  # the site's languages (PublicWeb.Locale.locales/0)
  @langs ~w(en uk)
  # the fields a post has in each of its languages
  @texts ~w(title summary body image_alt)

  schema "news_posts" do
    field :title, :string
    field :slug, :string
    field :rubric, :string, default: "community"
    field :summary, :string
    # HTML from the editor, kept to Public.News.Html's allow-list
    field :body, :string, default: ""
    # nil while the post is a draft
    field :published_at, :utc_datetime
    # cab account ids, read downward; never a foreign key into cab
    field :author_user_id, :integer
    field :editor_user_id, :integer
    # a file name in Public.Uploads; nil shows a drawing
    field :image, :string
    field :image_alt, :string
    # the language the fields above are in: the post's first version,
    # or, on a post from News.localize/2, the language it is shown in
    field :lang, :string, default: "en"
    # the post in the other site languages, each optional
    embeds_many :translations, Public.News.Translation, on_replace: :delete
    # private labels, loaded only under /manage
    many_to_many :tags, Public.Tags.Tag,
      join_through: "news_tags",
      join_keys: [post_id: :id, tag_id: :id],
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  def rubrics, do: @rubrics
  def langs, do: @langs

  @doc """
  The editor's fields arrive per language, `i18n: %{lang => %{title,
  summary, body, image_alt}}`: the version with a title becomes the
  post's own fields (the one it had first, when both have one), the
  other filled one its translation, an empty one is dropped.
  """
  def changeset(post, attrs) do
    post
    |> cast(from_i18n(attrs, post), [:title, :slug, :rubric, :summary, :body, :image_alt, :lang])
    |> clean_texts()
    |> Text.clean_text(:slug, max: 200)
    |> cast_embed(:translations, with: &Public.News.Translation.changeset/2)
    |> update_change(:slug, &slugify/1)
    |> put_slug()
    |> validate_required([:title, :slug, :rubric])
    |> validate_inclusion(:rubric, @rubrics)
    |> validate_inclusion(:lang, @langs)
    |> validate_format(:slug, ~r/^[a-z0-9]+(-[a-z0-9]+)*$/)
    |> unique_constraint(:slug)
  end

  @doc "A post's language versions' text fields cleaned, the body to the HTML allow-list (shared with Translation)."
  def clean_texts(changeset) do
    changeset
    |> Text.clean_text(:title, required: true, max: 200)
    |> Text.clean_text(:image_alt, max: 200)
    |> Text.clean_text(:summary, max: 1000, multiline: true)
    |> Text.clean_text(:body, max: 100_000, multiline: true)
    |> update_change(:body, &Public.News.Html.sanitize/1)
    |> then(&if(get_field(&1, :body), do: &1, else: put_change(&1, :body, "")))
  end

  @doc "The editor's fields per language, the post's own and its translations': %{lang => %{field => value}}."
  def i18n(%__MODULE__{} = post) do
    own = {post.lang, Map.new(@texts, &{&1, Map.get(post, String.to_existing_atom(&1))})}

    translated =
      for t <- post.translations,
          do: {t.lang, Map.new(@texts, &{&1, Map.get(t, String.to_existing_atom(&1))})}

    Map.new(for(lang <- @langs, do: {lang, %{}}) ++ translated ++ [own])
  end

  defp from_i18n(%{"i18n" => %{} = i18n} = attrs, post) do
    filled = for lang <- @langs, filled?(i18n[lang]), do: lang
    lang = first_lang(filled, post.lang, attrs["edit_lang"])

    attrs
    |> Map.merge(Map.take(i18n[lang] || %{}, @texts))
    |> Map.put("lang", lang)
    |> Map.put("translations", for(l <- filled, l != lang, do: Map.put(i18n[l], "lang", l)))
  end

  defp from_i18n(attrs, _post), do: attrs

  # the post's own language while it still has text, else the first filled
  # one, else (nothing written yet) the one being edited
  defp first_lang(filled, own, editing) do
    cond do
      own in filled -> own
      filled != [] -> hd(filled)
      editing in @langs -> editing
      true -> own
    end
  end

  defp filled?(%{} = fields) do
    Enum.any?(~w(title summary image_alt), &(String.trim(fields[&1] || "") != "")) or
      String.trim(Public.News.Html.text(fields["body"] || "")) != ""
  end

  defp filled?(_fields), do: false

  defp put_slug(changeset) do
    case get_field(changeset, :slug) do
      blank when blank in [nil, ""] ->
        put_change(changeset, :slug, slugify(get_field(changeset, :title)))

      _ ->
        changeset
    end
  end

  # Cyrillic letters by the KMU 2010 romanisation table: lowercase
  # Cyrillic codepoints, with the forms they take at a word's start
  @latin %{
    0x0430 => "a",
    0x0431 => "b",
    0x0432 => "v",
    0x0433 => "h",
    0x0491 => "g",
    0x0434 => "d",
    0x0435 => "e",
    0x0454 => "ie",
    0x0436 => "zh",
    0x0437 => "z",
    0x0438 => "y",
    0x0456 => "i",
    0x0457 => "i",
    0x0439 => "i",
    0x043A => "k",
    0x043B => "l",
    0x043C => "m",
    0x043D => "n",
    0x043E => "o",
    0x043F => "p",
    0x0440 => "r",
    0x0441 => "s",
    0x0442 => "t",
    0x0443 => "u",
    0x0444 => "f",
    0x0445 => "kh",
    0x0446 => "ts",
    0x0447 => "ch",
    0x0448 => "sh",
    0x0449 => "shch",
    0x044C => "",
    0x044E => "iu",
    0x044F => "ia"
  }
  @initial %{0x0454 => "ye", 0x0457 => "yi", 0x0439 => "y", 0x044E => "yu", 0x044F => "ya"}
  @apostrophes [?', ?`, 0x02BC, 0x2019]
  @slug_max 100

  @doc "A URL slug from free text: Cyrillic romanised (KMU 2010), lowercase ASCII words joined by dashes, at most #{@slug_max} characters."
  def slugify(nil), do: nil

  def slugify(text) do
    text
    |> String.downcase()
    |> String.to_charlist()
    |> romanise(true, [])
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> cut()
  end

  defp romanise([], _start, acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()
  defp romanise([c | rest], start, acc) when c in @apostrophes, do: romanise(rest, start, acc)
  # "zgh" keeps the pair apart from "zh"
  defp romanise([0x0437, 0x0433 | rest], _start, acc), do: romanise(rest, false, ["zgh" | acc])

  defp romanise([c | rest], start, acc) do
    out = (start && @initial[c]) || @latin[c] || <<c::utf8>>
    romanise(rest, not String.match?(<<c::utf8>>, ~r/^\p{L}$/u), [out | acc])
  end

  # a long title keeps its whole first words
  defp cut(slug) when byte_size(slug) <= @slug_max, do: slug

  defp cut(slug) do
    head = binary_part(slug, 0, @slug_max + 1)

    case String.replace(head, ~r/-[^-]*$/, "") do
      ^head -> binary_part(slug, 0, @slug_max)
      words -> words
    end
  end
end
