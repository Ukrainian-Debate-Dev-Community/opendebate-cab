defmodule Ui.FormComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Ui.FormComponents

  @definition [
    %{
      "id" => "email",
      "type" => "email",
      "label" => "Your e-mail",
      "hint" => nil,
      "required" => true,
      "options" => [],
      "locked" => true,
      "scope" => "guests"
    },
    %{
      "id" => "level",
      "type" => "choice",
      "label" => "Level",
      "hint" => "How long you debate",
      "required" => false,
      "options" => ["new", "old"],
      "scope" => "members"
    }
  ]

  @attrs %{"scope" => {~w(guests members both), "both"}}

  # ---------------------------------------------------------------
  # the editor
  # ---------------------------------------------------------------

  test "form_editor: the field table, the field routes the caller passes and a new field's form" do
    assigns = %{definition: @definition}

    html =
      rendered_to_string(~H"""
      <.form_editor
        definition={@definition}
        page="/forms/1"
        fields="/forms/1/fields"
        fixed={["Your name"]}
      />
      """)

    assert html =~ ~s(id="form-editor")
    assert html =~ ~s(class="t t-rows" id="form-editor-fields")
    assert html =~ ~s(id="field-fixed")
    assert html =~ "always asked"
    # a locked field can be edited, never moved or removed, and no
    # field moves above it
    assert html =~ ~s(href="/forms/1?edit=email")
    refute html =~ ~s(href="/forms/1/fields/email/remove")
    refute html =~ ~s(href="/forms/1/fields/email/move/down")
    assert html =~ ~s(href="/forms/1/fields/level/remove")
    refute html =~ ~s(href="/forms/1/fields/level/move/up")
    # the new field's form posts to the fields URL
    assert html =~ ~s(id="field-form" action="/forms/1/fields")
    assert html =~ "Add a field"
    # unscoped: no "Asked of" column, no scope choice
    refute html =~ "Asked of"
    refute html =~ ~s(name="scope")
  end

  test "form_editor: the scopes the caller passes, the fixed labels in theirs" do
    assigns = %{definition: @definition, attrs: @attrs}

    html =
      rendered_to_string(~H"""
      <.form_editor
        definition={@definition}
        page="/forms/1"
        fields="/forms/1/fields"
        editing={Enum.at(@definition, 1)}
        fixed={["Your name"]}
        attrs={@attrs}
        scopes={[{"Guests only", "guests"}, {"Members only", "members"}, {"Both", "both"}]}
        fixed_scope="guests"
      />
      """)

    assert html =~ "Asked of"
    assert html =~ ~r/data-label="Asked of"[^>]*>\s*Guests only/
    assert html =~ ~r/data-label="Asked of"[^>]*>\s*Members only/
    # the field being edited posts to its own route, its scope chosen
    assert html =~ ~s(action="/forms/1/fields/level")
    assert html =~ "Edit field: Level"
    assert html =~ ~s(type="radio" name="scope" value="members" checked)
  end

  test "editor_error words every Core.Forms editing code" do
    assert editor_error(:required) == "Enter a label."
    assert editor_error(:locked_moved) == editor_error(:locked)
    assert editor_error(:invalid) == "Use plain text without control characters."
    assert editor_error(:anything_else) == "Something went wrong, try again."
  end

  # ---------------------------------------------------------------
  # the inputs and the answers
  # ---------------------------------------------------------------

  test "a definition's fields map onto form_for blocks" do
    [email, level] = @definition

    assert answer_name(level) == "answers[level]"
    assert block_type(email) == :email
    assert block_type(level) == :select
    assert prompt(level) == "choose one"
    assert answer_error(:required, "choice") == "Choose one."

    assert answer_errors(@definition, %{"email" => {:invalid, :email}}) == %{
             "answers[email]" => "Enter an e-mail address like name@example.com."
           }
  end

  test "form_answers: muted label: value lines, contacts linking out" do
    assigns = %{
      answers: [
        %{"id" => "email", "type" => "email", "label" => "Your e-mail", "value" => "a@b.co"},
        %{"id" => "tg", "type" => "telegram", "label" => "Telegram", "value" => "debate_ua"},
        %{"id" => "ok", "type" => "yesno", "label" => "Rules", "value" => true}
      ]
    }

    html = rendered_to_string(~H"<.form_answers answers={@answers} />")

    assert html =~ ~s(class="sub answer")
    assert html =~ ~s(href="mailto:a@b.co">a@b.co</a>)
    assert html =~ ~s(href="https://t.me/debate_ua" rel="noopener">@debate_ua</a>)
    assert html =~ "Rules: yes"
  end

  test "the locked e-mail field's label follows the viewer's language" do
    field = %{"id" => "email", "label" => "Your e-mail"}

    assert field_label(field) == "Your e-mail"
    assert Gettext.with_locale(Ui.Gettext, "uk", fn -> field_label(field) end) != "Your e-mail"
    assert field_label(%{"id" => "x", "label" => "Your e-mail"}) == "Your e-mail"
  end
end
