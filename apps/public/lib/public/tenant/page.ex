defmodule Public.Tenant.Page do
  @moduledoc """
  A tenant's own page: `pages/<slug>.<lang>.md` in the tenant folder,
  served at `/<slug>`. A header between `---` lines (`title:` the page
  and menu title, `nav:` a number placing it in the header and footer
  menus, none keeps it out) and a Markdown body with blocks the site
  draws itself:

      ::: heading
      The organisation's name
      :::

      ::: cards
      ## Mission
      One paragraph.
      :::

      ::: timeline
      ## 2011
      - 07/05/2011: What happened
      :::

      ::: branches :::
      ::: documents :::
      ::: contacts :::

  `cards` holds one to three cards; `branches` is the branch map,
  `documents` the Policy and Terms, `contacts` the tenant's contacts (the
  last two side by side when they follow each other). Anything else is
  Markdown, raw HTML dropped.
  """

  @blocks ~w(heading cards timeline branches documents contacts)
  @max_cards 3

  @doc """
  Parses one file: `{:ok, %{title:, nav:, parts:}}` with parts
  `{:markdown, html}`, `{:heading, text}`, `{:cards, [{title, text}]}`,
  `{:timeline, [{year, [{date, text}]}]}`, `:branches`, `:documents`,
  `:contacts` - or `{:error, reason}`.
  """
  def parse(text) do
    with {:ok, header, body} <- header(text),
         {:ok, title} <- title(header),
         {:ok, nav} <- nav(header["nav"]),
         {:ok, parts} <- parts(String.split(body, ~r/\r?\n/), [], []) do
      {:ok, %{title: title, nav: nav, parts: parts}}
    end
  end

  defp header("---" <> rest) do
    case String.split(rest, ~r/\r?\n---[ \t]*(\r?\n|$)/, parts: 2) do
      [head, body] ->
        fields =
          for line <- String.split(head, ~r/\r?\n/, trim: true),
              [key, value] <- [String.split(line, ":", parts: 2)],
              into: %{},
              do: {String.trim(key), String.trim(value)}

        {:ok, fields, body}

      [_no_end] ->
        {:error, "the header has no closing ---"}
    end
  end

  defp header(_text), do: {:error, "no header (--- title: ... ---) at the top"}

  defp title(%{"title" => title}) when title != "", do: {:ok, title}
  defp title(_header), do: {:error, "the header has no title"}

  defp nav(nil), do: {:ok, nil}

  defp nav(value) do
    case Integer.parse(value) do
      {n, ""} -> {:ok, n}
      _ -> {:error, "nav is not a number: #{value}"}
    end
  end

  # the body line by line: Markdown runs, one-line blocks and blocks
  # with content up to their closing :::
  defp parts([], markdown, parts), do: {:ok, Enum.reverse(flush(markdown, parts))}

  defp parts([line | rest], markdown, parts) do
    cond do
      match = Regex.run(~r/^:::\s*([a-z]+)\s*:::\s*$/, line) ->
        with {:ok, part} <- block(Enum.at(match, 1), []),
             do: parts(rest, [], [part | flush(markdown, parts)])

      match = Regex.run(~r/^:::\s*([a-z]+)\s*$/, line) ->
        {inner, after_block} = Enum.split_while(rest, &(not Regex.match?(~r/^:::\s*$/, &1)))

        with :ok <- closed(after_block, Enum.at(match, 1)),
             {:ok, part} <- block(Enum.at(match, 1), inner),
             do: parts(tl(after_block), [], [part | flush(markdown, parts)])

      true ->
        parts(rest, [line | markdown], parts)
    end
  end

  defp closed([], name), do: {:error, "the #{name} block has no closing :::"}
  defp closed(_lines, _name), do: :ok

  defp flush(markdown, parts) do
    case markdown |> Enum.reverse() |> Enum.join("\n") |> String.trim() do
      "" -> parts
      text -> [{:markdown, MDEx.to_html!(text)} | parts]
    end
  end

  defp block(name, _inner) when name not in @blocks,
    do: {:error, "unknown block #{name} (known: #{Enum.join(@blocks, ", ")})"}

  defp block("heading", inner) do
    case text(inner) do
      "" -> {:error, "the heading block is empty"}
      heading -> {:ok, {:heading, heading}}
    end
  end

  defp block("cards", inner) do
    cards = for {title, lines} <- sections(inner), do: {title, text(lines)}

    if length(cards) in 1..@max_cards,
      do: {:ok, {:cards, cards}},
      else: {:error, "the cards block needs 1 to #{@max_cards} cards (## Title, then text)"}
  end

  defp block("timeline", inner) do
    years =
      for {year, lines} <- sections(inner) do
        {year, for(line <- lines, entry = entry(line), do: entry)}
      end

    if years != [] and Enum.all?(years, fn {_year, entries} -> entries != [] end),
      do: {:ok, {:timeline, years}},
      else: {:error, "the timeline block needs ## year headings, each with - date: text lines"}
  end

  defp block(name, _inner), do: {:ok, String.to_existing_atom(name)}

  # "## Title" lines start sections; lines before the first are dropped
  defp sections(lines) do
    {done, current} =
      Enum.reduce(lines, {[], nil}, fn line, {done, current} ->
        case Regex.run(~r/^##\s+(.+)$/, line) do
          [_, title] -> {close(current, done), {String.trim(title), []}}
          nil when current == nil -> {done, nil}
          nil -> {done, put_line(current, line)}
        end
      end)

    Enum.reverse(close(current, done))
  end

  defp put_line({title, lines}, line), do: {title, [line | lines]}

  defp close(nil, done), do: done
  defp close({title, lines}, done), do: [{title, Enum.reverse(lines)} | done]

  defp entry(line) do
    case Regex.run(~r/^\s*[-*]\s+(.+?):\s+(.+)$/, line) do
      [_, date, text] -> {String.trim(date), String.trim(text)}
      nil -> nil
    end
  end

  defp text(lines),
    do: lines |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == "")) |> Enum.join(" ")
end
