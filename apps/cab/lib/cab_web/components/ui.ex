defmodule CabWeb.Ui do
  @moduledoc """
  The design-system kit: the core components (chrome/action bar,
  sidenav, table, form, ballot, allocator) plus banner and section.

  Every page is a chrome bar and a stack of sections - nothing
  actionable exists outside the chrome, and no element outside this
  kit may appear on a page (whitelist doctrine).
  """

  use Phoenix.Component
  use Gettext, backend: CabWeb.Gettext

  import Phoenix.Controller, only: [get_csrf_token: 0]

  use Phoenix.VerifiedRoutes,
    endpoint: CabWeb.Endpoint,
    router: CabWeb.Router,
    statics: CabWeb.static_paths()

  # ---------------------------------------------------------------
  # 1. Chrome / action bar
  # ---------------------------------------------------------------

  @doc """
  The control mechanism of every page: crumb + THIS page's
  actions only, as flush tape-deck segments - navigation and the
  profile live in the sidenav, status lives in the page content as
  words. Max one `primary` (gold) segment per page; `quiet` =
  destructive or exit.

  A segment with `form` renders as that form's submit button instead
  of a link - the design's "submit lives in the chrome" rule for the
  ballot/compose/edit pages (the components carry no buttons).

      <.chrome crumbs={[{@club.name, ~p"/c/\#{@club.uuid}"}]} here="sessions">
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
              class={[seg[:primary] && "go", seg[:quiet] && "quiet"]}
            >
              {render_slot(seg)}
            </button>
          <% else %>
            <.link
              href={seg.href}
              method={seg[:method] || "get"}
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

  @doc "The beta tag beside the cab wordmark, until cab leaves beta."
  def beta(assigns) do
    ~H"""
    <span class="beta-tag">{gettext("beta")}</span>
    """
  end

  @doc """
  The left sidenav - ONLY navigation: brand script cap -> home, plain
  place-name items for the current context (global: Clubs / Standings
  / My page / + Admin for admins; club: Club / Rooms / Standings /
  Members / Register) and the profile block
  pinned to the bottom (avatar initials + username -> /account, sign
  out; anonymous: Sign in). No badges, counters or suffixes; the
  active item carries a left border.
  """
  attr :current_user, :any, default: nil
  attr :club, :any, default: nil, doc: "club context; nil = global"
  attr :club_role, :atom, default: :public
  attr :nav_session, :any, default: nil, doc: "the club's current session row (Rooms target)"
  attr :active, :string, default: nil, doc: "the lit item key"

  def sidenav(assigns) do
    ~H"""
    <nav class="sidenav" id="sidenav">
      <div class="bar">
        <.link href={~p"/"} class="cap">cab<.beta /></.link>
        <span :if={@club} class="where">{@club.name}</span>
        <button
          type="button"
          class="menu-btn"
          data-nav-toggle
          aria-controls="sidenav-menu"
          aria-expanded="false"
        >
          {gettext("Menu")}
        </button>
      </div>
      <div class="navbody" id="sidenav-menu">
        <%= if @club do %>
          <div class="sec">{@club.name}</div>
          <.nav_item
            active={@active}
            key="club"
            href={club_href(@club, @club_role)}
            label={gettext("Club")}
          />
          <.nav_item
            active={@active}
            key="rooms"
            href={rooms_href(@club, @club_role, @nav_session)}
            label={gettext("Rooms")}
          />
          <.nav_item
            active={@active}
            key="standings"
            href={~p"/c/#{@club.uuid}/standings/teams"}
            label={gettext("Standings")}
          />
          <.nav_item
            :if={not @club.is_private or Cab.Clubs.covers?(@club_role, :member)}
            active={@active}
            key="members"
            href={members_href(@club, @club_role)}
            label={gettext("Members")}
          />
        <% else %>
          <.nav_item active={@active} key="clubs" href={~p"/"} label={gettext("Clubs")} />
          <.nav_item
            active={@active}
            key="standings"
            href={~p"/standings/teams"}
            label={gettext("Standings")}
          />
          <.nav_item
            :if={@current_user && !guest?(@current_user)}
            active={@active}
            key="me"
            href={~p"/me"}
            label={gettext("My page")}
          />
          <.nav_item
            :if={@current_user && @current_user.is_admin}
            active={@active}
            key="admin"
            href={~p"/admin"}
            label={gettext("Admin")}
          />
        <% end %>
        <div class="profile" id="sidenav-profile">
          <div class="me">
            <%= if @current_user do %>
              <div class="who">
                <span class="av">{initials(@current_user)}</span>
                <%= if guest?(@current_user) do %>
                  <span>{@current_user.name || @current_user.username}</span>
                <% else %>
                  <.link href={~p"/account"}>{@current_user.username}</.link>
                <% end %>
              </div>
              <.link :if={guest?(@current_user)} href={~p"/signin"}>
                {gettext("Sign in with an account")}
              </.link>
              <.link class="out" href={~p"/auth/logout"}>{gettext("Sign out")}</.link>
            <% else %>
              <.link href={~p"/signin"}>{gettext("Sign in")}</.link>
            <% end %>
          </div>
          <div class="switches" id="sidenav-switches" phx-update="ignore">
            <button
              type="button"
              class="cycle"
              data-cycle="theme"
              data-state="auto"
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
                {CabWeb.Locale.short(Gettext.get_locale(CabWeb.Gettext))}
              </summary>
              <div class="menu" role="menu">
                <a
                  :for={{code, label, name} <- CabWeb.Locale.names()}
                  href={"/locale/#{code}"}
                  lang={code}
                  role="menuitem"
                  aria-current={Gettext.get_locale(CabWeb.Gettext) == code && "true"}
                >
                  <span class="code">{label}</span>{name}
                </a>
              </div>
            </details>
          </div>
        </div>
      </div>
    </nav>
    """
  end

  attr :key, :string, required: true
  attr :active, :string, default: nil
  attr :href, :any, required: true
  attr :label, :string, required: true

  defp nav_item(assigns) do
    ~H"""
    <.link href={@href} class={["item", @key == @active && "on"]}>{@label}</.link>
    """
  end

  defp club_href(club, role) when role in [:owner, :admin], do: ~p"/c/#{club.uuid}/owner"
  defp club_href(club, _role), do: ~p"/c/#{club.uuid}"

  # the LIVE session lives under Rooms; with no session yet the item
  # falls back to the archive (owner opens new sessions there)
  defp rooms_href(club, role, %{uuid: uuid}) when role in [:owner, :admin],
    do: ~p"/c/#{club.uuid}/owner/s/#{uuid}"

  defp rooms_href(club, _role, %{uuid: uuid}), do: ~p"/c/#{club.uuid}/s/#{uuid}"
  # no session yet: Rooms falls back to the club page (the archive;
  # the owner's edit view also opens new sessions there)
  defp rooms_href(club, role, nil) when role in [:owner, :admin],
    do: ~p"/c/#{club.uuid}/owner"

  defp rooms_href(club, _role, nil), do: ~p"/c/#{club.uuid}"

  defp members_href(club, role) when role in [:owner, :admin],
    do: ~p"/c/#{club.uuid}/owner/members"

  defp members_href(club, _role), do: ~p"/c/#{club.uuid}/members"

  defp guest?(user), do: Map.get(user, :guest, false)

  defp initials(user) do
    (user.name || user.username || "?")
    |> String.split()
    |> Enum.take(2)
    |> Enum.map(&String.first/1)
    |> Enum.join()
    |> String.upcase()
  end

  @doc """
  The tab row under the chrome (`.selrow`) - picks WHICH
  view of the page is shown (the four standings tabs). Real borders,
  no badges. `tabs` entries are `{key, label, href}`.
  """
  attr :id, :string, default: nil
  attr :tabs, :list, required: true
  attr :active, :string, required: true

  def selrow(assigns) do
    ~H"""
    <div class="selrow" id={@id}>
      <.link :for={{key, label, href} <- @tabs} href={href} class={key == @active && "on"}>
        {label}
      </.link>
    </div>
    """
  end

  # ---------------------------------------------------------------
  # 2. Table / standings
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
  # 3. Form
  # ---------------------------------------------------------------

  @doc """
  One form component for every write: violet top rule, head block
  (title + description), field blocks divided by hairlines, tinted
  submit block with one gold button + consequence note. POSTs to the
  same REST action the API exposes.

  Block types (the complete inventory): `:text`, `:longtext`, `:int`,
  `:float`, `:scale` (flush integer segments), `:yesno` (two pills),
  `:select` (pills at 2-4 options, dropdown at 5+), `:multi` (stacked
  checks), `:check` (one yes box), `:datetime` (half-split pair, pass
  `names`), `:file` (an image picker with the current one's `preview`
  and a `remove` box; pass `enctype="multipart/form-data"`). A `:text`
  block may name its input type (`input`: email, tel); a `:select`
  dropdown may lead with an empty `prompt` option.

  Server errors render per block: pass `errors` as a map of
  block-name => message; the failing block gets the amber border +
  message, the rest stay untouched.

      <.form_for action={~p"/c/\#{@club.uuid}/owner/sessions"}
                 title="Open a session" description="...">
        <:block name={:name} type={:text} label="Session name" required hint="..." />
        <:block name={:rooms} type={:int} label="Rooms" min={1} max={6} />
        <:submit note="Members get the sign-up right away.">Open session</:submit>
      </.form_for>
  """
  attr :action, :string, required: true
  attr :method, :string, default: "post"
  attr :id, :string, default: nil
  attr :title, :string, default: nil
  attr :description, :string, default: nil
  attr :errors, :map, default: %{}, doc: "block name => server-side error message"
  attr :hidden, :list, default: [], doc: "extra hidden inputs as {name, value}"
  attr :enctype, :string, default: nil, doc: "multipart/form-data for a :file block"
  attr :logo, :string, default: nil, doc: "an image beside the head block (the club's logo)"

  attr :guard, :boolean,
    default: false,
    doc: "a public form's bot protection before the submit block (CabWeb.BotGuard)"

  slot :block do
    attr :name, :any
    attr :names, :list, doc: "the two field names of a :datetime pair"
    attr :type, :atom
    attr :label, :string
    attr :required, :boolean
    attr :hint, :string
    attr :min, :any
    attr :max, :any
    attr :step, :any
    attr :value, :any
    attr :values, :list, doc: "the two values of a :datetime pair"
    attr :options, :list, doc: "choices for :select / :multi, strings or {label, value}"
    attr :placeholder, :string
    attr :input, :string, doc: "a :text block's input type: email, tel (default text)"
    attr :prompt, :string, doc: "a :select dropdown's empty first option"
    attr :maxlength, :integer
    attr :list, :string, doc: "a :text block's <datalist> id, for suggestions while typing"
    attr :other, :string, doc: "a :select pills value that opens a free-text field when chosen"
    attr :other_name, :any, doc: "that free-text field's name"
    attr :other_value, :string, doc: "that free-text field's current text"
    attr :other_placeholder, :string
    attr :accept, :string, doc: "a :file block's accepted types"
    attr :preview, :string, doc: "a :file block's current image"
    attr :preview_alt, :string, doc: "that image's text"
    attr :remove, :string, doc: "a :file block's remove box name (shown with a preview)"
    attr :remove_label, :string
  end

  slot :submit do
    attr :note, :string
    attr :quiet, :boolean, doc: "a plain button when the page's gold action is elsewhere"
    attr :disabled, :boolean, doc: "shown but not usable (a preview)"
  end

  def form_for(assigns) do
    ~H"""
    <form class="form" id={@id} action={@action} method={@method} enctype={@enctype}>
      <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
      <input :for={{name, value} <- @hidden} type="hidden" name={name} value={value} />
      <div :if={@title || @description} class={if @logo, do: "f-head with-logo", else: "f-head"}>
        <img :if={@logo} class="club-logo" src={@logo} alt="" />
        <div>
          <h3 :if={@title}>{@title}</h3>
          <p :if={@description}>{@description}</p>
        </div>
      </div>
      <div :for={block <- @block} class={["f-block", @errors[block[:name]] && "err"]}>
        <label :if={block[:label]} class="q">
          {block[:label]} <span :if={block[:required]} class="req">*</span>
        </label>
        {control(block)}
        <div :if={@errors[block[:name]]} class="error">{@errors[block[:name]]}</div>
        <div :if={block[:hint] && !@errors[block[:name]]} class="hint">{block[:hint]}</div>
      </div>
      <.bot_guard :if={@guard} error={@errors[:turnstile]} />
      <div :for={submit <- @submit} class="f-submit">
        <button
          type="submit"
          class={if submit[:quiet], do: "btn-quiet", else: "btn-go"}
          disabled={submit[:disabled]}
        >
          {render_slot(submit)}
        </button>
        <span :if={submit[:note]} class="note">{submit[:note]}</span>
      </div>
    </form>
    """
  end

  # the Turnstile widget (when configured) in its own block; it follows
  # the footer's light/dark choice, the system's otherwise
  attr :error, :string, default: nil

  defp bot_guard(assigns) do
    assigns = assign(assigns, :site_key, CabWeb.Turnstile.site_key())

    ~H"""
    <div :if={@site_key} class={["f-block", "f-guard", @error && "err"]}>
      <div
        class="cf-turnstile"
        data-sitekey={@site_key}
        data-language={Gettext.get_locale(CabWeb.Gettext)}
        data-theme="auto"
        data-size="flexible"
      >
      </div>
      <div :if={@error} class="error">{@error}</div>
      <script>
        (() => {
          const theme = document.documentElement.dataset.theme
          if (theme === "light" || theme === "dark")
            document.querySelectorAll(".cf-turnstile").forEach((el) => (el.dataset.theme = theme))
        })()
      </script>
      <script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer>
      </script>
    </div>
    """
  end

  defp control(block) do
    assigns = %{b: block, name: to_string(block[:name] || "")}

    case block[:type] || :text do
      :text ->
        ~H"""
        <input
          type={@b[:input] || "text"}
          name={@name}
          value={@b[:value]}
          placeholder={@b[:placeholder]}
          maxlength={@b[:maxlength]}
          list={@b[:list]}
        />
        """

      :longtext ->
        ~H"""
        <textarea rows="3" name={@name} placeholder={@b[:placeholder]} maxlength={@b[:maxlength]}>{@b[:value]}</textarea>
        """

      :int ->
        ~H|<input type="number" name={@name} value={@b[:value]} min={@b[:min]} max={@b[:max]} />|

      :float ->
        ~H"""
        <input
          type="number"
          name={@name}
          value={@b[:value]}
          min={@b[:min]}
          max={@b[:max]}
          step={@b[:step]}
          style="width:130px"
        />
        """

      :scale ->
        ~H"""
        <div class="scale">
          <label :for={i <- (@b[:min] || 1)..(@b[:max] || 5)}>
            <input type="radio" name={@name} value={i} checked={same?(@b[:value], i)} />
            <span>{i}</span>
          </label>
        </div>
        """

      :yesno ->
        ~H"""
        <div class="pills">
          <label>
            <input type="radio" name={@name} value="yes" checked={@b[:value] in [true, "yes"]} />
            <span>{gettext("Yes")}</span>
          </label>
          <label>
            <input type="radio" name={@name} value="no" checked={@b[:value] in [false, "no"]} />
            <span>{gettext("No")}</span>
          </label>
        </div>
        """

      :select ->
        options = Enum.map(block[:options] || [], &option/1)
        assigns = Map.put(assigns, :options, options)

        if length(options) <= 4 do
          ~H"""
          <div class="pills-field">
            <div class="pills">
              <label :for={{label, value} <- @options}>
                <input type="radio" name={@name} value={value} checked={same?(@b[:value], value)} />
                <span>{label}</span>
              </label>
            </div>
            <input
              :if={@b[:other]}
              type="text"
              class="pills-other"
              name={to_string(@b[:other_name])}
              value={@b[:other_value]}
              placeholder={@b[:other_placeholder]}
              maxlength="60"
              aria-label={@b[:other_placeholder]}
            />
          </div>
          """
        else
          ~H"""
          <select name={@name}>
            <option :if={@b[:prompt]} value="">{@b[:prompt]}</option>
            <option :for={{label, value} <- @options} value={value} selected={same?(@b[:value], value)}>
              {label}
            </option>
          </select>
          """
        end

      :multi ->
        assigns = Map.put(assigns, :options, Enum.map(block[:options] || [], &option/1))

        ~H"""
        <div class="opts">
          <label :for={{label, value} <- @options}>
            <input
              type="checkbox"
              name={@name <> "[]"}
              value={value}
              checked={value in List.wrap(@b[:value])}
            />
            {label}
          </label>
        </div>
        """

      :check ->
        ~H"""
        <div class="opts">
          <label>
            <input type="checkbox" name={@name} value="yes" checked={@b[:value] in [true, "yes"]} />
            {gettext("Yes")}
          </label>
        </div>
        """

      :file ->
        ~H"""
        <div class="file-field">
          <img
            :if={@b[:preview]}
            class="club-logo lg"
            src={@b[:preview]}
            alt={@b[:preview_alt] || ""}
          />
          <input type="file" name={@name} accept={@b[:accept]} aria-label={@b[:label]} />
          <label :if={@b[:preview] && @b[:remove]} class="file-remove">
            <input type="checkbox" name={@b[:remove]} value="yes" />
            {@b[:remove_label]}
          </label>
        </div>
        """

      :datetime ->
        [date_name, time_name] = Enum.map(block[:names] || [:date, :time], &to_string/1)
        [date_value, time_value] = block[:values] || [nil, nil]

        assigns =
          Map.merge(assigns, %{
            date_name: date_name,
            time_name: time_name,
            date_value: date_value,
            time_value: time_value
          })

        ~H"""
        <div class="half">
          <input
            type="text"
            name={@date_name}
            value={@date_value}
            placeholder={gettext("YYYY-MM-DD")}
          />
          <input type="text" name={@time_name} value={@time_value} placeholder={gettext("HH:MM")} />
        </div>
        """
    end
  end

  defp option({label, value}), do: {label, value}
  defp option(value), do: {value, value}

  defp same?(nil, _candidate), do: false
  defp same?(value, candidate), do: to_string(value) == to_string(candidate)

  @doc """
  A club's logo (CabWeb.ClubProfile.logo_path/1), nothing without one.
  Decorative: the club's name always stands next to it.
  """
  attr :club, :map, required: true
  attr :size, :atom, default: :sm, values: [:sm, :lg]

  def club_logo(assigns) do
    ~H"""
    <img
      :if={CabWeb.ClubProfile.logo_path(@club)}
      class={if @size == :lg, do: "club-logo lg", else: "club-logo"}
      src={CabWeb.ClubProfile.logo_path(@club)}
      alt=""
    />
    """
  end

  # ---------------------------------------------------------------
  # 4. Ballot
  # ---------------------------------------------------------------

  @doc """
  The scored BP ballot (club sessions, tournament prelims): motion
  header, one color block per team side (OG violet, OO blue, CG
  green, CO amber), position rows = speaker dropdown + iron check +
  score input (whole points, 50-100). Team totals and ranks DERIVE live
  (the BallotMath hook); tied totals mark both blocks amber - BP forbids ties.
  Submit lives in the chrome, not here.

  `teams` is a list of `%{side: :og, name: "...", rows: [...]}` where
  each row is `%{role: "PM", speakers: [{label, value}], selected:
  value, iron: boolean, score: number}`. A team may carry
  `tied: true` - its total block renders the amber tied state.

  Server errors re-render the same page: pass the message as `error`
  and it replaces the footer line in the amber style, with the
  offending teams marked tied.
  """
  attr :id, :string, default: nil
  attr :room, :string, default: nil
  attr :motion, :string, default: nil
  attr :teams, :list, required: true
  attr :error, :string, default: nil, doc: "server-side validation message (amber footer)"
  attr :action, :string, default: nil, doc: "POSTs to the in-tree ballot twin action"

  def ballot(assigns) do
    ~H"""
    <form class="ballot" id={@id} action={@action} method="post" phx-hook="BallotMath">
      <input :if={@action} type="hidden" name="_csrf_token" value={get_csrf_token()} />
      <div class="b-motion">
        <span class="k">
          {if @room, do: gettext("Motion — %{room}", room: @room), else: gettext("Motion")}
        </span>
        <b>{@motion}</b>
      </div>
      <div class="bgrid" data-ballot>
        <div :for={team <- @teams} class={["bteam", to_string(team.side)]}>
          <div class="side">
            <span class="pos">{side_label(team.side)}</span>
            <span class="tname">{team.name}</span>
          </div>
          <div :for={row <- team.rows} class="brow">
            <span class="role">{Map.get(row, :role_label, row.role)}</span>
            <select class="who" name={"ballot[#{team.side}][#{row.role}][speaker]"}>
              <option
                :for={{label, value} <- Enum.map(row[:speakers] || [], &option/1)}
                value={value}
                selected={same?(row[:selected], value)}
              >
                {label}
              </option>
            </select>
            <span class="iron">
              <input
                type="checkbox"
                name={"ballot[#{team.side}][#{row.role}][iron]"}
                checked={row[:iron]}
              /> {gettext("iron")}
            </span>
            <input
              type="number"
              name={"ballot[#{team.side}][#{row.role}][score]"}
              min="50"
              max="100"
              step="1"
              value={row[:score]}
            />
          </div>
          <div class={if team[:tied], do: "bsum tied", else: "bsum"}>
            <span>{gettext("team total")}</span><span class="tot">—</span><span class="rk">—</span>
          </div>
        </div>
      </div>
      <div class="bfoot">
        <%= if @error do %>
          <span class="err server">{@error}</span>
        <% else %>
          {gettext("Enter all eight scores — ranks derive from team totals.")}
        <% end %>
      </div>
    </form>
    """
  end

  defp side_label(:og), do: gettext("OG — OPENING GOV")
  defp side_label(:oo), do: gettext("OO — OPENING OPP")
  defp side_label(:cg), do: gettext("CG — CLOSING GOV")
  defp side_label(:co), do: gettext("CO — CLOSING OPP")
  defp side_label(side), do: side |> to_string() |> String.upcase()

  # ---------------------------------------------------------------
  # 5. Allocator (drag-and-drop, server-held draft)
  # ---------------------------------------------------------------

  @alloc_sides ~w(og oo cg co)

  defp side_short("og"), do: gettext("OG")
  defp side_short("oo"), do: gettext("OO")
  defp side_short("cg"), do: gettext("CG")
  defp side_short("co"), do: gettext("CO")

  @doc """
  The allocation surface (tabbycat's drag-and-drop model), rendered
  from the SERVER-HELD draft: a tray of everyone not placed yet over
  one row per room whose slots carry their key ("1:og:2", "1:judge").
  The Allocator hook only reports drops - `place {id, slot}` or
  `unplace {id}` - and the server re-renders, so new signups simply
  appear in the tray and nothing is ever placed automatically.

  `people` maps participant id => `%{id, name}` - registration carries
  no role, so anyone fits any slot and the drag decides who judges;
  `draft` maps slot key => participant id. The hidden form
  `form_id` carries the submit (the chrome's gold segment).

  With `count_event`, a room-count bar sits on top: - and + push that
  event with `rooms` one fewer or one more (1 to `max_rooms`), and
  Automatic (lit while `auto`) pushes `rooms: "automatic"`.
  """
  attr :id, :string, default: "allocator"
  attr :rooms, :integer, required: true
  attr :auto, :boolean, default: true, doc: "the room count follows the sign-ups"
  attr :max_rooms, :integer, default: 20
  attr :count_event, :string, default: nil, doc: "the room-count bar's phx-click event"
  attr :people, :map, required: true
  attr :draft, :map, required: true
  attr :form_id, :string, required: true
  attr :submit, :string, required: true, doc: "the phx-submit event of the hidden form"

  def allocator(assigns) do
    placed = MapSet.new(Map.values(assigns.draft))

    tray =
      assigns.people
      |> Map.values()
      |> Enum.reject(&MapSet.member?(placed, &1.id))
      |> Enum.sort_by(& &1.name)

    assigns = assign(assigns, sides: @alloc_sides, tray: tray)

    ~H"""
    <div class="dnd" id={@id} phx-hook="Allocator">
      <div :if={@count_event} class="rcount">
        <span class="tlabel">{gettext("Rooms")}</span>
        <.stepper
          event={@count_event}
          name="rooms"
          prev={@rooms - 1}
          next={@rooms + 1}
          prev_off={@rooms <= 1}
          next_off={@rooms >= @max_rooms}
          prev_text="-"
          next_text="+"
          prev_label={gettext("One room fewer")}
          next_label={gettext("One room more")}
        >
          {@rooms}
        </.stepper>
        <button
          type="button"
          class={["auto", @auto && "on"]}
          phx-click={@count_event}
          phx-value-rooms="automatic"
          aria-pressed={to_string(@auto)}
        >
          {gettext("Automatic")}
        </button>
      </div>
      <div class="tray" data-drop="tray">
        <span class="tlabel">{gettext("Waiting (%{count})", count: length(@tray))}</span>
        <.chip :for={person <- @tray} person={person} />
      </div>
      <table>
        <colgroup>
          <col class="c-room" />
          <col :for={_side <- @sides} />
          <col />
          <col class="c-status" />
        </colgroup>
        <thead>
          <tr>
            <th></th>
            <th>{gettext("OG")}</th>
            <th>{gettext("OO")}</th>
            <th>{gettext("CG")}</th>
            <th>{gettext("CO")}</th>
            <th>{gettext("Adjudicator")}</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={room <- 1..@rooms}>
            <td class="room">{gettext("R%{number}", number: room)}</td>
            <td :for={side <- @sides} class={"team t-#{side}"} data-side={side_short(side)}>
              <div
                :for={n <- 1..2}
                class="slot"
                data-slot={"#{room}:#{side}:#{n}"}
              >
                <%= if person = placed(@people, @draft, "#{room}:#{side}:#{n}") do %>
                  <.chip person={person} tag={:spk} />
                <% end %>
              </div>
            </td>
            <td class="judge" data-side={gettext("Adjudicator")}>
              <div class="slot" data-slot={"#{room}:judge"}>
                <%= if person = placed(@people, @draft, "#{room}:judge") do %>
                  <.chip person={person} tag={:adj} />
                <% end %>
              </div>
            </td>
            <td class="status">{allocation_words(@draft, room)}</td>
          </tr>
        </tbody>
      </table>
      <form id={@form_id} phx-submit={@submit}></form>
      <div class="bfoot">
        {gettext(
          "Drag chips into slots; drop on a taken slot to swap; drag a placed chip out of the table to unassign. A team with one speaker becomes an iron."
        )}
        <span class="touch-hint">
          {gettext(
            "On a touch screen, hold a person and drag them to a slot, or tap a person, then a slot."
          )}
        </span>
      </div>
    </div>
    """
  end

  attr :person, :map, required: true
  attr :tag, :atom, default: nil, doc: "the seat's role once placed: :spk or :adj"

  defp chip(assigns) do
    ~H"""
    <span class={["chip", @tag == :adj && "adj"]} draggable="true" data-id={@person.id}>
      <span class="n" title={@person.name}>{@person.name}</span><span :if={@tag} class="k">{tag_word(
        @tag
      )}</span>
    </span>
    """
  end

  defp tag_word(:spk), do: gettext("SPK")
  defp tag_word(:adj), do: gettext("ADJ")

  defp placed(people, draft, key), do: draft[key] && people[draft[key]]

  # a row's state in words: empty / incomplete / ready (+ irons)
  defp allocation_words(draft, room) do
    teams =
      for side <- @alloc_sides do
        Enum.count(1..2, &draft["#{room}:#{side}:#{&1}"])
      end

    judge? = draft["#{room}:judge"] != nil
    irons = Enum.count(teams, &(&1 == 1))

    cond do
      Enum.sum(teams) == 0 and not judge? ->
        gettext("empty")

      Enum.all?(teams, &(&1 >= 1)) and judge? and irons > 0 ->
        gettext("ready, %{count} iron", count: irons)

      Enum.all?(teams, &(&1 >= 1)) and judge? ->
        gettext("ready")

      true ->
        gettext("incomplete")
    end
  end

  # ---------------------------------------------------------------
  # Rest of the kit: banner, copy, section
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
  the full URL in mono, and the copy button. Used for the shared
  registration URL (owner page) and the personal guest links.
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
  The only layout primitive: uppercase micro-title + card. Every page
  is a chrome bar and a stack of sections. `pad` wraps the content in
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
end
