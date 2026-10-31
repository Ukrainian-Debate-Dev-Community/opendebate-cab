defmodule PublicWeb.CalendarHTML do
  use PublicWeb, :html

  alias PublicWeb.Period

  embed_templates "calendar_html/*"

  attr :period, Period, required: true
  attr :kind, :string, default: nil
  attr :base, :string, required: true
  attr :tag, :any, default: nil

  # month / year / all, the arrows of the month or year, and the kind
  # filter; all links, no script. Under /manage the links keep a chosen
  # tag.
  def toolbar(assigns) do
    assigns = assign(assigns, today: Date.beginning_of_month(Date.utc_today()))

    ~H"""
    <div class="ua-toolbar">
      <div class="ua-seg">
        <a
          class={@period.view == :month && "on"}
          href={link(@base, month_of(@period, @today), @kind, @tag)}
        >
          {gettext("Month")}
        </a>
        <a
          class={@period.view == :year && "on"}
          href={link(@base, year_of(@period, @today), @kind, @tag)}
        >
          {gettext("Year")}
        </a>
        <a class={@period.view == :all && "on"} href={link(@base, Period.all(), @kind, @tag)}>
          {gettext("All events")}
        </a>
      </div>
      <div :if={@period.view != :all} class="ua-month">
        <a
          class="ua-btn ua-btn--line ua-btn--sm"
          href={link(@base, Period.prev(@period), @kind, @tag)}
        >
          {step_label(Period.prev(@period))}
        </a>
        <b>{period_title(@period)}</b>
        <a
          class="ua-btn ua-btn--line ua-btn--sm"
          href={link(@base, Period.next(@period), @kind, @tag)}
        >
          {step_label(Period.next(@period))}
        </a>
      </div>
      <div class="ua-seg">
        <a class={is_nil(@kind) && "on"} href={link(@base, @period, nil, @tag)}>{gettext("All")}</a>
        <a
          :for={k <- Public.Events.Event.kinds()}
          class={k == @kind && "on"}
          href={link(@base, @period, k, @tag)}
        >
          {kinds_label(k)}
        </a>
      </div>
    </div>
    """
  end

  attr :event, :map, required: true
  slot :tags, doc: "more tags after the kind; /manage adds Private and the private tags"

  # an event's page below its head, public and under /manage alike: the
  # kind, the details, and when, where and in which language
  def event_body(assigns) do
    assigns =
      assign(assigns,
        paragraphs: paragraphs(assigns.event.details),
        language: event_language(assigns.event)
      )

    ~H"""
    <div class="ua-tags">
      <.tag kind={if @event.kind == "tournament", do: "ok", else: "info"}>
        {kind_label(@event.kind)}
      </.tag>
      {render_slot(@tags)}
    </div>
    <div class="ua-grid2">
      <div :if={@paragraphs != []}>
        <div class="ua-sec">{gettext("Details")}</div>
        <div class="ua-card ua-pad ua-prose ua-evtext" id="event-details">
          <p :for={paragraph <- @paragraphs}>{paragraph}</p>
        </div>
      </div>
      <div>
        <div class="ua-sec">{gettext("When and where")}</div>
        <div class="ua-card ua-pad ua-dl" id="event-facts">
          <div><span>{gettext("Dates")}</span>{event_dates(@event)}</div>
          <div :if={@event.city}><span>{gettext("City")}</span>{@event.city}</div>
          <div :if={@event.format}><span>{gettext("Format")}</span>{@event.format}</div>
          <div :if={@language}><span>{gettext("Language")}</span>{@language}</div>
        </div>
      </div>
    </div>
    """
  end

  # plain text, never HTML: a blank line starts a new paragraph
  def paragraphs(nil), do: []

  def paragraphs(text) do
    text
    |> String.split(~r/\R\s*\R/u)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  def link(base, %Period{} = period, kind, tag) do
    query =
      (Period.params(period) ++ [kind: kind, tag: tag && tag.id])
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    base <> "?" <> URI.encode_query(query)
  end

  # the events under month headings: the shown month alone, or each month
  # an event starts in (with its year when every event is shown)
  def groups(%Period{view: :month, first: first}, events), do: [{month_name(first.month), events}]

  def groups(%Period{view: view}, events) do
    events
    |> Enum.chunk_by(&{&1.starts_on.year, &1.starts_on.month})
    |> Enum.map(fn [event | _] = chunk ->
      month = month_name(event.starts_on.month)
      {if(view == :all, do: "#{month} #{event.starts_on.year}", else: month), chunk}
    end)
  end

  def empty_text(%Period{view: :month}), do: gettext("Nothing planned this month.")
  def empty_text(%Period{view: :year}), do: gettext("Nothing planned this year.")
  def empty_text(%Period{view: :all}), do: gettext("No events yet.")

  # switching view keeps the shown month or year where it can
  defp month_of(%Period{view: :month} = period, _today), do: period

  defp month_of(%Period{view: :year, first: first}, today) do
    Period.month(if first.year == today.year, do: today, else: first)
  end

  defp month_of(%Period{view: :all}, today), do: Period.month(today)

  defp year_of(%Period{view: :all}, today), do: Period.year(Date.new!(today.year, 1, 1))
  defp year_of(%Period{first: first}, _today), do: Period.year(Date.new!(first.year, 1, 1))

  defp period_title(%Period{view: :month, first: first}),
    do: "#{month_name(first.month)} #{first.year}"

  defp period_title(%Period{view: :year, first: first}), do: "#{first.year}"

  defp step_label(%Period{view: :month, first: first}), do: month_name(first.month)
  defp step_label(%Period{view: :year, first: first}), do: "#{first.year}"
end
