defmodule Core.Ui do
  @moduledoc """
  Shared design-system components (the cab2 design language) usable by
  any web app in the umbrella. Route-free by design: segments and
  actions receive plain hrefs as data, so core never depends on any
  app's router. App-specific chrome (top bar, flow strips wired to
  routes) lives in the owning app, e.g. `CabWeb.Ui`.
  """

  use Phoenix.Component

  @doc """
  Generic progress strip (port of design/cab2 ui.js `statusline`):
  renders `items` as pseg segments. Each item is a map with `:label`,
  optional `:state` ("done" | "live" | nil), `:sel` and `:href`
  (segments with an href are links).
  """
  attr :items, :list, required: true
  attr :style, :string, default: nil

  def statusline(assigns) do
    ~H"""
    <div class="progressline" style={@style}>
      <%= for item <- @items do %>
        <a
          :if={item[:href]}
          class={["pseg", item[:state], item[:sel] && "sel"]}
          href={item[:href]}
        >
          {item.label}
        </a>
        <span :if={!item[:href]} class={["pseg", item[:state], item[:sel] && "sel"]}>
          {item.label}
        </span>
      <% end %>
    </div>
    """
  end

  @doc "Guidance line (cab2 alert--info) with an optional CTA slot."
  slot :inner_block, required: true
  slot :action

  def guide(assigns) do
    ~H"""
    <div class="alert alert--info">
      <span>{render_slot(@inner_block)}</span>
      <span :if={@action != []} style="margin-left:auto;">{render_slot(@action)}</span>
    </div>
    """
  end

  attr :status, :string, required: true

  def status_tag(assigns) do
    ~H"""
    <span class={["tag", status_tag_class(@status)]}>{@status}</span>
    """
  end

  defp status_tag_class(status) do
    case status do
      s when s in ["confirmed", "completed"] -> "tag--ok"
      s when s in ["judging", "in_progress"] -> "tag--warn"
      s when s in ["pending", "scheduled", "draft"] -> "tag--muted"
      _ -> "tag--info"
    end
  end
end
