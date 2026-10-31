defmodule Public.Tenant do
  @moduledoc """
  The organisation's own part of the site: its names, footer lines,
  contacts, the texts cab shows about who runs it, the home and about
  pages, a few page labels and the club map. The deployment mounts them
  as a folder (`config :public, :tenant_dir`, TENANT_DIR in production)
  holding `tenant.json` and `map.json`; the code holds none of them.

  The folder is read once at boot (`load!/1`, from Public.Application)
  and kept in :persistent_term. A folder without a key the site needs
  refuses to boot, naming every missing key.

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
    ~w(about title),
    ~w(about blocks),
    ~w(about timeline),
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
    data = dir |> json!("tenant.json") |> Map.put("map", json!(dir, "map.json"))

    case missing(data) ++ unknown_branches(data) do
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
