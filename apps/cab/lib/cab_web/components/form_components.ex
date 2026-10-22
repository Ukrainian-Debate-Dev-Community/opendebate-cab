defmodule CabWeb.FormComponents do
  @moduledoc """
  cab's UI for configurable forms (`Core.Forms` holds the logic): the
  definition editor, a definition's fields as `form_for` blocks, and
  the answers given to it - built from cab's design kit (table,
  form_for, banner) in cab's words. Server-rendered, no JavaScript
  beyond the kit's method links.

  The editor's routes, relative to the `fields` URL the caller passes:

      POST <fields>                     add a field
      POST <fields>/<id>                save an edited field
      POST <fields>/<id>/remove         remove a field
      POST <fields>/<id>/move/up|down   move a field
      GET  <page>?edit=<id>             the page with that field's form
  """
  use CabWeb, :html

  alias Core.Forms

  @doc "A field type's name, as the editor shows it."
  def type_name("text"), do: gettext("short text")
  def type_name("longtext"), do: gettext("long text")
  def type_name("number"), do: gettext("number")
  def type_name("email"), do: gettext("e-mail")
  def type_name("phone"), do: gettext("phone")
  def type_name("telegram"), do: gettext("Telegram username")
  def type_name("yesno"), do: gettext("yes/no")
  def type_name("choice"), do: gettext("single choice")
  def type_name("multi"), do: gettext("multiple choice")
  def type_name(other), do: to_string(other)

  @doc "A field scope's name, as the editor shows it."
  def scope_name("guests"), do: gettext("Guests only")
  def scope_name("members"), do: gettext("Members only")
  def scope_name(_both), do: gettext("Guests and members")

  @doc "A `Core.Forms` editing error code as a message."
  def editor_error(:required), do: dgettext("errors", "Enter a label.")

  def editor_error({:too_long, max}),
    do: dgettext("errors", "%{count} characters at most.", count: max)

  def editor_error(:unknown_type), do: dgettext("errors", "Choose a type.")
  def editor_error(:unknown_scope), do: dgettext("errors", "Choose who is asked.")

  def editor_error({:options_count, min, max}),
    do: dgettext("errors", "Give %{min} to %{max} options, one per line.", min: min, max: max)

  def editor_error({:option_too_long, max}),
    do: dgettext("errors", "An option is %{count} characters at most.", count: max)

  def editor_error(:duplicate_options), do: dgettext("errors", "Each option must be different.")

  def editor_error({:too_many_fields, max}),
    do: dgettext("errors", "A form holds %{count} fields at most.", count: max)

  def editor_error(:locked),
    do: dgettext("errors", "This field is always asked: it cannot be moved or removed.")

  def editor_error(:invalid), do: Cab.Text.message(:invalid)
  def editor_error(:locked_removed), do: editor_error(:locked)
  def editor_error(:locked_moved), do: editor_error(:locked)
  def editor_error(_code), do: dgettext("errors", "Something went wrong, try again.")

  @doc "A `Core.Forms` answer error code as a message, worded for the field's type."
  def answer_error(:required, "choice"), do: dgettext("errors", "Choose one.")
  def answer_error(:required, "multi"), do: dgettext("errors", "Choose at least one.")
  def answer_error(:required, "yesno"), do: dgettext("errors", "Tick this box.")
  def answer_error(:required, _type), do: dgettext("errors", "Fill this in.")

  def answer_error({:invalid, :email}, _type),
    do: dgettext("errors", "Enter an e-mail address like name@example.com.")

  def answer_error({:invalid, :phone}, _type),
    do: dgettext("errors", "Enter a phone number: 7 to 20 digits, + in front if needed.")

  def answer_error({:invalid, :telegram}, _type),
    do: dgettext("errors", "Enter a Telegram username: 5 to 32 letters, digits or _, like @name.")

  def answer_error({:invalid, :number}, _type),
    do: dgettext("errors", "Enter a number, like 12 or 3.5.")

  def answer_error({:too_long, max}, _type),
    do: dgettext("errors", "%{count} characters at most.", count: max)

  def answer_error(:not_an_option, _type), do: dgettext("errors", "Choose from the options.")
  def answer_error(:invalid, _type), do: Cab.Text.message(:invalid)
  def answer_error(_code, _type), do: dgettext("errors", "Something went wrong, try again.")

  # ---------------------------------------------------------------
  # The editor
  # ---------------------------------------------------------------

  @doc """
  The field list (a kit table: up / down / edit / remove) and one
  field form: a new field's, or the one in `editing`; its submit is
  the page's own (a chrome segment with `form={form_id}`). `values`
  are the field form's posted params, `errors` the `Core.Forms` codes
  by param. `fixed` lists the labels the app asks before the form
  (shown first, not editable); locked fields can only be edited.
  `scoped` shows and edits each field's scope (who is asked it).
  """
  attr :id, :string, default: "form-editor"
  attr :definition, :list, required: true
  attr :page, :string, required: true, doc: "the editor page's URL"
  attr :fields, :string, required: true, doc: "the base URL of the field routes"
  attr :editing, :map, default: nil
  attr :values, :map, default: %{}
  attr :errors, :map, default: %{}
  attr :fixed, :list, default: []
  attr :form_id, :string, default: "field-form"
  attr :scoped, :boolean, default: false

  def form_editor(assigns) do
    definition = assigns.definition

    rows =
      Enum.map(assigns.fixed, &{:fixed, %{"id" => "fixed", "label" => &1}, nil}) ++
        for {field, index} <- Enum.with_index(definition) do
          up? = index > 0 and not Forms.locked?(Enum.at(definition, index - 1))
          down? = index < length(definition) - 1
          {:field, field, %{up: up?, down: down?}}
        end

    assigns =
      assigns
      |> assign(:values, Map.merge(Forms.field_params(assigns.editing), assigns.values))
      |> assign(
        :messages,
        Map.new(assigns.errors, fn {key, code} -> {key, editor_error(code)} end)
      )
      |> assign(:rows, rows)
      |> assign(:locked, Forms.locked?(assigns.editing))

    ~H"""
    <div id={@id}>
      <.table
        id={"#{@id}-fields"}
        rows={@rows}
        row_id={fn {_kind, field, _moves} -> "field-#{field["id"]}" end}
        empty={gettext("No fields yet.")}
      >
        <:col :let={{kind, field, _moves}} label={gettext("Field")}>
          {field_label(field)}
          <.sub :if={kind == :fixed or Forms.locked?(field)}>{gettext("always asked")}</.sub>
          <.sub :if={field["hint"]}>{field["hint"]}</.sub>
        </:col>
        <:col :let={{kind, field, _moves}} label={gettext("Type")}>
          {if kind == :fixed, do: type_name("text"), else: type_name(field["type"])}
          <.sub :if={field["options"] not in [nil, []]}>{Enum.join(field["options"], ", ")}</.sub>
        </:col>
        <:col :let={{kind, field, _moves}} :if={@scoped} label={gettext("Asked of")}>
          {scope_name(if kind == :fixed, do: "guests", else: Forms.scope(field))}
        </:col>
        <:col :let={{kind, field, _moves}} label={gettext("Answer")}>
          {if kind == :fixed or field["required"],
            do: gettext("required"),
            else: gettext("optional")}
        </:col>
        <:col :let={{kind, field, moves}}>
          <span :if={kind == :field} class="field-actions">
            <.link :if={moves.up} href={"#{@fields}/#{field["id"]}/move/up"} method="post">
              {gettext("up")}
            </.link>
            <.link
              :if={moves.down and not Forms.locked?(field)}
              href={"#{@fields}/#{field["id"]}/move/down"}
              method="post"
            >
              {gettext("down")}
            </.link>
            <.link href={"#{@page}?edit=#{field["id"]}"}>{gettext("edit")}</.link>
            <.link
              :if={not Forms.locked?(field)}
              href={"#{@fields}/#{field["id"]}/remove"}
              method="post"
            >
              {gettext("remove")}
            </.link>
          </span>
        </:col>
      </.table>
      <.banner :if={@messages[:form]} kind={:bad}>{@messages[:form]}</.banner>
      <.form_for
        id={@form_id}
        action={if @editing, do: "#{@fields}/#{@editing["id"]}", else: @fields}
        title={
          if @editing,
            do: gettext("Edit field: %{label}", label: field_label(@editing)),
            else: gettext("Add a field")
        }
        description={
          if @locked,
            do: gettext("Always asked. You can choose whether it is required and give it a hint."),
            else: gettext("Guests see the label as the question and the hint below it.")
        }
        errors={@messages}
      >
        <:block
          :if={not @locked}
          name={:label}
          type={:text}
          label={gettext("Label")}
          required
          maxlength={120}
          value={@values["label"]}
        />
        <:block
          :if={not @locked}
          name={:type}
          type={:select}
          label={gettext("Type")}
          value={@values["type"]}
          options={Enum.map(Forms.types(), &{type_name(&1), &1})}
        />
        <:block
          :if={@scoped and not @locked}
          name={:scope}
          type={:select}
          label={gettext("Asked of")}
          value={@values["scope"]}
          options={Enum.map(Forms.scopes(), &{scope_name(&1), &1})}
        />
        <:block
          :if={not @locked}
          name={:options}
          type={:longtext}
          label={gettext("Options")}
          value={@values["options"]}
          hint={gettext("Single and multiple choice only: one option per line, 2 to 20 options.")}
        />
        <:block
          name={:required}
          type={:yesno}
          label={gettext("Required")}
          value={@values["required"]}
        />
        <:block
          name={:hint}
          type={:text}
          label={gettext("Hint")}
          maxlength={200}
          value={@values["hint"]}
          hint={gettext("Optional: a line under the question.")}
        />
      </.form_for>
    </div>
    """
  end

  @doc """
  A field's or an answer's label as shown: cab's locked e-mail field
  in the viewer's language, every other label as the head wrote it.
  """
  def field_label(%{"id" => "email", "label" => "Your e-mail"}), do: gettext("Your e-mail")
  def field_label(field), do: field["label"]

  # ---------------------------------------------------------------
  # The inputs: a definition's fields as the kit's form_for blocks
  # ---------------------------------------------------------------
  #
  #     <:block
  #       :for={field <- @fields}
  #       name={answer_name(field)}
  #       type={block_type(field)}
  #       label={field["label"]}
  #       required={field["required"]}
  #       hint={field["hint"]}
  #       options={field["options"]}
  #       value={@answers[field["id"]]}
  #       input={input_type(field)}
  #       placeholder={placeholder(field)}
  #       prompt={prompt(field)}
  #     />
  #
  # Each field posts as answers[<field id>] (a list for multiple
  # choice), ready for Core.Forms.validate_answers/2.

  @doc "A field's input name; also its key in the form's errors map."
  def answer_name(field), do: "answers[#{field["id"]}]"

  @doc "The form_for block type for a field's type."
  def block_type(%{"type" => "longtext"}), do: :longtext
  def block_type(%{"type" => "yesno"}), do: :check
  def block_type(%{"type" => "choice"}), do: :select
  def block_type(%{"type" => "multi"}), do: :multi
  def block_type(_field), do: :text

  @doc "A :text block's input type."
  def input_type(%{"type" => "email"}), do: "email"
  def input_type(%{"type" => "phone"}), do: "tel"
  def input_type(_field), do: nil

  @doc "A :text block's placeholder."
  def placeholder(%{"type" => "telegram"}), do: "@username"
  def placeholder(%{"type" => "phone"}), do: "+380 ..."
  def placeholder(%{"type" => "number"}), do: "12"
  def placeholder(_field), do: nil

  @doc "A single choice's empty first option (dropdowns only, at 5+ options)."
  def prompt(%{"type" => "choice"}), do: gettext("choose one")
  def prompt(_field), do: nil

  @doc "Answer error codes by field id as form_for errors (block name => message)."
  def answer_errors(definition, codes) do
    for field <- definition, code = codes[field["id"]], into: %{} do
      {answer_name(field), answer_error(code, field["type"])}
    end
  end

  # ---------------------------------------------------------------
  # The answers
  # ---------------------------------------------------------------

  @doc """
  Answers as muted "label: value" lines (for a table cell), each with
  the label it had when answered; e-mail, phone and Telegram link out.
  """
  attr :answers, :list, required: true

  def form_answers(assigns) do
    ~H"""
    <span :for={answer <- @answers} class="sub answer">
      {field_label(answer)}: <.answer_value answer={answer} />
    </span>
    """
  end

  @doc "One answer's value; e-mail, phone and Telegram link out."
  attr :answer, :map, required: true

  def answer_value(%{answer: %{"type" => "email", "value" => value}} = assigns)
      when is_binary(value) do
    ~H|<a href={"mailto:#{@answer["value"]}"}>{@answer["value"]}</a>|
  end

  def answer_value(%{answer: %{"type" => "phone", "value" => value}} = assigns)
      when is_binary(value) do
    ~H|<a href={"tel:#{String.replace(@answer["value"], ~r/[^0-9+]/, "")}"}>{@answer["value"]}</a>|
  end

  def answer_value(%{answer: %{"type" => "telegram", "value" => value}} = assigns)
      when is_binary(value) do
    ~H|<a href={"https://t.me/#{@answer["value"]}"} rel="noopener">@{@answer["value"]}</a>|
  end

  def answer_value(assigns), do: ~H"{answer_text(@answer)}"

  @doc "An answer's value as plain text."
  def answer_text(%{"value" => true}), do: gettext("yes")
  def answer_text(%{"value" => false}), do: gettext("no")
  def answer_text(%{"value" => values}) when is_list(values), do: Enum.join(values, ", ")
  def answer_text(%{"value" => value}) when is_binary(value), do: value
  def answer_text(_answer), do: ""
end
