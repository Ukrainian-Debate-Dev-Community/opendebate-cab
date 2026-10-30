defmodule PublicWeb.Site do
  @moduledoc """
  The site's pieces, ported from the design board: the
  header and footer every page shares, the ribbon under /manage, page
  heads, tags, news cards, event rows, the month grid and the maps.
  """
  use Phoenix.Component
  use Gettext, backend: PublicWeb.Gettext

  use Phoenix.VerifiedRoutes,
    endpoint: PublicWeb.Endpoint,
    router: PublicWeb.Router,
    statics: PublicWeb.static_paths()

  alias Public.{Geo, Tenant}

  @doc "Where cab lives; the Cabinet, Policy, Terms and club links point there."
  def cab_url(path \\ ""), do: Application.fetch_env!(:public, :cab_url) <> path

  # ---------------------------------------------------------------
  # frame
  # ---------------------------------------------------------------

  attr :class, :string, default: nil

  @doc "The tenant's name with its beta tag, linking home; the one copy every page uses."
  def wordmark(assigns) do
    assigns = assign(assigns, :name, Tenant.get(:name))

    ~H"""
    <a class={["wordmark", @class]} href={~p"/"}>{@name}<.beta /></a>
    """
  end

  @doc "The beta tag beside the wordmark, until the site leaves beta."
  def beta(assigns) do
    ~H"""
    <span class="beta-tag">{gettext("beta")}</span>
    """
  end

  attr :active, :atom, default: nil

  def site_header(assigns) do
    assigns =
      assign(assigns, :items, [
        {:home, ~p"/", gettext("Home")},
        {:news, ~p"/news", gettext("News")},
        {:calendar, ~p"/calendar", gettext("Calendar")},
        {:clubs, ~p"/clubs", gettext("Clubs")},
        {:about, ~p"/about", gettext("About")}
      ])

    ~H"""
    <header class="ua-top">
      <.wordmark class="ua-brand" />
      <nav class="ua-nav">
        <a :for={{key, href, label} <- @items} class={key == @active && "on"} href={href}>{label}</a>
      </nav>
      <div class="ua-right">
        <.switches />
        <a class="ua-btn ua-btn--line ua-btn--sm" href={cab_url()}>{gettext("Cabinet")}</a>
      </div>
    </header>
    """
  end

  @doc """
  The theme button (light, auto, dark on each click, kept in this
  browser) and the language menu, as in cab. Both work without the
  sign-in session: the theme lives in localStorage, the language in
  its own cookie.
  """
  def switches(assigns) do
    assigns = assign(assigns, :locale, Gettext.get_locale(PublicWeb.Gettext))

    ~H"""
    <div class="ua-switches">
      <button
        type="button"
        class="cycle"
        data-cycle="theme"
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
      <details class="langs" data-langs>
        <summary class="cycle" aria-label={gettext("Language")} title={gettext("Language")}>
          {PublicWeb.Locale.short(@locale)}
        </summary>
        <div class="menu" role="menu">
          <a
            :for={{code, label, name} <- PublicWeb.Locale.names()}
            href={"/locale/#{code}"}
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

  attr :access, :atom, required: true
  attr :manager, :map, required: true
  attr :active, :atom, default: nil

  def ribbon(assigns) do
    items = [
      {:dash, ~p"/manage", gettext("Overview")},
      {:news, ~p"/manage/news", gettext("News")},
      {:calendar, ~p"/manage/calendar", gettext("Calendar")},
      {:requests, ~p"/manage/requests", gettext("Requests")},
      {:tags, ~p"/manage/tags", gettext("Tags")}
    ]

    items =
      if assigns.access == :admin,
        do: items ++ [{:people, ~p"/manage/people", gettext("People")}],
        else: items

    assigns = assign(assigns, :items, items)

    ~H"""
    <div class="ua-cmbar">
      <span class="ua-cmrole">
        {if @access == :admin, do: gettext("Admin"), else: gettext("Content manager")}
      </span>
      <a :for={{key, href, label} <- @items} class={key == @active && "on"} href={href}>{label}</a>
      <span class="ua-cmme">
        <span class="ua-av">{initials(@manager)}</span>{display_name(@manager)}
      </span>
      <a class="ua-cmlink" href={~p"/"}>{gettext("View site")}</a>
      <a class="ua-cmlink" href={cab_url("/auth/logout")}>{gettext("Sign out")}</a>
    </div>
    """
  end

  def site_footer(assigns) do
    assigns = assign(assigns, :contacts, Tenant.get(:contacts))

    ~H"""
    <footer class="ua-foot">
      <div class="ua-foot-in ua-foot-in--3">
        <div>
          <.wordmark class="ua-foot-mark" />
          <p>{Tenant.text(:org)}</p>
          <p>{Tenant.text(:since)}</p>
        </div>
        <div>
          <b>{gettext("Site")}</b>
          <a href={~p"/news"}>{gettext("News")}</a>
          <a href={~p"/calendar"}>{gettext("Calendar")}</a>
          <a href={~p"/clubs"}>{gettext("Clubs")}</a>
          <a href={~p"/about"}>{gettext("About")}</a>
        </div>
        <div>
          <b>{gettext("Platform")}</b>
          <a href={cab_url()}>{gettext("Cabinet (cab)")}</a>
          <a href={cab_url("/policy")}>{gettext("Privacy policy")}</a>
          <a href={cab_url("/terms")}>{gettext("Terms of use")}</a>
        </div>
        <div>
          <b>{gettext("Contact")}</b>
          <a :for={contact <- @contacts} href={contact["href"]}>{contact["text"]}</a>
        </div>
      </div>
    </footer>
    """
  end

  # ---------------------------------------------------------------
  # page pieces
  # ---------------------------------------------------------------

  attr :kicker, :string, required: true
  attr :title, :string, required: true
  attr :lead, :string, default: nil
  attr :logo, :string, default: nil, doc: "an image beside the title (a club's logo)"
  slot :actions

  def page_head(assigns) do
    ~H"""
    <div class="ua-head">
      <img :if={@logo} class="ua-logo ua-logo--lg" src={@logo} alt="" />
      <div class="ua-head-text">
        <span class="ua-kicker">{@kicker}</span>
        <h1>{@title}</h1>
        <p :if={@lead} class="ua-lead">{@lead}</p>
      </div>
      <div :if={@actions != []} class="ua-head-act">{render_slot(@actions)}</div>
    </div>
    """
  end

  attr :kind, :string, default: nil
  slot :inner_block, required: true

  def tag(assigns) do
    ~H"""
    <span class={["ua-tag", @kind && "ua-tag--#{@kind}"]}>{render_slot(@inner_block)}</span>
    """
  end

  attr :post, :map, required: true

  def news_card(assigns) do
    ~H"""
    <article class="ua-card ua-news">
      <.cover post={@post}>
        <.tag kind="cover">{rubric_label(@post.rubric)}</.tag>
      </.cover>
      <div class="ua-pad">
        <h3><a href={~p"/news/#{@post.slug}"}>{@post.title}</a></h3>
        <div class="ua-meta">
          {long_date(@post.published_at)}, {gettext("%{n} min read", n: read_minutes(@post.body))}
        </div>
      </div>
    </article>
    """
  end

  attr :post, :map, required: true
  attr :class, :string, default: nil
  slot :inner_block

  @doc "A post's cover: its image when it has one, else one of three gradients."
  def cover(assigns) do
    ~H"""
    <div
      :if={@post.image}
      class={["ua-cover", "ua-cover--img", @class]}
    >
      <img src={Public.Uploads.url(@post.image)} alt={@post.image_alt || ""} loading="lazy" />
      {render_slot(@inner_block)}
    </div>
    <div :if={!@post.image} class={["ua-cover", "c#{rem(@post.id, 3) + 1}", @class]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :event, :map, required: true
  attr :href, :string, required: true, doc: "the event's page"
  slot :inner_block

  @doc """
  An event in a list. The whole row opens the event's page: the title's
  link stretches over it, and the row's own controls sit above that link.
  """
  def event_row(assigns) do
    assigns = assign(assigns, phase: event_phase(assigns.event, Date.utc_today()))

    ~H"""
    <div class={[
      "ua-ev",
      @event.visibility == "private" && "ua-ev--priv",
      @phase == :past && "ua-ev--past",
      @phase == :today && "ua-ev--today"
    ]}>
      <.date_badge date={@event.starts_on} />
      <div class="ua-ev-body">
        <h4><a class="ua-ev-link" href={@href}>{@event.title}</a></h4>
        <div class="ua-meta">{event_meta(@event)}</div>
      </div>
      <%= if @event.visibility == "private" do %>
        <.tag kind="priv">{gettext("Private")}</.tag>
      <% else %>
        <.tag kind={if @event.kind == "tournament", do: "ok", else: "info"}>
          {kind_label(@event.kind)}
        </.tag>
      <% end %>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :date, Date, required: true

  def date_badge(assigns) do
    ~H"""
    <span class="ua-date"><b>{pad(@date.day)}</b><span>{short_month(@date.month)}</span></span>
    """
  end

  attr :first, Date, required: true
  attr :events, :list, required: true
  attr :href, :any, required: true, doc: "a function from an event to its page"

  def month_grid(assigns) do
    first = assigns.first
    start = Date.beginning_of_week(first)
    stop = Date.end_of_week(Date.end_of_month(first))
    weeks = Date.range(start, stop) |> Enum.chunk_every(7)

    assigns =
      assign(assigns,
        weeks: weeks,
        today: Date.utc_today(),
        heads: [
          gettext("Mon"),
          gettext("Tue"),
          gettext("Wed"),
          gettext("Thu"),
          gettext("Fri"),
          gettext("Sat"),
          gettext("Sun")
        ]
      )

    ~H"""
    <div class="ua-cal">
      <div class="ua-cal-h"><span :for={h <- @heads}>{h}</span></div>
      <div :for={week <- @weeks} class="ua-cal-w">
        <div
          :for={day <- week}
          class={["ua-day", day.month != @first.month && "out", day == @today && "today"]}
        >
          <span class="n">{day.day}</span>
          <a
            :for={e <- Enum.filter(@events, &on_day?(&1, day))}
            class={[
              "ua-chip",
              e.visibility == "private" && "ua-chip--priv",
              event_phase(e, @today) == :past && "ua-chip--past"
            ]}
            href={@href.(e)}
          >
            {e.title}
          </a>
        </div>
      </div>
    </div>
    """
  end

  # an event is past once its last day is over, and on today while it runs
  defp event_phase(event, today) do
    cond do
      Date.compare(event.ends_on || event.starts_on, today) == :lt -> :past
      Date.compare(event.starts_on, today) != :gt -> :today
      true -> :upcoming
    end
  end

  defp on_day?(event, day),
    do:
      Date.compare(event.starts_on, day) != :gt and
        Date.compare(event.ends_on || event.starts_on, day) != :lt

  @doc "The club map: a dot per city with clubs, sized by their number; a dot filters the list."
  attr :counts, :map, required: true
  attr :selected, :string, default: nil
  attr :labels, :boolean, default: true

  def club_map(assigns) do
    dots =
      for {city, n} <- assigns.counts, point = Geo.point(city), point != nil do
        {city, n, point, 7 + 3 * (min(n, 6) - 1)}
      end

    assigns = assign(assigns, dots: dots, outline: Geo.outline(), view_box: Geo.view_box())

    ~H"""
    <svg class="ua-map" viewBox={@view_box} role="img" aria-label={Tenant.text([:labels, :map])}>
      <polygon class="ua-land" points={@outline} />
      <a
        :for={{city, n, {x, y}, r} <- @dots}
        class={["ua-city", city == @selected && "on"]}
        href={~p"/clubs?#{[city: city]}"}
      >
        <circle cx={x} cy={y} r={r} />
        <text :if={@labels} x={x + r + 5} y={y + 4}>{city_label(city)}{if n > 1, do: " #{n}"}</text>
      </a>
    </svg>
    """
  end

  @doc "The map of the active branches; a city opens Clubs filtered to it."
  def branch_map(assigns) do
    assigns =
      assign(assigns, branches: Geo.branches(), outline: Geo.outline(), view_box: Geo.view_box())

    ~H"""
    <svg
      class="ua-map ua-map--branches"
      viewBox={@view_box}
      role="img"
      aria-label={Tenant.text([:labels, :branches_map])}
    >
      <polygon class="ua-land" points={@outline} />
      <a :for={{city, {x, y}} <- @branches} class="ua-branch" href={~p"/clubs?#{[city: city]}"}>
        <circle cx={x} cy={y} r="5" />
        <text {branch_label(city, x, y)}>{city_label(city)}</text>
      </a>
    </svg>
    """
  end

  # a label sits right of its dot unless the tenant's map moves it
  defp branch_label(city, x, y) do
    case Geo.label_side(city) do
      :left -> %{x: x - 9, y: y + 5, "text-anchor": "end"}
      :below -> %{x: x + 9, y: y + 17}
      :right -> %{x: x + 9, y: y + 5}
    end
  end

  # ---------------------------------------------------------------
  # words
  # ---------------------------------------------------------------

  @doc """
  A city's name in the page language when the tenant's map names it;
  any other name is shown as the club wrote it in cab.
  """
  def city_label(city), do: Geo.name(city)

  def rubric_label("announcements"), do: gettext("Announcements")
  def rubric_label("results"), do: gettext("Results")
  def rubric_label("interviews"), do: gettext("Interviews")
  def rubric_label("tips"), do: gettext("Tips")
  def rubric_label(_), do: gettext("Community")

  def kind_label("tournament"), do: gettext("Tournament")
  def kind_label("training"), do: gettext("Training")
  def kind_label("club"), do: gettext("Club event")
  def kind_label(_), do: gettext("Event")

  def kinds_label("tournament"), do: gettext("Tournaments")
  def kinds_label("training"), do: gettext("Trainings")
  def kinds_label("club"), do: gettext("Club events")
  def kinds_label(_), do: gettext("Other events")

  def format_label("bp"), do: gettext("BP")
  def format_label("apf"), do: gettext("APF")
  def format_label(_), do: gettext("Other format")

  @doc "A club's format or language, with the club's own words for other."
  def format_label("other", text) when is_binary(text) and text != "", do: text
  def format_label(value, _text), do: format_label(value)
  def language_label("other", text) when is_binary(text) and text != "", do: text
  def language_label(value, _text), do: language_label(value)

  def language_label("uk"), do: gettext("Ukrainian")
  def language_label("en"), do: gettext("English")
  def language_label(_), do: gettext("Other language")

  def audience_label("school"), do: gettext("School students")
  def audience_label("university"), do: gettext("University students")
  def audience_label(_), do: gettext("Open to all")

  @doc "An event's language: its name from the list, or the name given for other."
  def event_language(%{language: "other", language_other: name}) when name not in [nil, ""],
    do: name

  def event_language(%{language: nil}), do: nil
  def event_language(%{language: code}), do: language_label(code)

  def event_meta(event) do
    [kind_label(event.kind), event.city, event.format, event_language(event)]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(", ")
  end

  def month_name(n) do
    Enum.at(
      [
        gettext("January"),
        gettext("February"),
        gettext("March"),
        gettext("April"),
        pgettext("short month", "May"),
        gettext("June"),
        gettext("July"),
        gettext("August"),
        gettext("September"),
        gettext("October"),
        gettext("November"),
        gettext("December")
      ],
      n - 1
    )
  end

  def short_month(n) do
    Enum.at(
      [
        pgettext("short month", "Jan"),
        pgettext("short month", "Feb"),
        pgettext("short month", "Mar"),
        pgettext("short month", "Apr"),
        pgettext("short month", "May"),
        pgettext("short month", "Jun"),
        pgettext("short month", "Jul"),
        pgettext("short month", "Aug"),
        pgettext("short month", "Sep"),
        pgettext("short month", "Oct"),
        pgettext("short month", "Nov"),
        pgettext("short month", "Dec")
      ],
      n - 1
    )
  end

  @doc "An event's day, or its first and last day when it runs longer."
  def event_dates(%{starts_on: first, ends_on: last}) do
    if last && Date.compare(last, first) == :gt,
      do: "#{long_date(first)} - #{long_date(last)}",
      else: long_date(first)
  end

  def long_date(nil), do: gettext("Draft")
  def long_date(%DateTime{} = at), do: long_date(DateTime.to_date(at))
  def long_date(%Date{} = d), do: "#{d.day} #{date_month(d.month)} #{d.year}"

  # the month as it reads inside a date (in some languages a different
  # form from the month's own name)
  defp date_month(n) do
    Enum.at(
      [
        pgettext("in a date", "January"),
        pgettext("in a date", "February"),
        pgettext("in a date", "March"),
        pgettext("in a date", "April"),
        pgettext("in a date", "May"),
        pgettext("in a date", "June"),
        pgettext("in a date", "July"),
        pgettext("in a date", "August"),
        pgettext("in a date", "September"),
        pgettext("in a date", "October"),
        pgettext("in a date", "November"),
        pgettext("in a date", "December")
      ],
      n - 1
    )
  end

  def read_minutes(body), do: max(1, div(length(String.split(body || "")), 200))

  def display_name(user), do: user.name || user.username

  def initials(user) do
    user
    |> display_name()
    |> String.split()
    |> Enum.take(2)
    |> Enum.map_join(&String.first/1)
    |> String.upcase()
  end

  defp pad(n) when n < 10, do: "0#{n}"
  defp pad(n), do: "#{n}"
end
