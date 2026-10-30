defmodule PublicWeb.PageHTML do
  use PublicWeb, :html

  alias Public.Tenant

  embed_templates "page_html/*"

  # the start of the story on the home page: {year, text}
  def story do
    for item <- Tenant.get(:story), do: {item["year"], Tenant.translate(item["text"])}
  end

  # the year line of the About page: {year, [{date, text}]}
  def timeline do
    for year <- Tenant.get([:about, :timeline]) do
      {year["year"], for(e <- year["entries"], do: {e["date"], Tenant.translate(e["text"])})}
    end
  end

  # entries alternate left and right of the year line
  def timeline_sides do
    {items, _} =
      Enum.map_reduce(timeline(), 0, fn {year, entries}, n ->
        sided = entries |> Enum.with_index(n) |> Enum.map(fn {e, i} -> {e, rem(i, 2)} end)
        {{year, sided}, n + length(entries)}
      end)

    items
  end
end
