defmodule CabWeb.Ui do
  @moduledoc """
  cab's own components: the sidenav, the tab row, the club logo, the
  ballot and the allocator. The shared kit (table, form, banner,
  section, the chrome/command bar, ...) is `Ui`.

  Every page is a chrome bar and a stack of sections - nothing
  actionable exists outside the chrome, and no element outside this
  kit and `Ui` may appear on a page (whitelist doctrine).
  """

  use Phoenix.Component
  use Gettext, backend: CabWeb.Gettext

  import Phoenix.Controller, only: [get_csrf_token: 0]
  import Ui.Components, only: [beta: 1, stepper: 1, switches: 1]

  use Phoenix.VerifiedRoutes,
    endpoint: CabWeb.Endpoint,
    router: CabWeb.Router,
    statics: CabWeb.static_paths()

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
        <% end %>
        <%!-- the signed-in person's own pages, in every context --%>
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
          <.switches
            id="sidenav-switches"
            phx-update="ignore"
            locale={Gettext.get_locale(CabWeb.Gettext)}
            locales={CabWeb.Locale.names()}
            theme_key="cab-theme"
            up
          />
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
  # a finished session's results are on its session page, for everyone
  defp rooms_href(club, role, %{uuid: uuid, finished_at: nil}) when role in [:owner, :admin],
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
  # 2. Ballot
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

  defp option({label, value}), do: {label, value}
  defp option(value), do: {value, value}

  defp same?(nil, _candidate), do: false
  defp same?(value, candidate), do: to_string(value) == to_string(candidate)

  # ---------------------------------------------------------------
  # 3. Allocator (drag-and-drop, server-held draft)
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
end
