defmodule CabWeb.UiTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import CabWeb.Ui

  # ---------------------------------------------------------------
  # chrome
  # ---------------------------------------------------------------

  test "chrome renders crumbs and segments only - no brand cap, no account, no stage pill" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.chrome crumbs={[{"Kyiv Debate Club", "/c/abc"}]} here="rooms">
        <:seg href="/delete" method="post" quiet>Delete rooms</:seg>
        <:seg href="/motion">Edit motion</:seg>
        <:seg href="/finish" method="post" primary>Finish session</:seg>
      </.chrome>
      """)

    assert html =~ ~s(class="chrome")
    assert html =~ ~s(href="/c/abc")
    assert html =~ "Kyiv Debate Club"
    assert html =~ ~s(<span class="here">rooms</span>)

    # navigation and status left the chrome for the sidenav / content
    refute html =~ ~s(class="cap")
    refute html =~ "stage"
    refute html =~ "Sign in"
    refute html =~ "Sign out"

    # quiet and primary map onto the design classes; plain segs get neither
    assert html =~ ~r/class="quiet"[^>]*/
    assert html =~ ~s(class="go")
    assert [_only_one] = String.split(html, ~s(class="go")) |> tl()

    # post segments render as method links, get segments as plain anchors
    assert html =~ ~s(data-method="post")
    refute html =~ ~s(href="/motion" data-method)
  end

  test "sidenav global context: cap, Clubs/Standings, Admin for admins only" do
    assigns = %{
      admin: %{username: "root", name: nil, is_admin: true},
      user: %{username: "anna", name: "Anna Kovalenko", is_admin: false}
    }

    html =
      rendered_to_string(~H"""
      <.sidenav current_user={@user} active="clubs" />
      """)

    # the brand script cap goes home; plain place names, no badges
    assert html =~ ~s(class="cap")
    assert html =~ ">Clubs<"
    assert html =~ ~s(href="/standings/teams")
    refute html =~ ">Admin<"
    refute html =~ ~s(class="n")

    # the active item carries .on (a left border in CSS, no shadows)
    assert html =~ "item on"

    # profile pinned to the bottom: initials avatar + name -> /account
    assert html =~ ~s(class="profile")
    assert html =~ ~s(class="av")
    assert html =~ "AK"
    assert html =~ ~s(href="/account")
    assert html =~ "Sign out"
    assert html =~ ~s(href="/auth/logout")

    admin_html =
      rendered_to_string(~H"""
      <.sidenav current_user={@admin} active="admin" />
      """)

    assert admin_html =~ ">Admin<"
    assert admin_html =~ ~s(href="/admin")

    anonymous =
      rendered_to_string(~H"""
      <.sidenav current_user={nil} />
      """)

    assert anonymous =~ "Sign in"
    assert anonymous =~ ~s(href="/signin")
    refute anonymous =~ "/auth/github"
    refute anonymous =~ "Sign out"
  end

  test "sidenav club context: place items, role-scoped targets" do
    assigns = %{
      club: %{uuid: "abc", name: "Kyiv Debate Club", is_private: false},
      session: %Cab.Sessions.Session{uuid: "s1"}
    }

    member_html =
      rendered_to_string(~H"""
      <.sidenav club={@club} club_role={:member} nav_session={@session} active="rooms" />
      """)

    assert member_html =~ "Kyiv Debate Club"

    for item <- ~w(Club Rooms Standings Members Register) do
      assert member_html =~ ">#{item}<"
    end

    # the Sessions item is gone - the club page is the archive
    refute member_html =~ ">Sessions<"

    assert member_html =~ ~s(href="/c/abc")
    assert member_html =~ ~s(href="/c/abc/s/s1")
    assert member_html =~ ~s(href="/c/abc/standings/teams")
    assert member_html =~ ~s(href="/c/abc/members")
    assert member_html =~ ~s(href="/r/s1")

    owner_html =
      rendered_to_string(~H"""
      <.sidenav club={@club} club_role={:owner} nav_session={@session} active="club" />
      """)

    assert owner_html =~ ~s(href="/c/abc/owner")
    assert owner_html =~ ~s(href="/c/abc/owner/s/s1")
    assert owner_html =~ ~s(href="/c/abc/owner/members")

    # with no session yet the Rooms item falls back and Register hides
    no_session =
      rendered_to_string(~H"""
      <.sidenav club={@club} club_role={:member} nav_session={nil} />
      """)

    refute no_session =~ "/c/abc/s/"
    refute no_session =~ ">Register<"

    # a finished session keeps Rooms (its results) but takes no sign-ups
    assigns =
      Map.put(assigns, :done, %Cab.Sessions.Session{
        uuid: "s0",
        finished_at: ~U[2026-10-08 20:00:00Z]
      })

    done_html =
      rendered_to_string(~H"""
      <.sidenav club={@club} club_role={:member} nav_session={@done} />
      """)

    assert done_html =~ ~s(href="/c/abc/s/s0")
    refute done_html =~ ">Register<"

    # a private club's roster is members-only, so outsiders lose the item
    assigns = %{assigns | club: %{assigns.club | is_private: true}}

    private_public =
      rendered_to_string(~H"""
      <.sidenav club={@club} club_role={:public} nav_session={nil} />
      """)

    refute private_public =~ ">Members<"

    private_member =
      rendered_to_string(~H"""
      <.sidenav club={@club} club_role={:member} nav_session={nil} />
      """)

    assert private_member =~ ">Members<"
  end

  test "selrow renders the tab row with the active state and no badges" do
    assigns = %{
      tabs: [
        {"teams", "Teams", "/standings/teams"},
        {"speakers", "Speakers", "/standings/speakers"}
      ]
    }

    html =
      rendered_to_string(~H"""
      <.selrow id="tabs" tabs={@tabs} active="speakers" />
      """)

    assert html =~ ~s(class="selrow")
    assert html =~ ~s(href="/standings/teams")

    assert html =~
             ~r/class="on"[^>]*href="\/standings\/speakers"|href="\/standings\/speakers"[^>]*class="on"/

    refute html =~ ~s(class="n")
  end

  # ---------------------------------------------------------------
  # table
  # ---------------------------------------------------------------

  test "table renders every cell format: rank, sub, code, num" do
    assigns = %{rows: [%{name: "Anna", team: "KDC-A", avg: "76.42"}]}

    html =
      rendered_to_string(~H"""
      <.table id="standings" rows={@rows} rank>
        <:col :let={s} label="Speaker">
          {s.name}
          <.sub>Kyiv Debate Club</.sub>
        </:col>
        <:col :let={s} label="Team" code>{s.team}</:col>
        <:col :let={s} label="Avg spk" float>{s.avg}</:col>
      </.table>
      """)

    assert html =~ ~s(class="t t-rows" id="standings")
    assert html =~ ~s(<td class="rank">1</td>)
    assert html =~ ~s(class="sub">Kyiv Debate Club</span>)
    assert html =~ ~s(class="code")
    assert html =~ ~s(class="num")
  end

  test "table: the head slot leads the first header cell only, the rest are plain labels" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.table rows={[]}>
        <:head><input type="checkbox" class="pick" /></:head>
        <:col :let={s} label="Name">{s}</:col>
        <:col :let={s} label="Seat">{s}</:col>
        <:col :let={s}>{s}</:col>
      </.table>
      """)

    [head] = Regex.run(~r/<thead>.*<\/thead>/s, html)
    assert [_one] = Regex.scan(~r/class="pick"/, head)
    assert head =~ ~r/class="pick">\s*Name/
    refute head =~ "false"

    plain =
      rendered_to_string(~H"""
      <.table rows={[]}>
        <:col :let={s} label="Name">{s}</:col>
        <:col :let={s}>{s}</:col>
      </.table>
      """)

    refute plain =~ "false"
  end

  test "table renders the centered empty state line with the full colspan" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.table rows={[]} rank empty="No speakers yet.">
        <:col :let={s} label="Speaker">{s}</:col>
        <:col :let={s} label="Team">{s}</:col>
      </.table>
      """)

    assert html =~ ~s(class="empty")
    assert html =~ ~s(colspan="3")
    assert html =~ "No speakers yet."
  end

  # ---------------------------------------------------------------
  # form
  # ---------------------------------------------------------------

  test "form_for renders head, the block type inventory and the tinted submit" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.form_for action="/sessions" title="Open a session" description="Members can sign up.">
        <:block name={:name} type={:text} label="Session name" required hint="Shown to members." />
        <:block name={:notes} type={:longtext} label="Notes" />
        <:block name={:rooms} type={:int} label="Rooms" min={1} max={6} />
        <:block name={:avg} type={:float} label="Avg" min={50} max={100} step={0.5} />
        <:block name={:rating} type={:scale} label="Rate" min={1} max={8} />
        <:block name={:guests} type={:yesno} label="Allow guests?" />
        <:block name={:as} type={:select} label="I am" options={["Speaker", "Judge", "Hosting"]} />
        <:block
          name={:format}
          type={:select}
          label="Format"
          options={["BP", "WSDC", "LD", "KP", "AP", "Policy"]}
        />
        <:block name={:opts} type={:multi} label="Options" options={["motion by judge", "guests"]} />
        <:block names={[:date, :time]} type={:datetime} label="Date and start time" />
        <:submit note="Members get the sign-up right away.">Open session</:submit>
      </.form_for>
      """)

    assert html =~ ~s(class="form" action="/sessions")
    assert html =~ ~s(action="/sessions")
    assert html =~ "_csrf_token"
    assert html =~ ~s(class="f-head")
    assert html =~ "Open a session"
    assert html =~ ~s(<span class="req">*</span>)
    assert html =~ ~s(class="hint")

    assert html =~ ~s(type="text" name="name")
    assert html =~ ~s(rows="3" name="notes")
    assert html =~ ~s(name="rooms" min="1" max="6")
    assert html =~ ~s(name="avg")
    assert html =~ ~s(step="0.5")

    # scale: 8 flush segments
    assert html =~ ~s(class="scale")
    assert length(String.split(html, ~s(name="rating"))) == 9

    # yesno: always two pills
    assert html =~ ~s(name="guests" value="yes")
    assert html =~ ~s(name="guests" value="no")

    # select: pills at 2-4 options, dropdown at 5+
    assert html =~ ~s(type="radio" name="as" value="Speaker")
    assert html =~ ~s(name="format">)

    # multi: stacked checks posting a list
    assert html =~ ~s(class="opts")
    assert html =~ ~s(name="opts[]")

    # datetime: half-split pair
    assert html =~ ~s(class="half")
    assert html =~ ~s(name="date")
    assert html =~ ~s(placeholder="HH:MM")

    assert html =~ ~s(class="f-submit")
    assert html =~ ~s(class="btn-go")
    assert html =~ "Members get the sign-up right away."
  end

  test "form_for: a :text block's input type, a dropdown prompt and the one-box :check" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.form_for action="/x">
        <:block name="answers[a]" type={:text} input="tel" label="Phone" />
        <:block
          name="answers[b]"
          type={:select}
          label="Level"
          prompt="choose one"
          options={~w(a b c d e)}
        />
        <:block name="answers[c]" type={:check} label="Rules" value="yes" />
      </.form_for>
      """)

    assert html =~ ~s(type="tel" name="answers[a]")
    assert html =~ ~s(<option value="">choose one</option>)
    assert html =~ ~r/type="checkbox" name="answers\[c\]" value="yes" checked/
  end

  test "form_for renders the server error on the failing block only" do
    assigns = %{errors: %{email: "Enter a full email address."}}

    html =
      rendered_to_string(~H"""
      <.form_for action="/x" errors={@errors}>
        <:block name={:name} type={:text} label="Name" hint="kept" />
        <:block name={:email} type={:text} label="Contact email" hint="replaced" />
        <:submit>Save</:submit>
      </.form_for>
      """)

    assert html =~ ~s(f-block err)
    assert html =~ ~s(<div class="error">Enter a full email address.</div>)
    assert html =~ "kept"
    refute html =~ "replaced"
    assert length(String.split(html, "f-block err")) == 2
  end

  # ---------------------------------------------------------------
  # ballot
  # ---------------------------------------------------------------

  defp bp_teams do
    for {side, name} <- [
          og: "Anna & Bohdan",
          oo: "Daryna & Olesia",
          cg: "Hlib & Marko",
          co: "Iryna & Sofia"
        ] do
      %{
        side: side,
        name: name,
        rows: [
          %{role: "1st", speakers: [{"A", 1}, {"B", 2}], selected: 1, iron: false, score: 76},
          %{role: "2nd", speakers: [{"A", 1}, {"B", 2}], selected: 2, iron: false, score: 75.5}
        ]
      }
    end
  end

  test "ballot renders motion header, the four side color blocks and scored position rows" do
    assigns = %{teams: bp_teams()}

    html =
      rendered_to_string(~H"""
      <.ballot room="Room 1" motion="THW let judges pick the motions." teams={@teams} />
      """)

    assert html =~ ~s(class="ballot")
    assert html =~ "THW let judges pick the motions."
    assert html =~ "Motion \u2014 Room 1"
    assert html =~ ~s(data-ballot)

    for side <- ~w(og oo cg co), do: assert(html =~ ~s(class="bteam #{side}"))
    assert html =~ "OG \u2014 OPENING GOV"
    assert html =~ "CO \u2014 CLOSING OPP"

    # per row: speaker dropdown, iron check, score input 50-100 step .5
    assert html =~ ~s(class="who")
    assert html =~ "iron"
    assert html =~ ~s(min="50" max="100" step="1")
    assert length(String.split(html, ~s(class="brow"))) == 9

    # live totals / derived ranks live in the bsum, filled by JS
    assert html =~ ~s(class="bsum")
    assert html =~ ~s(class="tot")
    assert html =~ ~s(class="rk")
    assert html =~ ~s(class="bfoot")
  end

  test "allocator renders the server draft: tray of the unplaced, keyed slots, row words" do
    assigns = %{
      people: %{
        1 => %{id: 1, name: "Anna"},
        2 => %{id: 2, name: "Bohdan"},
        99 => %{id: 99, name: "Nadia"}
      },
      draft: %{"1:og:1" => 1, "2:judge" => 99}
    }

    html =
      rendered_to_string(~H"""
      <.allocator rooms={3} people={@people} draft={@draft} form_id="allocator-form" submit="start" />
      """)

    # the hook reports drops; the hidden form carries the submit event
    assert html =~ ~s(phx-hook="Allocator")
    assert html =~ ~s(id="allocator-form" phx-submit="start")

    # the tray holds only the unplaced - Anna sits in her slot
    [tray, table] = String.split(html, "<table>", parts: 2)
    refute tray =~ "Anna"
    assert tray =~ "Bohdan"
    refute tray =~ "Nadia"
    # the tray carries no role tags; placed chips take their seat's tag
    refute tray =~ ~s(class="k")
    assert tray =~ "Waiting (1)"

    # slots carry their keys; the placed chip renders inside its slot
    assert table =~ ~s(data-slot="1:og:1")
    assert table =~ ~s(data-slot="2:judge")
    assert table =~ ~s(title="Anna">Anna</span><span class="k">SPK</span>)
    assert table =~ ~s(title="Nadia">Nadia</span><span class="k">ADJ</span>)

    # row state in words, never pills
    assert table =~ "incomplete"
    assert table =~ "empty"
    refute html =~ "tag-"
  end

  test "banner renders kind and the optional trailing link" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.banner kind={:good} href="/club" link="Go to club">Your join request was approved.</.banner>
      """)

    assert html =~ ~s(class="banner good")
    assert html =~ "Your join request was approved."
    assert html =~ ~s(href="/club")
    assert html =~ "Go to club"

    plain =
      rendered_to_string(~H"""
      <.banner kind={:bad}>Could not make rooms.</.banner>
      """)

    assert plain =~ ~s(class="banner bad")
    refute plain =~ "<a"
  end

  test "section renders the micro-title and card, flush or padded" do
    assigns = %{}

    flush =
      rendered_to_string(~H"""
      <.section title="My clubs">table goes here</.section>
      """)

    assert flush =~ ~s(class="section")
    assert flush =~ "<h4>My clubs</h4>"
    assert flush =~ ~s(class="card")
    refute flush =~ ~s(class="pad")

    padded =
      rendered_to_string(~H"""
      <.section title="Club" pad>prose</.section>
      """)

    assert padded =~ ~s(class="pad")
  end

  test "flash banners map info and error flashes onto banner kinds" do
    assigns = %{flash: %{"info" => "session opened", "error" => "could not sign up"}}

    html =
      rendered_to_string(~H"""
      <.flash_banners flash={@flash} />
      """)

    assert html =~ ~s(class="banner info")
    assert html =~ "session opened"
    assert html =~ ~s(class="banner bad")
    assert html =~ "could not sign up"
  end
end
