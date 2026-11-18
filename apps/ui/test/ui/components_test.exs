defmodule Ui.ComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Ui.Components

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
  # banner, time, stepper, split button, section
  # ---------------------------------------------------------------

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
    assert flush =~ "<span>My clubs</span>"
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

  test "stepper: links or events, an end shown but off" do
    assigns = %{}

    links =
      rendered_to_string(~H"""
      <.stepper prev="/a" next={nil} prev_label="Earlier" next_label="Later">Now</.stepper>
      """)

    assert links =~ ~s(class="stepper")
    assert links =~ ~s(href="/a")
    assert links =~ ~s(class="off")
    assert links =~ "Now"

    events =
      rendered_to_string(~H"""
      <.stepper
        event="rooms"
        name="rooms"
        prev={0}
        next={2}
        prev_off
        prev_label="Fewer"
        next_label="More"
      >
        1
      </.stepper>
      """)

    assert events =~ ~s(phx-value-rooms="0")
    assert events =~ ~s(phx-value-rooms="2")
    assert events =~ "disabled"
  end

  test "dropdown_button: the main action and a menu of alternatives" do
    assigns = %{
      items: [
        %{label: "Practice", href: "/c/abc?session=s2", at: ~U[2026-11-01 18:00:00Z]},
        %{label: "Mini", href: "/c/abc?session=s3", current: true}
      ]
    }

    html =
      rendered_to_string(~H"""
      <.dropdown_button items={@items}>Register</.dropdown_button>
      """)

    assert html =~ ~s(class="dd-btn go split")
    assert html =~ ~s(<button type="submit" class="dd-main">)
    assert html =~ ~s(<details class="dd-more" data-menu>)
    assert html =~ ~s(href="/c/abc?session=s2")
    assert html =~ ~s(aria-current="true")
    assert html =~ ~s(class="at")

    plain =
      rendered_to_string(~H"""
      <.dropdown_button quiet href="/somewhere">Open</.dropdown_button>
      """)

    assert plain =~ ~s(class="dd-btn quiet")
    assert plain =~ ~s(href="/somewhere")
    refute plain =~ "<details"
  end

  test "a time renders as its UTC instant with a UTC fallback text" do
    assigns = %{at: ~U[2026-10-09 15:30:00Z]}

    html = rendered_to_string(~H"<.local_time at={@at} as={:short} />")
    assert html =~ ~s(datetime="2026-10-09T15:30:00Z")
    assert html =~ ~s(data-when="short")
    assert html =~ "9 Oct, 15:30 UTC"
  end

  test "section: bare leaves the card out; an action links at the title's right" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.section title="News" bare id="news">
        <:action href="/news">All news</:action>
        rows
      </.section>
      """)

    assert html =~ ~s(id="news")
    assert html =~ ~s(href="/news")
    assert html =~ "All news"
    refute html =~ ~s(class="card")
  end

  test "card, empty, tag and page head" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.card id="c" class="extra" pad>text</.card>
      <.empty id="none">Nothing yet.</.empty>
      <.tag kind="ok">Published</.tag>
      <.page_head kicker="Clubs" title="Kyiv" lead="A club" logo="/logo.png">
        <:actions><a href="/x">Open</a></:actions>
      </.page_head>
      """)

    assert html =~ ~s(class="card extra" id="c")
    assert html =~ ~s(<div class="pad">text</div>)
    assert html =~ ~s(class="card empty-state" id="none")
    assert html =~ ~s(class="tag ok")
    assert html =~ ~s(class="page-head")
    assert html =~ ~s(class="kicker")
    assert html =~ ~s(class="logo" src="/logo.png")
    assert html =~ ~s(class="acts")
  end

  test "chrome: crumbs, the tail and its segments as links, method links or submits" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.chrome crumbs={[{"Calendar", "/cal"}]} here="Event">
        <:seg href="/edit">Edit</:seg>
        <:seg href="/del" method="delete" quiet>Delete</:seg>
        <:seg form="f" primary>Save</:seg>
      </.chrome>
      """)

    assert html =~ ~s(class="chrome")
    assert html =~ ~s(href="/cal")
    assert html =~ ~s(class="here">Event)
    assert html =~ ~s(data-method="delete")
    assert html =~ ~s(class="quiet")
    assert html =~ ~s(form="f")
    assert html =~ ~s(class="go")
  end

  test "switches: the theme button with its key and words, the language menu" do
    assigns = %{locales: [{"en", "EN", "English"}, {"uk", "UA", "Ukrainian"}]}

    html =
      rendered_to_string(~H"""
      <.switches locale="uk" locales={@locales} theme_key="site-theme" up id="sw" />
      """)

    assert html =~ ~s(id="sw")
    assert html =~ ~s(data-theme-key="site-theme")
    assert html =~ ~s(data-label-dark="Theme: dark")
    assert html =~ ~s(class="langs up")
    assert html =~ ~s(href="/locale/uk")
    assert html =~ ~s(aria-current="true")
    assert html =~ "UA"
  end

  test "copy carries its words for the moment after copying" do
    assigns = %{}
    html = rendered_to_string(~H|<.copy text="https://x" />|)
    assert html =~ ~s(data-copy="https://x")
    assert html =~ ~s(data-label-copied="Copied")
  end
end
