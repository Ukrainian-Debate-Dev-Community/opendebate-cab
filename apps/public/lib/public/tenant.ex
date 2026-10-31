defmodule Public.Tenant do
  @moduledoc """
  The organisation's own part of the site: its names, footer lines,
  contacts, the texts cab shows about who runs it, the home and about
  page, a few page labels, the club map and its own pages (About...).
  The deployment mounts them as a folder (`config :public, :tenant_dir`,
  TENANT_DIR in production) holding `tenant.json`, `map.json` and
  `pages/` (`Public.Tenant.Page`); the code holds none of them.

  The folder is read once at boot (`load!/1`, from Public.Application)
  and kept in :persistent_term. A folder without a key the site needs, or
  with a page that does not read, refuses to boot, naming every problem.

  Every text is an object with a value per language, `{"en": "...",
  "uk": "..."}`; `text/2` and `translate/2` give the value in the page
  language, English when the language has none. Links and e-mail
  addresses are plain strings.
  """

  @term {__MODULE__, :data}

  # what the site reads; a value may be null only where noted below
  @required [
    ~w(name),
    ~w(title),
    ~w(org),
    ~w(since),
    ~w(contacts),
    ~w(cab about),
    ~w(cab site_url),
    ~w(cab org_text),
    ~w(cab org_label),
    ~w(cab org_url),
    ~w(cab contact_email),
    ~w(cab support_email),
    ~w(cab signin_foot),
    ~w(cab directory_title),
    ~w(cab welcome),
    ~w(cab tagline),
    ~w(home kicker),
    ~w(home heading),
    ~w(home heading_em),
    ~w(home lead),
    ~w(home about_link),
    ~w(story),
    ~w(labels news),
    ~w(labels clubs),
    ~w(labels calendar_lead),
    ~w(labels map),
    ~w(labels branches),
    ~w(labels branches_map),
    ~w(map size),
    ~w(map outline),
    ~w(map cities),
    ~w(map branches)
  ]

  # keys that may be null or left out: home.notice (no notice on the
  # home page), event_requests_email (nobody is e-mailed), map.names
  # (city names per language) and map.label_side ("left" or "below"
  # for a branch whose label would cover a neighbour)

  @doc "The keys the site needs, as dotted paths."
  def required, do: Enum.map(@required, &Enum.join(&1, "."))

  @doc "Reads the folder and keeps it for `get/1`; raises when a key is missing."
  def load!(dir \\ Application.fetch_env!(:public, :tenant_dir)) do
    data = read!(dir)
    :persistent_term.put(@term, data)
    data
  end

  @doc """
  The folder's `tenant.json`, with `map.json` under "map". Raises when a
  file is missing or unreadable, or when keys the site needs are missing
  (all of them in one message).
  """
  def read!(dir) do
    {pages, page_problems} = pages(dir)

    data =
      dir
      |> json!("tenant.json")
      |> Map.put("map", json!(dir, "map.json"))
      |> Map.put("pages", pages)

    case missing(data) ++ unknown_branches(data) ++ page_problems do
      [] ->
        data

      problems ->
        raise ArgumentError,
              "the tenant folder #{dir} is missing what the site needs: " <>
                Enum.join(problems, ", ")
    end
  end

  defp json!(dir, file) do
    path = Path.join(dir, file)

    case File.read(path) do
      {:ok, body} ->
        case Jason.decode(body) do
          {:ok, %{} = map} -> map
          _ -> raise ArgumentError, "the tenant file #{path} is not a JSON object"
        end

      {:error, reason} ->
        raise ArgumentError,
              "the tenant file #{path} cannot be read: #{:file.format_error(reason)}"
    end
  end

  # pages/<slug>.<lang>.md: %{slug => %{lang => page}}, every page with
  # its English file
  defp pages(dir) do
    files = Path.wildcard(Path.join([dir, "pages", "*.md"]))

    {pages, problems} =
      Enum.reduce(files, {%{}, []}, fn path, {pages, problems} ->
        name = Path.basename(path)

        with [_, slug, lang] <- Regex.run(~r/^([a-z0-9-]+)\.([a-z]{2})\.md$/, name),
             {:ok, page} <- path |> File.read!() |> Public.Tenant.Page.parse() do
          {Map.update(pages, slug, %{lang => page}, &Map.put(&1, lang, page)), problems}
        else
          nil -> {pages, problems ++ ["pages/#{name} (name it <slug>.<lang>.md)"]}
          {:error, reason} -> {pages, problems ++ ["pages/#{name}: #{reason}"]}
        end
      end)

    english = for {slug, langs} <- pages, not Map.has_key?(langs, "en"), do: "pages/#{slug}.en.md"
    {pages, problems ++ english}
  end

  defp missing(data) do
    for path <- @required, fetch(data, path) in [nil, ""], do: Enum.join(path, ".")
  end

  defp unknown_branches(%{"map" => %{"branches" => branches, "cities" => %{} = cities}})
       when is_list(branches) do
    for city <- branches, not Map.has_key?(cities, city), do: "map.cities.#{city}"
  end

  defp unknown_branches(_data), do: []

  @doc "A value as the folder has it: `get(\"name\")`, `get([:home, :notice])`."
  def get(keys), do: fetch(data(), List.wrap(keys))

  @doc "A tenant page by its slug, in `locale` (the page language by default), English when missing; nil when there is none."
  def page(slug, locale \\ nil) do
    case get(["pages", slug]) do
      nil -> nil
      langs -> langs[locale || Gettext.get_locale(PublicWeb.Gettext)] || langs["en"]
    end
  end

  @doc "The pages in the header and footer menus, by their nav number: [{slug, title}]."
  def nav_pages(locale \\ nil) do
    for(
      {slug, %{"en" => %{nav: nav}}} when is_integer(nav) <- get("pages") || %{},
      do: {nav, slug}
    )
    |> Enum.sort()
    |> Enum.map(fn {_nav, slug} -> {slug, page(slug, locale).title} end)
  end

  @doc "A text in `locale` (the page language by default), English when missing."
  def text(keys, locale \\ nil), do: keys |> get() |> translate(locale)

  @doc """
  A text object's value in `locale` (the page language by default),
  English when it has none. A plain string is the same in every language.
  """
  def translate(text, locale \\ nil)
  def translate(nil, _locale), do: nil
  def translate(text, _locale) when is_binary(text), do: text

  def translate(%{} = text, locale) do
    locale = locale || Gettext.get_locale(PublicWeb.Gettext)
    present(text[locale]) || text["en"]
  end

  defp present(value) when value in [nil, ""], do: nil
  defp present(value), do: value

  defp data do
    :persistent_term.get(@term, nil) ||
      raise "the tenant is not loaded: Public.Tenant.load!/1 runs at boot"
  end

  defp fetch(data, []), do: data

  defp fetch(%{} = data, [key | rest]),
    do: data |> Map.get(to_string(key)) |> fetch(rest)

  defp fetch(_data, _keys), do: nil
end
