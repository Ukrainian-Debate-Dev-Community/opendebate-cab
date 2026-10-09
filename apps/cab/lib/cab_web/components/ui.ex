defmodule CabWeb.Ui do
  @moduledoc """
  The design-system kit: the core components (chrome/action bar,
  sidenav, table, form, ballot, allocator) plus banner and section.

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
  # 1. Chrome / action bar
  # ---------------------------------------------------------------

  @doc """
  The control mechanism of every page: crumb + THIS page's
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
  The left sidenav — ONLY navigation: brand script cap -> home, plain
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
          key="standings"
          href={~p"/c/#{@club.uuid}/standings/teams"}
          label="Standings"
        />
        <.nav_item
          :if={not @club.is_private or Cab.Clubs.covers?(@club_role, :member)}
          active={@active}
          key="members"
          href={members_href(@club, @club_role)}
          label="Members"
        />
        <.nav_item
          :if={@nav_session}
          active={@active}
          key="register"
          href={~p"/r/#{@nav_session.uuid}"}
          label="Register"
        />
      <% else %>
        <.nav_item active={@active} key="clubs" href={~p"/"} label="Clubs" />
        <.nav_item active={@active} key="standings" href={~p"/standings/teams"} label="Standings" />
        <.nav_item :if={@current_user} active={@active} key="me" href={~p"/me"} label="My page" />
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

  defp initials(user) do
    (user.name || user.username || "?")
    |> String.split()
    |> Enum.take(2)
    |> Enum.map(&String.first/1)
    |> Enum.join()
    |> String.upcase()
  end

  @doc """
  The tab row under the chrome (`.selrow`) — picks WHICH
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

  attr :empty, :string, default: "Nothing here yet."

  slot :col do
    attr :label, :string
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
          <th :if={@rank} style="width:40px">#</th>
          <th
            :for={col <- @col}
            class={[(col[:num] || col[:float]) && "num", col[:center] && "c"]}
          >
            {col[:label]}
          </th>
        </tr>
      </thead>
      <tbody>
        <tr :if={@rows == []}>
          <td
            class="empty"
            colspan={length(@col) + ((@rank && 1) || 0)}
          >
            {@empty}
          </td>
        </tr>
        <tr
          :for={{row, index} <- Enum.with_index(@rows, 1)}
          id={@row_id && @row_id.(row)}
          class={@row_class && @row_class.(row)}
        >
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
  # 4. Ballot
  # ---------------------------------------------------------------

  @sides %{
    og: "OG — OPENING GOV",
    oo: "OO — OPENING OPP",
    cg: "CG — CLOSING GOV",
    co: "CO — CLOSING OPP"
  }

  @doc """
  The scored BP ballot (club sessions, tournament prelims): motion
  header, one color block per team side (OG violet, OO blue, CG
  green, CO amber), position rows = speaker dropdown + iron check +
  score input (whole points, 50-100). Team totals and ranks DERIVE live
  (the BallotMath hook); tied totals mark both blocks amber — BP forbids ties.
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
    <form class="ballot" id={@id} action={@action} method="post" phx-hook="BallotMath">
      <input :if={@action} type="hidden" name="_csrf_token" value={get_csrf_token()} />
      <div class="b-motion">
        <span class="k">Motion{@room && " — #{@room}"}</span>
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
              step="1"
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
          <span class="err server">{@error}</span>
        <% else %>
          Enter all eight scores — ranks derive from team totals.
        <% end %>
      </div>
    </form>
    """
  end

  defp side_label(side), do: @sides[side] || side |> to_string() |> String.upcase()

  # ---------------------------------------------------------------
  # 5. Allocator (drag-and-drop, server-held draft)
  # ---------------------------------------------------------------

  @alloc_sides ~w(og oo cg co)

  @doc """
  The allocation surface (tabbycat's drag-and-drop model), rendered
  from the SERVER-HELD draft: a tray of everyone not placed yet over
  one row per room whose slots carry their key ("1:og:2", "1:judge").
  The Allocator hook only reports drops — `place {id, slot}` or
  `unplace {id}` — and the server re-renders, so new signups simply
  appear in the tray and nothing is ever placed automatically.

  `people` maps participant id => `%{id, name}` — registration carries
  no role, so anyone fits any slot and the drag decides who judges;
  `draft` maps slot key => participant id. The hidden form
  `form_id` carries the submit (the chrome's gold segment).
  """
  attr :id, :string, default: "allocator"
  attr :rooms, :integer, required: true
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
      <div class="tray" data-drop="tray">
        <span class="tlabel">Unallocated ({length(@tray)})</span>
        <.chip :for={person <- @tray} person={person} />
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
          <tr :for={room <- 1..@rooms}>
            <td class="room">R{room}</td>
            <td :for={side <- @sides} class={"team t-#{side}"}>
              <div
                :for={n <- 1..2}
                class="slot"
                data-slot={"#{room}:#{side}:#{n}"}
              >
                <%= if person = placed(@people, @draft, "#{room}:#{side}:#{n}") do %>
                  <.chip person={person} />
                <% end %>
              </div>
            </td>
            <td>
              <div class="slot" data-slot={"#{room}:judge"}>
                <%= if person = placed(@people, @draft, "#{room}:judge") do %>
                  <.chip person={person} />
                <% end %>
              </div>
            </td>
            <td class="status">{allocation_words(@draft, room)}</td>
          </tr>
        </tbody>
      </table>
      <form id={@form_id} phx-submit={@submit}></form>
      <div class="bfoot">
        Drag chips into slots; drop on a taken slot to swap; drag back to the
        tray to unassign. A team with one speaker becomes an iron.
      </div>
    </div>
    """
  end

  attr :person, :map, required: true

  defp chip(assigns) do
    ~H"""
    <span class="chip" draggable="true" data-id={@person.id}>{@person.name}</span>
    """
  end

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
      Enum.sum(teams) == 0 and not judge? -> "empty"
      Enum.all?(teams, &(&1 >= 1)) and judge? and irons > 0 -> "ready, #{irons} iron"
      Enum.all?(teams, &(&1 >= 1)) and judge? -> "ready"
      true -> "incomplete"
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
