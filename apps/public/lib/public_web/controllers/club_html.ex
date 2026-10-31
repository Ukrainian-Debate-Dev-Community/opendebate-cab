defmodule PublicWeb.ClubHTML do
  use PublicWeb, :html

  alias PublicWeb.Clubs

  embed_templates "club_html/*"

  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :values, :list, required: true
  attr :labeler, :any, required: true
  attr :filters, :map, required: true

  # one filter as links: All, then each value; the other filters stay
  def filter_seg(assigns) do
    ~H"""
    <label>
      {@label}
      <span class="ua-seg">
        <a class={blank?(@filters[@name]) && "on"} href={href(@filters, @name, nil)}>
          {gettext("All")}
        </a>
        <a
          :for={v <- @values}
          class={@filters[@name] == v && "on"}
          href={href(@filters, @name, v)}
        >
          {@labeler.(v)}
        </a>
      </span>
    </label>
    """
  end

  def href(filters, name, value) do
    query = filters |> Map.put(name, value) |> Enum.reject(fn {_k, v} -> blank?(v) end)
    if query == [], do: ~p"/clubs", else: "/clubs?" <> URI.encode_query(query)
  end

  def labels(values, labeler), do: Enum.map_join(values || [], ", ", labeler)

  defp blank?(v), do: v in [nil, ""]
end
