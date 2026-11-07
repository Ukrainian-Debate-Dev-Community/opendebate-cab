defmodule Ui.Components do
  @moduledoc """
  The kit both web apps draw pages with: table, section, card, banner,
  flash banners, the command bar, the page head, tags, the empty line,
  local time, copy, stepper, the split button, the theme and language
  switches and the beta tag. Generic: links and texts that belong to an
  app come in as attrs and slots.
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
  attr :id, :string, default: nil
  slot :inner_block, required: true

  def banner(assigns) do
    ~H"""
    <div class={["banner", to_string(@kind)]} id={@id}>
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
  to the clipboard (the `[data-copy]` handler in ui.js), saying so for
  a moment.
  """
  attr :text, :string, required: true

  def copy(assigns) do
    ~H"""
    <button
      type="button"
      class="copy"
      data-copy={@text}
      data-label-copy={gettext("Copy")}
      data-label-copied={gettext("Copied")}
    >
      {gettext("Copy")}
    </button>
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
  card flush. `bare` leaves the card out, for content that brings its
  own (a list of rows, a grid of cards). An `action` is a link at the
  right of the title (All news).

      <.section title="News" bare>
        <:action href="/news">All news</:action>
        ...
      </.section>
  """
  attr :title, :string, required: true
  attr :id, :string, default: nil
  attr :pad, :boolean, default: false
  attr :bare, :boolean, default: false

  slot :action do
    attr :href, :string, required: true
  end

  slot :inner_block, required: true

  def section(assigns) do
    ~H"""
    <div class="section" id={@id}>
      <h4>
        <span>{@title}</span>
        <.link :for={action <- @action} href={action.href}>{render_slot(action)}</.link>
      </h4>
      <%= if @bare do %>
        {render_slot(@inner_block)}
      <% else %>
        <.card pad={@pad}>{render_slot(@inner_block)}</.card>
      <% end %>
    </div>
    """
  end

  @doc "A card: the bordered surface sections, forms and lists stand on."
  attr :id, :string, default: nil
  attr :class, :any, default: nil
  attr :pad, :boolean, default: false
  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <div class={Enum.join(["card" | List.wrap(@class)] |> Enum.filter(& &1), " ")} id={@id}>
      <%= if @pad do %>
        <div class="pad">{render_slot(@inner_block)}</div>
      <% else %>
        {render_slot(@inner_block)}
      <% end %>
    </div>
    """
  end

  @doc "The one muted line where a list has nothing (yet), in a card of its own."
  attr :id, :string, default: nil
  slot :inner_block, required: true

  def empty(assigns) do
    ~H"""
    <div class="card empty-state" id={@id}>{render_slot(@inner_block)}</div>
    """
  end

  @doc """
  A page's head: a kicker over the title, an optional lead and image
  (a logo), and the page's own actions at its right.
  """
  attr :kicker, :string, default: nil
  attr :title, :string, required: true
  attr :lead, :string, default: nil
  attr :logo, :string, default: nil, doc: "an image beside the title"
  slot :actions

  def page_head(assigns) do
    ~H"""
    <div class="page-head">
      <img :if={@logo} class="logo" src={@logo} alt="" />
      <div class="text">
        <span :if={@kicker} class="kicker">{@kicker}</span>
        <h1>{@title}</h1>
        <p :if={@lead} class="lead">{@lead}</p>
      </div>
      <div :if={@actions != []} class="acts">{render_slot(@actions)}</div>
    </div>
    """
  end

  @doc "A short status or kind beside a title: plain, ok, info, warn, priv or cover."
  attr :kind, :any, default: nil
  slot :inner_block, required: true

  def tag(assigns) do
    ~H"""
    <span class={["tag", @kind && to_string(@kind)]}>{render_slot(@inner_block)}</span>
    """
  end

  # ---------------------------------------------------------------
  # Command bar
  # ---------------------------------------------------------------

  @doc """
  The command bar of a page: crumb + THIS page's actions only, as
  flush tape-deck segments. Max one `primary` (gold) segment per page;
  `quiet` = destructive or exit.

  A segment with `form` renders as that form's submit button instead
  of a link; one with `method` (post, put, delete) is a link that
  sends that request (data-method, handled by phoenix_html's JS).

      <.chrome crumbs={[{"Club", "/c/x"}]} here="sessions">
        <:seg form="open-session-form" primary>Open new session</:seg>
      </.chrome>
  """
  attr :crumbs, :list, default: [], doc: "crumb entries as {label, href} tuples"
  attr :here, :string, default: nil, doc: "the non-link tail crumb"

  slot :seg do
    attr :href, :any
    attr :method, :string, doc: "defaults to get; post renders a method link"
    attr :form, :string, doc: "renders a submit button for this form id instead of a link"
    attr :primary, :boolean, doc: "the page's single gold segment"
    attr :quiet, :boolean, doc: "grey: destructive or exit"
    attr :id, :string
  end

  def chrome(assigns) do
    ~H"""
    <div class="chrome">
      <div class="crumb">
        <%= for {label, href} <- @crumbs do %>
          <.link href={href}>{label}</.link>
          <span class="sep">/</span>
        <% end %>
        <span :if={@here} class="here">{@here}</span>
      </div>
      <div :if={@seg != []} class="seg">
        <%= for seg <- @seg do %>
          <%= if seg[:form] do %>
            <button
              type="submit"
              form={seg[:form]}
              id={seg[:id]}
              class={[seg[:primary] && "go", seg[:quiet] && "quiet"]}
            >
              {render_slot(seg)}
            </button>
          <% else %>
            <.link
              href={seg.href}
              method={seg[:method] || "get"}
              id={seg[:id]}
              class={[seg[:primary] && "go", seg[:quiet] && "quiet"]}
            >
              {render_slot(seg)}
            </.link>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------
  # Theme and language
  # ---------------------------------------------------------------

  @doc """
  The theme button (light, auto, dark on each click, kept in this
  browser under `theme_key`) and the language menu (each of `locales`,
  `{code, short label, name}`, a link to `<locale_path><code>`). ui.js
  runs both; without it the language links still work. `up` opens the
  menu upwards (a switch at the bottom of a column).
  """
  attr :locale, :string, required: true
  attr :locales, :list, required: true
  attr :theme_key, :string, required: true
  attr :locale_path, :string, default: "/locale/"
  attr :up, :boolean, default: false
  attr :rest, :global

  def switches(assigns) do
    assigns =
      assign(assigns,
        short:
          Enum.find_value(assigns.locales, assigns.locale, fn {code, label, _name} ->
            code == assigns.locale && label
          end)
      )

    ~H"""
    <div class="switches" {@rest}>
      <button
        type="button"
        class="cycle"
        data-cycle="theme"
        data-theme-key={@theme_key}
        data-state="auto"
        data-label-light={gettext("Theme: light")}
        data-label-auto={gettext("Theme: auto")}
        data-label-dark={gettext("Theme: dark")}
        aria-label={gettext("Theme: auto")}
        title={gettext("Theme: light, auto or dark")}
      >
        <svg class="i-light" viewBox="0 0 16 16" aria-hidden="true">
          <circle cx="8" cy="8" r="2.6" />
          <path d="M8 1.5v1.8M8 12.7v1.8M1.5 8h1.8M12.7 8h1.8M3.4 3.4l1.3 1.3M11.3 11.3l1.3 1.3M3.4 12.6l1.3-1.3M11.3 4.7l1.3-1.3" />
        </svg>
        <svg class="i-auto" viewBox="0 0 16 16" aria-hidden="true">
          <circle cx="8" cy="8" r="5.5" /><path d="M8 2.5v11a5.5 5.5 0 0 0 0-11Z" class="fill" />
        </svg>
        <svg class="i-dark" viewBox="0 0 16 16" aria-hidden="true">
          <path d="M13 9.6A5.2 5.2 0 0 1 6.4 3a5.2 5.2 0 1 0 6.6 6.6Z" />
        </svg>
      </button>
      <details class={["langs", @up && "up"]} data-langs>
        <summary class="cycle" aria-label={gettext("Language")} title={gettext("Language")}>
          {@short}
        </summary>
        <div class="menu" role="menu">
          <a
            :for={{code, label, name} <- @locales}
            href={@locale_path <> code}
            lang={code}
            role="menuitem"
            aria-current={@locale == code && "true"}
          >
            <span class="code">{label}</span>{name}
          </a>
        </div>
      </details>
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
