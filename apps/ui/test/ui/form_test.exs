defmodule Ui.FormTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Ui.Form

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

    # datetime: the native date and time pickers, half-split
    assert html =~ ~s(class="half")
    assert html =~ ~s(type="date" name="date")
    assert html =~ ~s(type="time" name="time")

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

  test "form_for: a :datetime pair prefilled with the caller's wall-clock parts" do
    assigns = %{at: ~U[2026-12-01 16:30:00Z]}

    html =
      rendered_to_string(~H"""
      <.form_for action="/schedule">
        <:block
          names={[:date, :time]}
          type={:datetime}
          at={@at}
          value={["2026-12-01", "18:30"]}
          zone="Europe/Kyiv"
        />
      </.form_for>
      """)

    assert html =~ ~s(data-at="2026-12-01T16:30:00Z")
    assert html =~ ~s(type="date" name="date" value="2026-12-01")
    assert html =~ ~s(type="time" name="time" value="18:30")
    assert html =~ ~s(type="hidden" name="zone" value="Europe/Kyiv")
  end

  test "form_for: the Turnstile widget only with a site key" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.form_for action="/x" guard="1x00000000000000000000AA">
        <:submit>Send</:submit>
      </.form_for>
      """)

    assert html =~ ~s(class="cf-turnstile" data-sitekey="1x00000000000000000000AA")
    assert html =~ ~s(data-language="en")

    plain =
      rendered_to_string(~H"""
      <.form_for action="/x">
        <:submit>Send</:submit>
      </.form_for>
      """)

    refute plain =~ "cf-turnstile"
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

  test "form_for contact blocks: phone with its picker hook, e-mail, telegram" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.form_for action="/x">
        <:block name="answers[ph]" type={:phone} label="Phone" value="+380501234567" />
        <:block name="answers[em]" type={:email} label="E-mail" value="a@b.co" required />
        <:block name="answers[tg]" type={:telegram} label="Telegram" value="debate_ua" />
      </.form_for>
      """)

    # the phone block: a hooked wrapper, the stored E.164 shown readable
    assert html =~ ~s(phx-hook="PhoneField")
    assert html =~ ~s(id="phone-answers-ph-")
    assert html =~ ~s(type="tel")
    assert html =~ ~s(value="+380 50 123 4567")
    assert html =~ ~s(autocomplete="tel")
    # checked in the browser when the field is left, no hint while typing
    assert html =~ "data-phone"
    # the messages travel with the field (the server's own, translated),
    # so the helpers need no table of words on other sites' pages
    assert html =~ ~s(data-msg-country="Country")
    assert html =~ ~s(data-msg-invalid="Enter a full phone number for its country)
    assert html =~ ~s(data-msg-required="Fill this in.")
    refute html =~ "phonehint"
    # e-mail: the e-mail keyboard and autofill, cleaned as typed
    assert html =~ ~s(type="email")
    assert html =~ ~s(inputmode="email")
    assert html =~ "data-email"
    # a required field says so to the browser's check
    assert html =~ ~s(data-required="true")
    # telegram: shown with its @, cleaned as typed
    assert html =~ ~s(value="@debate_ua")
    assert html =~ "data-telegram"
  end

  test "form_for: a put goes as a post with _method; :date, :custom and rows" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.form_for action="/events/1" method="put">
        <:block name="event[starts_on]" type={:date} label="Starts" value="2026-11-07" />
        <:block name="event[details]" type={:longtext} label="Details" rows={7} />
        <:block name="event[tags]" type={:custom} label="Tags"><span class="mine">chips</span></:block>
        <:submit>Save</:submit>
      </.form_for>
      """)

    assert html =~ ~s(method="post")
    assert html =~ ~s(name="_method" value="put")
    assert html =~ ~s(type="date" name="event[starts_on]" value="2026-11-07")
    assert html =~ ~s(rows="7")
    assert html =~ ~s(class="mine">chips</span>)
  end
end
