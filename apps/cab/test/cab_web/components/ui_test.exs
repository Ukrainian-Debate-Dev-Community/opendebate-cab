defmodule CabWeb.UiTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import CabWeb.Ui

  # ---------------------------------------------------------------
  # chrome
  # ---------------------------------------------------------------

  test "chrome renders cap, crumbs, stage and segments honouring primary/quiet" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.chrome crumbs={[{"Kyiv Debate Club", "/c/abc"}]} here="rooms" stage="running" stage_kind={:warn}>
        <:seg href="/delete" method="post" quiet>Delete rooms</:seg>
        <:seg href="/motion">Edit motion</:seg>
        <:seg href="/finish" method="post" primary>Finish session</:seg>
      </.chrome>
      """)

    assert html =~ ~s(class="chrome")
    assert html =~ ~s(class="cap")
    assert html =~ ~s(href="/c/abc")
    assert html =~ "Kyiv Debate Club"
    assert html =~ ~s(<span class="here">rooms</span>)
    assert html =~ ~s(class="stage warn")

    # quiet and primary map onto the design classes; plain segs get neither
    assert html =~ ~r/class="quiet"[^>]*/
    assert html =~ ~s(class="go")
    assert [_only_one] = String.split(html, ~s(class="go")) |> tl()

    # post segments render as method links, get segments as plain anchors
    assert html =~ ~s(data-method="post")
    refute html =~ ~s(href="/motion" data-method)
  end

  test "chrome account segments: signed-in shows name + sign out, signed-out shows sign in" do
    assigns = %{user: %{username: "anna"}}

    signed_in =
      rendered_to_string(~H"""
      <.chrome account current_user={@user} here="my cabinet" />
      """)

    assert signed_in =~ ~s(class="me")
    assert signed_in =~ "anna"
    assert signed_in =~ "Sign out"
    assert signed_in =~ ~s(href="/auth/logout")
    refute signed_in =~ "Sign in"

    signed_out =
      rendered_to_string(~H"""
      <.chrome account current_user={nil} here="cab" />
      """)

    assert signed_out =~ "Sign in"
    assert signed_out =~ ~s(href="/auth/github")
    refute signed_out =~ "Sign out"
  end

  # ---------------------------------------------------------------
  # table
  # ---------------------------------------------------------------

  test "table renders every cell format: check, rank, sub, code, num, sort header" do
    assigns = %{rows: [%{name: "Anna", team: "KDC-A", avg: "76.42"}]}

    html =
      rendered_to_string(~H"""
      <.table id="standings" rows={@rows} rank check={fn _row -> true end}>
        <:col :let={s} label="Speaker" sort="name">
          {s.name}
          <.sub>Kyiv Debate Club</.sub>
        </:col>
        <:col :let={s} label="Team" code>{s.team}</:col>
        <:col :let={s} label="Avg spk" sort="avg" float>{s.avg}</:col>
      </.table>
      """)

    assert html =~ ~s(class="t" id="standings")
    assert html =~ ~s(data-check-all)
    assert html =~ ~s(checked)
    assert html =~ ~s(<td class="rank">1</td>)
    assert html =~ ~s(class="sub">Kyiv Debate Club</span>)
    assert html =~ ~s(class="code")
    assert html =~ ~s(class="sort num")
    assert html =~ ~s(data-k="avg")
    assert html =~ ~s(data-k="name")
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
    assert html =~ "Motion · Room 1"
    assert html =~ ~s(data-ballot)

    for side <- ~w(og oo cg co), do: assert(html =~ ~s(class="bteam #{side}"))
    assert html =~ "OG · OPENING GOV"
    assert html =~ "CO · CLOSING OPP"

    # per row: speaker dropdown, iron check, score input 50-100 step .5
    assert html =~ ~s(class="who")
    assert html =~ "iron"
    assert html =~ ~s(min="50" max="100" step="0.5")
    assert length(String.split(html, ~s(class="brow"))) == 9

    # live totals / derived ranks live in the bsum, filled by JS
    assert html =~ ~s(class="bsum")
    assert html =~ ~s(class="tot")
    assert html =~ ~s(class="rk")
    assert html =~ ~s(class="bfoot")
  end

  test "elim ballot renders an advances checkbox per team and the exact-count message" do
    assigns = %{
      teams: [
        %{side: :og, name: "Anna & Bohdan", advances: true},
        %{side: :oo, name: "Daryna & Olesia", advances: true},
        %{side: :cg, name: "Hlib & Marko", advances: false},
        %{side: :co, name: "Iryna & Sofia", advances: false}
      ]
    }

    html =
      rendered_to_string(~H"""
      <.elim_ballot room="Semifinal · Room A" advance={2} teams={@teams} />
      """)

    assert html =~ ~s(class="ballot elim")
    assert html =~ ~s(data-advance="2")
    assert length(String.split(html, ~s(type="checkbox"))) == 5
    assert length(String.split(html, "advances")) == 5
    assert html =~ "Top 2 advance."
    assert html =~ "Tick exactly 2 teams."
    refute html =~ ~s(type="number")
    refute html =~ "<select"
  end

  # ---------------------------------------------------------------
  # tag, banner, section
  # ---------------------------------------------------------------

  test "dnd_table renders the tray of kind-marked chips, droppable slots and hidden inputs" do
    assigns = %{
      tray: [
        %{id: 1, name: "Anna", kind: "spk"},
        %{id: 2, name: "Bohdan", kind: "spk"},
        %{id: 99, name: "Nadia", kind: "judge"}
      ]
    }

    html =
      rendered_to_string(~H"""
      <.dnd_table id="compose" action="/rooms" rooms={2} tray={@tray} />
      """)

    # a plain form POSTing to the composition action — dnd is
    # presentation, not transport
    assert html =~ ~s(class="dnd")
    assert html =~ ~s(action="/rooms")
    assert html =~ ~s(method="post")
    assert html =~ "data-dnd"
    assert html =~ ~s(name="_csrf_token")

    # tray: draggable chips with the kind mark; judges carry the blue class
    assert html =~ "data-tray"
    assert html =~ "data-tray-count"
    assert length(String.split(html, ~s(draggable="true"))) == 4
    assert html =~ ~s(data-id="1")
    assert html =~ "Anna <span class=\"k\">SPK</span>"
    assert html =~ "Nadia <span class=\"k\">JUDGE</span>"
    assert html =~ ~s(class="chip judge")

    # two rows x (4 team cells with side bands x 2 slots + judge slot
    # + status tag), each slot mirroring a hidden input
    for side <- ~w(og oo cg co), do: assert(html =~ ~s(class="team t-#{side}"))
    assert length(String.split(html, ~s(class="slot"))) == 19
    assert html =~ ~s(name="rooms[1][og][1]")
    assert html =~ ~s(name="rooms[1][og][2]")
    assert html =~ ~s(name="rooms[2][co][2]")
    assert html =~ ~s(name="rooms[1][judge]")
    assert html =~ ~s(name="rooms[2][judge]")
    assert html =~ ~s(data-kind="judge")
    assert html =~ ~s(class="status")
    assert html =~ "iron"

    # never dropdowns or swap controls for allocation
    refute html =~ "<select"
  end

  test "tag renders its three kinds" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.tag kind={:ok}>active</.tag>
      <.tag kind={:warn}>pending</.tag>
      <.tag kind={:mut}>archive</.tag>
      """)

    assert html =~ ~s(class="tag tag-ok")
    assert html =~ ~s(class="tag tag-warn")
    assert html =~ ~s(class="tag tag-mut")
  end

  test "banner renders kind and the optional trailing link" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.banner kind={:good} href="/club" link="Go to club →">Your join request was approved.</.banner>
      """)

    assert html =~ ~s(class="banner good")
    assert html =~ "Your join request was approved."
    assert html =~ ~s(href="/club")
    assert html =~ "Go to club →"

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
