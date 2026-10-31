defmodule PublicWeb.PageHTML do
  use PublicWeb, :html

  alias Public.Tenant

  embed_templates "page_html/*"

  # the start of the story on the home page: {year, text}
  def story do
    for item <- Tenant.get(:story), do: {item["year"], Tenant.translate(item["text"])}
  end

  # a tenant page's parts in runs: {:main, parts} for the page's own
  # blocks, {:side, parts} for Documents and Contacts that follow each
  # other, set side by side below them
  def groups(parts) do
    parts
    |> Enum.chunk_by(&(&1 in [:documents, :contacts]))
    |> Enum.map(fn
      [side | _] = sides when side in [:documents, :contacts] -> {:side, sides}
      main -> {:main, main}
    end)
  end

  attr :part, :any, required: true

  @doc "One block of a tenant page (Public.Tenant.Page)."
  def part(%{part: {:markdown, html}} = assigns) do
    assigns = assign(assigns, :html, html)

    ~H"""
    <div class="ua-prose">{Phoenix.HTML.raw(@html)}</div>
    """
  end

  def part(%{part: {:heading, text}} = assigns) do
    assigns = assign(assigns, :lines, String.split(text, " ", parts: 3))

    ~H"""
    <h1 class="ua-hist-title">
      <%= for {line, i} <- Enum.with_index(@lines) do %>
        <br :if={i > 0} />{line}
      <% end %>
    </h1>
    """
  end

  def part(%{part: {:cards, cards}} = assigns) do
    assigns = assign(assigns, :cards, Enum.with_index(cards, 1))

    ~H"""
    <div class="ua-blobs">
      <div :for={{{title, text}, i} <- @cards} class={["ua-blob", "b#{i}"]}>
        <h2>{title}</h2>
        <p>{text}</p>
      </div>
    </div>
    """
  end

  def part(%{part: {:timeline, years}} = assigns) do
    assigns = assign(assigns, :years, sided(years))

    ~H"""
    <div class="ua-tl">
      <%= for {year, entries} <- @years do %>
        <div class="ua-tl-year"><span>{year}</span></div>
        <div
          :for={{{date, text}, side} <- entries}
          class={["ua-tl-item", if(side == 0, do: "l", else: "r")]}
        >
          <div class="ua-tl-card">
            <b>{date}</b><p>{text}</p>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  def part(%{part: :branches} = assigns) do
    ~H"""
    <div class="ua-branches">
      <div class="ua-branches-h">
        <b>{Tenant.text([:labels, :branches])}</b><span>
          {ngettext(
            "%{count} city. Click a city to see its clubs",
            "%{count} cities. Click a city to see its clubs",
            length(Public.Geo.branches())
          )}
        </span>
      </div>
      <.branch_map />
    </div>
    """
  end

  attr :sides, :list, required: true

  @doc "Documents and Contacts, side by side when both follow each other."
  def sides(assigns) do
    ~H"""
    <div class={length(@sides) > 1 && "ua-grid2"}>
      <div :for={side <- @sides}>
        <%= if side == :documents do %>
          <div class="ua-sec">{gettext("Documents")}</div>
          <div class="ua-card ua-docs">
            <a href={cab_url("/policy")}>
              <b>{gettext("Privacy policy")}</b><span>{gettext("What we store and why")}</span>
            </a>
            <a href={cab_url("/terms")}>
              <b>{gettext("Terms of use")}</b><span>{gettext("The rules for the site and the cabinet")}</span>
            </a>
          </div>
        <% else %>
          <div class="ua-sec">{gettext("Contact")}</div>
          <div class="ua-card ua-pad ua-dl">
            <div :for={contact <- Tenant.get(:contacts)}>
              <span>{Tenant.translate(contact["label"])}</span><a href={contact["href"]}>{contact[
                "text"
              ]}</a>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # timeline entries alternate left and right of the year line
  def sided(years) do
    {items, _} =
      Enum.map_reduce(years, 0, fn {year, entries}, n ->
        sided = entries |> Enum.with_index(n) |> Enum.map(fn {e, i} -> {e, rem(i, 2)} end)
        {{year, sided}, n + length(entries)}
      end)

    items
  end
end
