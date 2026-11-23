defmodule PublicWeb.Manage.HTML do
  @moduledoc "The /manage pages: ui's forms and tables, the command in the bar above."
  use PublicWeb, :html

  embed_templates "html/*"

  @doc """
  A form's errors as form_for wants them: the field's input name (as
  `name/2` gives it) => its first message.
  """
  def field_errors(%Phoenix.HTML.Form{} = form) do
    form.errors
    |> Enum.reverse()
    |> Map.new(fn {field, error} -> {field_name(form, field), translate(error)} end)
  end

  @doc """
  The news form's errors by block name: a text field's under the
  language version it belongs to (`post[i18n][uk][title]`), the
  translations' included.
  """
  def news_errors(%Phoenix.HTML.Form{source: changeset} = form) do
    lang = Ecto.Changeset.get_field(changeset, :lang)

    own =
      Map.new(form.errors |> Enum.reverse(), fn {field, error} ->
        if to_string(field) in ~w(title summary body image_alt),
          do: {"post[i18n][#{lang}][#{field}]", translate(error)},
          else: {field_name(form, field), translate(error)}
      end)

    translated =
      for t <- translation_changesets(changeset),
          {field, error} <- Enum.reverse(t.errors),
          into: %{},
          do: {"post[i18n][#{Ecto.Changeset.get_field(t, :lang)}][#{field}]", translate(error)}

    Map.merge(own, translated)
  end

  @doc "The language of the first version with a refused field, nil when none is refused."
  def error_lang(%Ecto.Changeset{valid?: true}), do: nil

  def error_lang(%Ecto.Changeset{} = changeset) do
    own = Ecto.Changeset.get_field(changeset, :lang)

    if Enum.any?(changeset.errors, fn {f, _} ->
         to_string(f) in ~w(title summary body image_alt)
       end),
       do: own,
       else:
         Enum.find_value(translation_changesets(changeset), fn t ->
           t.errors != [] && Ecto.Changeset.get_field(t, :lang)
         end)
  end

  defp translation_changesets(changeset) do
    case changeset.changes[:translations] do
      list when is_list(list) -> Enum.filter(list, &match?(%Ecto.Changeset{}, &1))
      _ -> []
    end
  end

  @doc "A field's input name in a form, as its params arrive: `post[title]`."
  def field_name(%Phoenix.HTML.Form{name: form}, field), do: "#{form}[#{field}]"

  @doc "A URL with more query parameters (its own kept)."
  def with_query(url, params) do
    sep = if String.contains?(url, "?"), do: "&", else: "?"
    url <> sep <> URI.encode_query(params)
  end

  defp translate({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end

  attr :action, :string, required: true
  attr :method, :string, default: "post"
  attr :class, :string, default: "btn-quiet btn-sm"
  attr :confirm, :string, default: nil
  slot :inner_block, required: true

  # a one-button form (publish, revoke, delete): POST with the CSRF token
  def button_to(assigns) do
    ~H"""
    <.form for={%{}} action={@action} method={@method} class="btn-form">
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
    <span class="vis">
      <.form
        :for={value <- ~w(public private)}
        for={%{}}
        action={@action}
        method="post"
        class="btn-form"
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
    <span :if={@tags != []} class="tags">
      <span :for={tag <- @tags} class={["tag", tag.color]}>{tag.name}</span>
    </span>
    """
  end

  attr :tags, :list, required: true
  attr :selected, :any, default: nil
  attr :href, :any, required: true, doc: "a function from a tag (or nil) to its link"

  @doc "The ?tag= filter: every tag as a link, the chosen one marked."
  def tag_filter(assigns) do
    ~H"""
    <div :if={@tags != []} class="tagbar">
      <a class={["tag", is_nil(@selected) && "on"]} href={@href.(nil)}>
        {gettext("All tags")}
      </a>
      <a
        :for={tag <- @tags}
        class={["tag", tag.color, @selected && @selected.id == tag.id && "on"]}
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

  @doc """
  The editor's tag picker, a form_for :custom block's content: one
  checkbox chip per tag; an empty value clears them all.
  """
  def tag_picker(assigns) do
    ~H"""
    <input type="hidden" name={@name} value="" />
    <div :if={@tags != []} class="tagpick">
      <label :for={tag <- @tags} class={["tag", tag.color]}>
        <input type="checkbox" name={@name} value={tag.id} checked={tag.id in @selected} />
        {tag.name}
      </label>
    </div>
    <div class="hint">
      {gettext("Private: only content managers see tags.")}
      <a href={~p"/manage/tags"}>{gettext("Manage tags")}</a>
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
