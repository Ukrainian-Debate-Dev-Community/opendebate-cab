defmodule PublicWeb.Manage.HTML do
  @moduledoc "The /manage pages: cab's form look, the command in the bar above."
  use PublicWeb, :html

  embed_templates "html/*"

  attr :form, :any, required: true
  attr :field, :atom, required: true

  def errors(assigns) do
    assigns =
      assign(assigns, :messages, Enum.map(assigns.form[assigns.field].errors, &translate/1))

    ~H"""
    <div :for={msg <- @messages} class="hint" style="color:var(--warn)">{msg}</div>
    """
  end

  defp translate({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end

  attr :action, :string, required: true
  attr :method, :string, default: "post"
  attr :class, :string, default: "ua-btn ua-btn--line ua-btn--sm"
  attr :confirm, :string, default: nil
  slot :inner_block, required: true

  # a one-button form (publish, revoke, delete): POST with the CSRF token
  def button_to(assigns) do
    ~H"""
    <.form for={%{}} action={@action} method={@method} class="ua-inline-form">
      <button type="submit" class={@class}>{render_slot(@inner_block)}</button>
    </.form>
    """
  end

  attr :event, :map, required: true
  attr :action, :string, required: true
  attr :back, :string, default: nil, doc: "\"event\": come back to the event's page"

  @doc "An event's Public / Private switch: two one-button forms."
  def visibility_switch(assigns) do
    ~H"""
    <span class="ua-vis">
      <.form
        :for={value <- ~w(public private)}
        for={%{}}
        action={@action}
        method="post"
        class="ua-inline-form"
      >
        <input type="hidden" name="visibility" value={value} />
        <input :if={@back} type="hidden" name="back" value={@back} />
        <button type="submit" class={@event.visibility == value && "on"}>
          {if value == "public", do: gettext("Public"), else: gettext("Private")}
        </button>
      </.form>
    </span>
    """
  end

  attr :tags, :list, required: true

  @doc "A row's private tags, as coloured chips; only /manage shows them."
  def tag_chips(assigns) do
    ~H"""
    <span :if={@tags != []} class="ua-labels">
      <span :for={tag <- @tags} class={["ua-label", "ua-label--#{tag.color}"]}>{tag.name}</span>
    </span>
    """
  end

  attr :tags, :list, required: true
  attr :selected, :any, default: nil
  attr :href, :any, required: true, doc: "a function from a tag (or nil) to its link"

  @doc "The ?tag= filter: every tag as a link, the chosen one marked."
  def tag_filter(assigns) do
    ~H"""
    <div :if={@tags != []} class="ua-tagbar">
      <a class={["ua-label", "ua-label--all", is_nil(@selected) && "on"]} href={@href.(nil)}>
        {gettext("All tags")}
      </a>
      <a
        :for={tag <- @tags}
        class={["ua-label", "ua-label--#{tag.color}", @selected && @selected.id == tag.id && "on"]}
        href={@href.(tag)}
      >
        {tag.name}
      </a>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :tags, :list, required: true
  attr :selected, :list, required: true

  @doc "The editor's tag picker: one checkbox chip per tag; an empty value clears them all."
  def tag_picker(assigns) do
    ~H"""
    <div class="f-block">
      <label class="q">{gettext("Tags")}</label>
      <input type="hidden" name={@name} value="" />
      <div :if={@tags != []} class="ua-tagpick">
        <label :for={tag <- @tags} class={["ua-label", "ua-label--#{tag.color}"]}>
          <input type="checkbox" name={@name} value={tag.id} checked={tag.id in @selected} />
          {tag.name}
        </label>
      </div>
      <div class="hint">
        {gettext("Private: only content managers see tags.")}
        <a href={~p"/manage/tags"}>{gettext("Manage tags")}</a>
      </div>
    </div>
    """
  end

  @doc "The ids of the tags to tick: what the form sent, else what the record has."
  def selected_tag_ids(%{"tag_ids" => ids}, _record),
    do: ids |> List.wrap() |> Enum.flat_map(&parse_id/1)

  def selected_tag_ids(_attrs, %{tags: tags}) when is_list(tags), do: Enum.map(tags, & &1.id)
  def selected_tag_ids(_attrs, _record), do: []

  defp parse_id(id) do
    case Integer.parse(to_string(id)) do
      {n, ""} -> [n]
      _ -> []
    end
  end

  def color_label("gray"), do: gettext("Gray")
  def color_label("red"), do: gettext("Red")
  def color_label("orange"), do: gettext("Orange")
  def color_label("yellow"), do: gettext("Yellow")
  def color_label("green"), do: gettext("Green")
  def color_label("teal"), do: gettext("Teal")
  def color_label("blue"), do: gettext("Blue")
  def color_label(_), do: gettext("Purple")
end
