defmodule CabWeb.Ui do
  @moduledoc """
  The design-system kit, ported from `design/components-v2.html` and
  `design/pages-v2.html`: the 4 core components (chrome/action bar,
  table, form, ballot) plus the 3 extras (tag, banner, section).

  Every page is a chrome bar and a stack of sections — nothing
  actionable exists outside the chrome, and no element outside this
  kit may appear on a page (whitelist doctrine).
  """

  use Phoenix.Component

  import Phoenix.Controller, only: [get_csrf_token: 0]

  use Phoenix.VerifiedRoutes,
    endpoint: CabWeb.Endpoint,
    router: CabWeb.Router,
    statics: CabWeb.static_paths()

  # ---------------------------------------------------------------
  # 1 · Chrome / action bar
  # ---------------------------------------------------------------

  @doc """
  The control mechanism of every page (pages-v6): crumb + THIS page's
  actions only, as flush tape-deck segments — navigation and the
  profile live in the sidenav, status lives in the page content as
  words. Max one `primary` (gold) segment per page; `quiet` =
  destructive or exit.

  A segment with `form` renders as that form's submit button instead
  of a link — the design's "submit lives in the chrome" rule for the
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

  @doc """
  The left sidenav (pages-v6 shell) — ONLY navigation: brand script
  cap -> home, plain place-name items for the current context
  (global: Clubs / Standings / + Admin for admins; club: Club /
  Rooms / Sessions / Standings / Members) and the profile block
  pinned to the bottom (avatar initials + username -> /account, sign
  out; anonymous: Sign in). No badges, counters or suffixes; the
  active item carries a left border.
  """
  attr :current_user, :any, default: nil
  attr :club, :any, default: nil, doc: "club context; nil = global"
  attr :club_role, :atom, default: :public
  attr :nav_session, :any, default: nil, doc: "the club's newest session row (Rooms target)"
  attr :active, :string, default: nil, doc: "the lit item key"

  def sidenav(assigns) do
    ~H"""
    <nav class="sidenav" id="sidenav">
      <.link href={~p"/"} class="cap">cab</.link>
      <%= if @club do %>
        <div class="sec">{@club.name}</div>
        <.nav_item active={@active} key="club" href={club_href(@club, @club_role)} label="Club" />
        <.nav_item
          active={@active}
          key="rooms"
          href={rooms_href(@club, @club_role, @nav_session)}
          label="Rooms"
        />
        <.nav_item
          active={@active}
          key="sessions"
          href={sessions_href(@club, @club_role)}
          label="Sessions"
        />
        <.nav_item
          active={@active}
          key="standings"
          href={~p"/c/#{@club.uuid}/standings/teams"}
          label="Standings"
        />
        <.nav_item
          active={@active}
          key="members"
          href={members_href(@club, @club_role)}
          label="Members"
        />
      <% else %>
        <.nav_item active={@active} key="clubs" href={~p"/"} label="Clubs" />
        <.nav_item active={@active} key="standings" href={~p"/standings/teams"} label="Standings" />
        <.nav_item
          :if={@current_user && @current_user.is_admin}
          active={@active}
          key="admin"
          href={~p"/admin"}
          label="Admin"
        />
      <% end %>
      <div class="profile" id="sidenav-profile">
        <%= if @current_user do %>
          <div class="who">
            <span class="av">{initials(@current_user)}</span>
            <.link href={~p"/account"}>{@current_user.username}</.link>
          </div>
          <.link class="out" href={~p"/auth/logout"}>sign out</.link>
        <% else %>
          <.link href={~p"/signin"}>Sign in</.link>
        <% end %>
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

  defp club_href(club, :owner), do: ~p"/c/#{club.uuid}/owner"
  defp club_href(club, _role), do: ~p"/c/#{club.uuid}"

  # the LIVE session lives under Rooms; with no session yet the item
  # falls back to the archive (owner opens new sessions there)
  defp rooms_href(club, :owner, %{uuid: uuid}), do: ~p"/c/#{club.uuid}/owner/s/#{uuid}"
  defp rooms_href(club, _role, %{uuid: uuid}), do: ~p"/c/#{club.uuid}/s/#{uuid}"
  defp rooms_href(club, role, nil), do: sessions_href(club, role)

  defp sessions_href(club, :owner), do: ~p"/c/#{club.uuid}/owner/sessions"
  defp sessions_href(club, _role), do: ~p"/c/#{club.uuid}/member/sessions"

  defp members_href(club, :owner), do: ~p"/c/#{club.uuid}/owner/members"
  defp members_href(club, _role), do: ~p"/c/#{club.uuid}/member/members"

  defp initials(user) do
    (user.name || user.username || "?")
    |> String.split()
    |> Enum.take(2)
    |> Enum.map(&String.first/1)
    |> Enum.join()
    |> String.upcase()
  end

  @doc """
  The tab row under the chrome (pages-v6 `.selrow`) — picks WHICH
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
  # 2 · Table / standings
  # ---------------------------------------------------------------

  @doc """
  One table for everything tabular. Cell formats via `:col` flags:
  `code` (mono), `num` (right-aligned tabular), `float` (same),
  `center`; table flags `rank` (violet # column) and `check`
  (bulk-ops checkbox column, header selects all — pass `true` or a
  `row -> boolean` function for the checked state). `sort` on a
  column makes the header client-side sortable. Empty rows render
  one centered muted line.

      <.table id="speakers" rows={@speakers} rank>
        <:col :let={s} label="Speaker" sort="name">{s.name}<.sub>{s.club}</.sub></:col>
        <:col :let={s} label="Team" code>{s.team_key}</:col>
        <:col :let={s} label="Avg spk" sort="avg" float>{s.avg}</:col>
      </.table>
  """
  attr :id, :string, default: nil
  attr :rows, :list, required: true
  attr :rank, :boolean, default: false
  attr :check, :any, default: false
  attr :row_id, :any, default: nil, doc: "row -> dom id"

  attr :row_class, :any,
    default: nil,
    doc: "row -> extra tr class (e.g. the viewer's \"me\" tint)"

  attr :empty, :string, default: "Nothing here yet."

  slot :col do
    attr :label, :string
    attr :sort, :string, doc: "client-side sort key; marks the header sortable"
    attr :num, :boolean
    attr :float, :boolean
    attr :code, :boolean
    attr :center, :boolean
    attr :class, :string, doc: "extra td class (the draw table's side color bands)"
  end

  def table(assigns) do
    ~H"""
    <table class="t" id={@id}>
      <thead>
        <tr>
          <th :if={@check != false} class="c" style="width:36px">
            <input type="checkbox" data-check-all />
          </th>
          <th :if={@rank} style="width:40px">#</th>
          <th
            :for={col <- @col}
            class={[col[:sort] && "sort", (col[:num] || col[:float]) && "num", col[:center] && "c"]}
            data-k={col[:sort]}
          >
            {col[:label]}
          </th>
        </tr>
      </thead>
      <tbody>
        <tr :if={@rows == []}>
          <td
            class="empty"
            colspan={length(@col) + ((@rank && 1) || 0) + ((@check != false && 1) || 0)}
          >
            {@empty}
          </td>
        </tr>
        <tr
          :for={{row, index} <- Enum.with_index(@rows, 1)}
          id={@row_id && @row_id.(row)}
          class={@row_class && @row_class.(row)}
        >
          <td :if={@check != false} class="c">
            <input type="checkbox" checked={checked?(@check, row)} />
          </td>
          <td :if={@rank} class="rank">{index}</td>
          <td
            :for={col <- @col}
            class={[
              col[:code] && "code",
              (col[:num] || col[:float]) && "num",
              col[:center] && "c",
              col[:class]
            ]}
          >
            {render_slot(col, row)}
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  defp checked?(check, row) when is_function(check, 1), do: !!check.(row)
  defp checked?(_check, _row), do: false

  @doc "The optional muted sub-line inside a table cell."
  slot :inner_block, required: true

  def sub(assigns) do
    ~H"""
    <span class="sub">{render_slot(@inner_block)}</span>
    """
  end

  # ---------------------------------------------------------------
  # 3 · Form
  # ---------------------------------------------------------------

  @doc """
  One form component for every write: violet top rule, head block
  (title + description), field blocks divided by hairlines, tinted
  submit block with one gold button + consequence note. POSTs to the
  same REST action the API exposes.

  Block types (the complete inventory): `:text`, `:longtext`, `:int`,
  `:float`, `:scale` (flush integer segments), `:yesno` (two pills),
  `:select` (pills at 2-4 options, dropdown at 5+), `:multi` (stacked
  checks), `:datetime` (half-split pair, pass `names`).

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
  end

  slot :submit do
    attr :note, :string
  end

  def form_for(assigns) do
    ~H"""
    <form class="form" id={@id} action={@action} method={@method}>
      <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
      <input :for={{name, value} <- @hidden} type="hidden" name={name} value={value} />
      <div :if={@title || @description} class="f-head">
        <h3 :if={@title}>{@title}</h3>
        <p :if={@description}>{@description}</p>
      </div>
      <div :for={block <- @block} class={["f-block", @errors[block[:name]] && "err"]}>
        <label :if={block[:label]} class="q">
          {block[:label]} <span :if={block[:required]} class="req">*</span>
        </label>
        {control(block)}
        <div :if={@errors[block[:name]]} class="error">{@errors[block[:name]]}</div>
        <div :if={block[:hint] && !@errors[block[:name]]} class="hint">{block[:hint]}</div>
      </div>
      <div :for={submit <- @submit} class="f-submit">
        <button type="submit" class="btn-go">{render_slot(submit)}</button>
        <span :if={submit[:note]} class="note">{submit[:note]}</span>
      </div>
    </form>
    """
  end

  defp control(block) do
    assigns = %{b: block, name: to_string(block[:name] || "")}

    case block[:type] || :text do
      :text ->
        ~H|<input type="text" name={@name} value={@b[:value]} placeholder={@b[:placeholder]} />|

      :longtext ->
        ~H|<textarea rows="3" name={@name} placeholder={@b[:placeholder]}>{@b[:value]}</textarea>|

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
            <span>Yes</span>
          </label>
          <label>
            <input type="radio" name={@name} value="no" checked={@b[:value] in [false, "no"]} />
            <span>No</span>
          </label>
        </div>
        """

      :select ->
        options = Enum.map(block[:options] || [], &option/1)
        assigns = Map.put(assigns, :options, options)

        if length(options) <= 4 do
          ~H"""
          <div class="pills">
            <label :for={{label, value} <- @options}>
              <input type="radio" name={@name} value={value} checked={same?(@b[:value], value)} />
              <span>{label}</span>
            </label>
          </div>
          """
        else
          ~H"""
          <select name={@name}>
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
          <input type="text" name={@date_name} value={@date_value} placeholder="YYYY-MM-DD" />
          <input type="text" name={@time_name} value={@time_value} placeholder="HH:MM" />
        </div>
        """
    end
  end

  defp option({label, value}), do: {label, value}
  defp option(value), do: {value, value}

  defp same?(nil, _candidate), do: false
  defp same?(value, candidate), do: to_string(value) == to_string(candidate)

  # ---------------------------------------------------------------
  # 4 · Ballot
  # ---------------------------------------------------------------

  @sides %{
    og: "OG · OPENING GOV",
    oo: "OO · OPENING OPP",
    cg: "CG · CLOSING GOV",
    co: "CO · CLOSING OPP"
  }

  @doc """
  The scored BP ballot (club sessions, tournament prelims): motion
  header, one color block per team side (OG violet, OO blue, CG
  green, CO amber), position rows = speaker dropdown + iron check +
  score input (50-100, step 0.5). Team totals and ranks DERIVE live
  (vanilla JS); tied totals mark both blocks amber — BP forbids ties.
  Submit lives in the chrome, not here.

  `teams` is a list of `%{side: :og, name: "...", rows: [...]}` where
  each row is `%{role: "PM", speakers: [{label, value}], selected:
  value, iron: boolean, score: number}`. A team may carry
  `tied: true` — its total block renders the amber tied state.

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
    <form class="ballot" id={@id} action={@action} method="post">
      <input :if={@action} type="hidden" name="_csrf_token" value={get_csrf_token()} />
      <div class="b-motion">
        <span class="k">Motion{@room && " · #{@room}"}</span>
        <b>{@motion}</b>
      </div>
      <div class="bgrid" data-ballot>
        <div :for={team <- @teams} class={["bteam", to_string(team.side)]}>
          <div class="side">
            <span class="pos">{side_label(team.side)}</span>
            <span class="tname">{team.name}</span>
          </div>
          <div :for={row <- team.rows} class="brow">
            <span class="role">{row.role}</span>
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
              /> iron
            </span>
            <input
              type="number"
              name={"ballot[#{team.side}][#{row.role}][score]"}
              min="50"
              max="100"
              step="0.5"
              value={row[:score]}
            />
          </div>
          <div class={if team[:tied], do: "bsum tied", else: "bsum"}>
            <span>team total</span><span class="tot">—</span><span class="rk">—</span>
          </div>
        </div>
      </div>
      <div class="bfoot">
        <%= if @error do %>
          <span class="err">{@error}</span>
        <% else %>
          Enter all eight scores — ranks derive from team totals.
        <% end %>
      </div>
    </form>
    """
  end

  @doc """
  The elimination ballot (tournaments): checkbox only — tick who
  passes, exactly `advance` ticks required (live-validated). No
  order, no scores. `teams` is `%{side:, name:, advances: boolean}`.
  """
  attr :id, :string, default: nil
  attr :room, :string, default: nil
  attr :advance, :integer, required: true
  attr :prompt, :string, default: nil
  attr :teams, :list, required: true
  attr :action, :string, default: nil, doc: "wired in M3; render-only until then"

  def elim_ballot(assigns) do
    ~H"""
    <form class="ballot elim" id={@id} action={@action} method="post">
      <input :if={@action} type="hidden" name="_csrf_token" value={get_csrf_token()} />
      <div class="b-motion">
        <span class="k">{@room}</span>
        <b>{@prompt || "Order the teams. Top #{@advance} advance."}</b>
      </div>
      <div class="bgrid" data-advance={@advance}>
        <div :for={team <- @teams} class={["bteam", to_string(team.side)]}>
          <div class="side">
            <span class="pos">{team.side |> to_string() |> String.upcase()}</span>
            <span class="tname">{team.name}</span>
          </div>
          <div class="brow">
            <input type="checkbox" name={"advance[#{team.side}]"} checked={team[:advances]} />
            <span class="who">advances</span>
          </div>
        </div>
      </div>
      <div class="bfoot">Tick exactly {@advance} teams.</div>
    </form>
    """
  end

  defp side_label(side), do: @sides[side] || side |> to_string() |> String.upcase()

  # ---------------------------------------------------------------
  # 5 · Drag-and-drop table (allocations)
  # ---------------------------------------------------------------

  @dnd_sides ~w(og oo cg co)

  @doc """
  The console allocation surface (tabbycat's draganddrop model) — the
  ONLY allocation UI, never dropdowns or swap controls for
  allocation: a tray of unallocated chips (name + SPK/JUDGE mark,
  judges blue) above a table whose team cells are dashed drop slots
  with the ballot's side color bands. Chip kinds gate targets,
  dropping on an occupied slot swaps (the displaced chip returns to
  the dragged chip's origin), dragging to the tray unassigns; each
  row carries a live status — empty / incomplete / ready + iron xN
  (a 1-speaker team is a declared iron).

  Slots mirror hidden inputs named `rooms[N][og][1]` …
  `rooms[N][judge]`, so the submit is the SAME plain POST the
  composition endpoint takes — drag-and-drop is presentation, not
  transport. The submit button lives in the chrome
  (`<:seg form={id}>`), like the ballot. Behavior is the dnd widget
  in assets/js/app.js (vanilla JS, no frameworks).

  `tray` entries are `%{id, name, kind}` with kind "spk" | "judge".
  """
  attr :id, :string, required: true
  attr :action, :string, required: true
  attr :rooms, :integer, required: true, doc: "row count, derived from attendance"
  attr :tray, :list, required: true

  attr :note, :string,
    default:
      "Drag chips into slots; drop on an occupied slot to swap; drag back " <>
        "to the tray to unassign. A team with one speaker becomes an iron."

  def dnd_table(assigns) do
    assigns = assign(assigns, :sides, @dnd_sides)

    ~H"""
    <form class="dnd" id={@id} action={@action} method="post" data-dnd>
      <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
      <div class="tray" data-tray>
        <span class="tlabel">Unallocated · <span data-tray-count>{length(@tray)}</span></span>
        <span
          :for={chip <- @tray}
          class={["chip", chip.kind == "judge" && "judge"]}
          draggable="true"
          data-kind={chip.kind}
          data-id={chip.id}
        >
          {chip.name} <span class="k">{if chip.kind == "judge", do: "JUDGE", else: "SPK"}</span>
        </span>
      </div>
      <table>
        <thead>
          <tr>
            <th></th>
            <th>OG</th>
            <th>OO</th>
            <th>CG</th>
            <th>CO</th>
            <th>Judge</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={room <- 1..@rooms} data-room={room}>
            <td class="room">R{room}</td>
            <td :for={side <- @sides} class={"team t-#{side}"}>
              <div :for={slot <- 1..2} class="slot" data-kind="spk">
                <input type="hidden" name={"rooms[#{room}][#{side}][#{slot}]"} value="" />
              </div>
            </td>
            <td>
              <div class="slot" data-kind="judge">
                <input type="hidden" name={"rooms[#{room}][judge]"} value="" />
              </div>
            </td>
            <td class="status"><span class="tag tag-mut">empty</span></td>
          </tr>
        </tbody>
      </table>
      <div class="bfoot">{@note}</div>
    </form>
    """
  end

  # ---------------------------------------------------------------
  # Rest of the kit: tag, banner, section
  # ---------------------------------------------------------------

  @doc "Status tag: three kinds, used inside the chrome and table cells."
  attr :kind, :atom, default: :mut, values: [:ok, :warn, :mut]
  slot :inner_block, required: true

  def tag(assigns) do
    ~H"""
    <span class={"tag tag-#{@kind}"}>{render_slot(@inner_block)}</span>
    """
  end

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
  The copy-to-clipboard affordance: a small button that writes `text`
  to the clipboard (vanilla JS `[data-copy]` handler in app.js).
  """
  attr :text, :string, required: true

  def copy(assigns) do
    ~H"""
    <button type="button" class="copy" data-copy={@text}>copy</button>
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
