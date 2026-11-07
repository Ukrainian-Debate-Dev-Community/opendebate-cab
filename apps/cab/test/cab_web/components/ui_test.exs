defmodule CabWeb.UiTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import CabWeb.Ui
  import Ui.Components, only: [chrome: 1]

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

  test "sidenav: My page and Admin in every context for the signed-in" do
    assigns = %{
      club: %{uuid: "abc", name: "Kyiv Debate Club", is_private: false},
      admin: %{username: "root", name: nil, is_admin: true},
      user: %{username: "anna", name: "Anna Kovalenko", is_admin: false}
    }

    member =
      rendered_to_string(~H"""
      <.sidenav club={@club} club_role={:member} current_user={@user} active="club" />
      """)

    assert member =~ ~s(href="/me")
    assert member =~ ">My page<"
    refute member =~ ">Admin<"

    admin =
      rendered_to_string(~H"""
      <.sidenav club={@club} club_role={:admin} current_user={@admin} active="club" />
      """)

    assert admin =~ ">My page<"
    assert admin =~ ~s(href="/admin")

    anonymous =
      rendered_to_string(~H"""
      <.sidenav club={@club} club_role={:public} current_user={nil} active="club" />
      """)

    refute anonymous =~ ">My page<"
    refute anonymous =~ ">Admin<"
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

    for item <- ~w(Club Rooms Standings Members) do
      assert member_html =~ ">#{item}<"
    end

    # the Sessions item is gone - the club page is the archive
    refute member_html =~ ">Sessions<"

    assert member_html =~ ~s(href="/c/abc")
    assert member_html =~ ~s(href="/c/abc/s/s1")
    assert member_html =~ ~s(href="/c/abc/standings/teams")
    assert member_html =~ ~s(href="/c/abc/members")
    # registration lives on the club page, not in the sidebar
    refute member_html =~ ">Register<"
    refute member_html =~ ~s(href="/r/s1")

    owner_html =
      rendered_to_string(~H"""
      <.sidenav club={@club} club_role={:owner} nav_session={@session} active="club" />
      """)

    assert owner_html =~ ~s(href="/c/abc/owner")
    assert owner_html =~ ~s(href="/c/abc/owner/s/s1")
    assert owner_html =~ ~s(href="/c/abc/owner/members")

    # with no session yet the Rooms item falls back to the club page
    no_session =
      rendered_to_string(~H"""
      <.sidenav club={@club} club_role={:member} nav_session={nil} />
      """)

    refute no_session =~ "/c/abc/s/"

    # a finished session keeps Rooms (its results)
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

    # the head too: a finished session's results are on its session page
    owner_done =
      rendered_to_string(~H"""
      <.sidenav club={@club} club_role={:owner} nav_session={@done} />
      """)

    assert owner_done =~ ~s(href="/c/abc/s/s0")
    refute owner_done =~ "/c/abc/owner/s/s0"

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
end
