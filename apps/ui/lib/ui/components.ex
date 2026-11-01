defmodule Ui.Components do
  @moduledoc """
  The kit both web apps draw pages with: table, section, banner, flash
  banners, local time, copy, stepper, the split button and the beta
  tag. Generic: links and texts that belong to an app come in as attrs
  and slots.
  """

  use Phoenix.Component
  use Gettext, backend: Ui.Gettext

  # ---------------------------------------------------------------
  # Table
  # ---------------------------------------------------------------

  @doc """
  One table for everything tabular. Cell formats via `:col` flags:
  `code` (mono), `num` (right-aligned tabular), `float` (same),
  `center`; the table flag `rank` adds the violet # column. Empty
  rows render one centered muted line.

      <.table id="speakers" rows={@speakers} rank>
        <:col :let={s} label="Speaker">{s.name}<.sub>{s.club}</.sub></:col>
        <:col :let={s} label="Team" code>{s.team_key}</:col>
      </.table>
  """
  attr :id, :string, default: nil
  attr :rows, :list, required: true
  attr :rank, :boolean, default: false
  attr :row_id, :any, default: nil, doc: "row -> dom id"

  attr :row_class, :any,
    default: nil,
    doc: "row -> extra tr class (e.g. the viewer's \"me\" tint)"

  attr :row_href, :any,
    default: nil,
    doc: "row -> url the whole row opens (its links and buttons keep their own)"

  attr :empty, :string, default: nil, doc: "the empty-table line; nil = \"Nothing here yet.\""

  slot :head, doc: "markup before the first column's label (a select-all box)"

  slot :col do
    attr :label, :string
    attr :num, :boolean
    attr :float, :boolean
    attr :code, :boolean
    attr :center, :boolean
    attr :class, :string, doc: "extra td class (the draw table's side color bands)"
    attr :wide_only, :boolean, doc: "hidden when the table folds into cards on a phone"
  end

  def table(assigns) do
    ~H"""
    <table class="t t-rows" id={@id}>
      <thead>
        <tr>
          <th :if={@rank} style="width:40px">#</th>
          <th
            :for={{col, i} <- Enum.with_index(@col)}
            class={[(col[:num] || col[:float]) && "num", col[:center] && "c"]}
          >
            {if i == 0, do: render_slot(@head)}{col[:label]}
          </th>
        </tr>
      </thead>
      <tbody>
        <tr :if={@rows == []}>
          <td
            class="empty"
            colspan={length(@col) + ((@rank && 1) || 0)}
          >
            {@empty || gettext("Nothing here yet.")}
          </td>
        </tr>
        <tr
          :for={{row, index} <- Enum.with_index(@rows, 1)}
          id={@row_id && @row_id.(row)}
          class={[@row_class && @row_class.(row), @row_href && "linked"]}
          data-href={@row_href && @row_href.(row)}
        >
          <td :if={@rank} class="rank">{index}</td>
          <td
            :for={col <- @col}
            data-label={col[:label]}
            class={[
              col[:code] && "code",
              (col[:num] || col[:float]) && "num",
              col[:center] && "c",
              col[:class],
              col[:wide_only] && "wide-only"
            ]}
          >
            {render_slot(col, row)}
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc "The optional muted sub-line inside a table cell."
  slot :inner_block, required: true

  def sub(assigns) do
    ~H"""
    <span class="sub">{render_slot(@inner_block)}</span>
    """
  end

  # ---------------------------------------------------------------
  # Banner, time, stepper, split button, copy, section, beta
  # ---------------------------------------------------------------

  @doc "Flash + notices: three kinds, one optional trailing link."
  attr :kind, :atom, default: :info, values: [:info, :good, :bad]
  attr :href, :any, default: nil
  attr :link, :string, default: nil
  slot :inner_block, required: true

  def banner(assigns) do
    ~H"""
    <div class={["banner", to_string(@kind)]}>
      <span>{render_slot(@inner_block)}</span>
      <.link :if={@href} href={@href}>{@link}</.link>
    </div>
    """
  end

  @doc """
  A moment in time, shown in the viewer's zone and language: the server
  writes the UTC instant (and a UTC fallback text), the browser formats
  it with the account's time zone, or the device's (assets/js "when").
  Formats: :date (9 Oct 2026), :day (9 Oct), :datetime (9 Oct 2026, 18:30),
  :short (9 Oct, 18:30), :weekday_time (Thu 18:30), :time (18:30).
  """
  attr :at, :any, required: true
  attr :as, :atom, default: :date, values: [:date, :day, :datetime, :short, :weekday_time, :time]

  def local_time(assigns) do
    ~H"""
    <time :if={@at} datetime={DateTime.to_iso8601(@at)} data-when={@as}>{utc_text(@at, @as)}</time>
    """
  end

  defp utc_text(at, :date), do: Calendar.strftime(at, "%-d %b %Y")
  defp utc_text(at, :day), do: Calendar.strftime(at, "%-d %b")
  defp utc_text(at, :datetime), do: Calendar.strftime(at, "%-d %b %Y, %H:%M UTC")
  defp utc_text(at, :short), do: Calendar.strftime(at, "%-d %b, %H:%M UTC")
  defp utc_text(at, :weekday_time), do: Calendar.strftime(at, "%a %H:%M UTC")
  defp utc_text(at, :time), do: Calendar.strftime(at, "%H:%M UTC")

  @doc """
  A stepper, `[ < | current | > ]`: steps to the previous or the next
  value. With `event` both sides are LiveView buttons sending
  `phx-value-<name>` = `prev` / `next`; without it they are links to
  the `prev` / `next` paths. A side that is nil or false is shown but
  off. The current value is the inner block.

      <.stepper prev="/c/x/standings/teams?session=a" next={nil}
                prev_label="Earlier session" next_label="Later session">
        Club session, 17 Oct
      </.stepper>
  """
  attr :prev, :any,
    default: nil,
    doc: "the previous value (event) or path (link); nil/false = off"

  attr :next, :any, default: nil
  attr :prev_off, :boolean, default: false, doc: "shown but off, keeping its value"
  attr :next_off, :boolean, default: false
  attr :event, :string, default: nil
  attr :name, :string, default: "value", doc: "the phx-value-<name> an event sends"
  attr :prev_text, :string, default: "<"
  attr :next_text, :string, default: ">"
  attr :prev_label, :string, required: true
  attr :next_label, :string, required: true
  slot :inner_block, required: true

  def stepper(assigns) do
    ~H"""
    <span class="stepper">
      <.step
        value={@prev}
        off={@prev_off or @prev in [nil, false]}
        event={@event}
        name={@name}
        text={@prev_text}
        label={@prev_label}
      />
      <span class="n" aria-live="polite">{render_slot(@inner_block)}</span>
      <.step
        value={@next}
        off={@next_off or @next in [nil, false]}
        event={@event}
        name={@name}
        text={@next_text}
        label={@next_label}
      />
    </span>
    """
  end

  attr :value, :any
  attr :off, :boolean
  attr :event, :string
  attr :name, :string
  attr :text, :string
  attr :label, :string

  defp step(%{event: event} = assigns) when is_binary(event) do
    assigns = assign(assigns, :data, %{"phx-value-#{assigns.name}" => assigns.value})

    ~H"""
    <button
      type="button"
      phx-click={@event}
      {@data}
      disabled={@off}
      aria-label={@label}
      title={@label}
    >
      {@text}
    </button>
    """
  end

  defp step(assigns) do
    ~H"""
    <.link :if={!@off} href={@value} aria-label={@label} title={@label}>{@text}</.link>
    <span :if={@off} class="off" aria-hidden="true">{@text}</span>
    """
  end

  @doc """
  A split button: the main action, and beside it a caret opening a
  menu of alternatives - like a pull request's merge button. The main
  part submits its form (`type`, `form`) unless `href` makes it a
  link; each menu item is a link. The menu is a `<details>` (works
  without JS; app.js closes it on an outside click or Escape, as the
  language menu). With no items it is the plain button.

  Items are maps: `label`, `href`, optional `at` (a DateTime shown in
  the viewer's time zone after the label) and `current` (marked as
  the chosen one).

      <.dropdown_button items={[%{label: "Practice", href: "/c/x?session=y"}]}>
        Register
      </.dropdown_button>
  """
  attr :items, :list, default: []
  attr :href, :string, default: nil, doc: "the main part as a link instead of a submit"
  attr :type, :string, default: "submit"
  attr :form, :string, default: nil, doc: "the id of the form the main part submits"
  attr :quiet, :boolean, default: false, doc: "the plain style when the gold action is elsewhere"
  attr :disabled, :boolean, default: false
  attr :menu_label, :string, default: nil, doc: "the caret's name for screen readers"
  slot :inner_block, required: true

  def dropdown_button(assigns) do
    assigns =
      assign_new(assigns, :menu_label_text, fn ->
        assigns.menu_label || gettext("More options")
      end)

    ~H"""
    <div class={["dd-btn", if(@quiet, do: "quiet", else: "go"), @items != [] && "split"]}>
      <.link :if={@href} href={@href} class="dd-main">{render_slot(@inner_block)}</.link>
      <button :if={!@href} type={@type} form={@form} class="dd-main" disabled={@disabled}>
        {render_slot(@inner_block)}
      </button>
      <details :if={@items != []} class="dd-more" data-menu>
        <summary class="dd-caret" aria-label={@menu_label_text} title={@menu_label_text}>
          <svg viewBox="0 0 16 16" aria-hidden="true"><path d="M4 6l4 4 4-4" /></svg>
        </summary>
        <div class="menu" role="menu">
          <.link
            :for={item <- @items}
            href={item.href}
            role="menuitem"
            aria-current={item[:current] && "true"}
          >
            <span>{item.label}</span><span :if={item[:at]} class="at"><.local_time
              at={item.at}
              as={:weekday_time}
            /></span>
          </.link>
        </div>
      </details>
    </div>
    """
  end

  @doc """
  The copy-to-clipboard affordance: a small button that writes `text`
  to the clipboard (vanilla JS `[data-copy]` handler in app.js).
  """
  attr :text, :string, required: true

  def copy(assigns) do
    ~H"""
    <button type="button" class="copy" data-copy={@text}>{gettext("Copy")}</button>
    """
  end

  @doc """
  A banner carrying a shareable URL with the copy affordance: label,
  the full URL in mono, and the copy button (a registration link, a
  personal link).
  """
  attr :kind, :atom, default: :info, values: [:info, :good, :bad]
  attr :url, :string, required: true
  attr :id, :string, default: nil
  slot :inner_block

  def copy_banner(assigns) do
    ~H"""
    <div class={["banner", to_string(@kind)]} id={@id}>
      <span :if={@inner_block != []}>{render_slot(@inner_block)}</span>
      <code class="url">{@url}</code>
      <.copy text={@url} />
    </div>
    """
  end

  @doc "Flash messages rendered through the banner component."
  attr :flash, :map, required: true

  def flash_banners(assigns) do
    ~H"""
    <.banner :if={Phoenix.Flash.get(@flash, :info)} kind={:info}>
      {Phoenix.Flash.get(@flash, :info)}
    </.banner>
    <.banner :if={Phoenix.Flash.get(@flash, :error)} kind={:bad}>
      {Phoenix.Flash.get(@flash, :error)}
    </.banner>
    """
  end

  @doc """
  The only layout primitive: uppercase micro-title + card. A page is
  a stack of sections. `pad` wraps the content in
  the card's prose padding (summary cards); tables and forms fill the
  card flush.
  """
  attr :title, :string, required: true
  attr :pad, :boolean, default: false
  slot :inner_block, required: true

  def section(assigns) do
    ~H"""
    <div class="section">
      <h4>{@title}</h4>
      <div class="card">
        <%= if @pad do %>
          <div class="pad">{render_slot(@inner_block)}</div>
        <% else %>
          {render_slot(@inner_block)}
        <% end %>
      </div>
    </div>
    """
  end

  @doc "The beta tag beside an app's wordmark, until the app leaves beta."
  def beta(assigns) do
    ~H"""
    <span class="beta-tag">{gettext("beta")}</span>
    """
  end
end
