defmodule Ui.Form do
  @moduledoc """
  The one form every write goes through, `form_for/1`, and its field
  blocks. Generic: the caller passes the action, the values and, for a
  public form, its Turnstile site key.
  """

  use Phoenix.Component
  use Gettext, backend: Ui.Gettext

  import Phoenix.Controller, only: [get_csrf_token: 0]
  import Ui.Components, only: [dropdown_button: 1]

  @doc """
  One form component for every write: violet top rule, head block
  (title + description), field blocks divided by hairlines, tinted
  submit block with one gold button + consequence note. POSTs to the
  same REST action the API exposes.

  Block types (the complete inventory): `:text`, `:longtext`, `:int`,
  `:float`, `:scale` (flush integer segments), `:yesno` (two pills),
  `:select` (pills at 2-4 options, dropdown at 5+), `:multi` (stacked
  checks), `:check` (one yes box), `:datetime` (the phone's date and
  time pickers side by side, pass `names`; `value` prefills them with
  `at`'s `[date, time]` in `zone` - the caller converts, ui keeps no
  zone database - and `zone` goes along as `zone`: app.js puts the
  viewer's own there, without one the server reads the account's), `:file` (an
  image picker with the current one's `preview`
  and a `remove` box; pass `enctype="multipart/form-data"`), `:phone`
  (a number with a country picker, formatted as it is typed; the
  picker opens on the app's default country, else the visitor's region;
  without JS a plain field taking a +code), `:email` (the e-mail
  keyboard, spaces dropped, the domain lowercased), `:telegram` (a
  username: the @ added, t.me links read), `:date` (the date picker
  alone), `:rich` (formatted text, see `rich/1`) and `:custom` (the
  block's own content: an app's control under the kit's label and
  hint). A `:longtext` or `:rich` block may ask for more `rows`. A `:text` block may name its
  input type (`input`: email, tel); a `:select` dropdown may lead with
  an empty `prompt` option. A `required` `:text` or `:longtext` block's
  field is `required` in the browser too.

  A form can hold versions of the same blocks (a text in two languages):
  give each such block a `group` and name, as `switch`, the `:select`
  block that chooses between them; only the chosen group's blocks show,
  and choosing another pill swaps them in place (ui.js) - every field
  is still sent.

  Server errors render per block: pass `errors` as a map of
  block-name => message; the failing block gets the amber border +
  message, the rest stay untouched.

  A `method` other than get and post (put, delete) goes as a post with
  the `_method` field Plug reads.

      <.form_for action="/sessions" title="Open a session" description="...">
        <:block name={:name} type={:text} label="Session name" required hint="..." />
        <:block name={:rooms} type={:int} label="Rooms" min={1} max={6} />
        <:submit note="Members get the sign-up right away.">Open session</:submit>
      </.form_for>
  """
  attr :action, :string, required: true
  attr :method, :string, default: "post"
  attr :id, :string, default: nil
  attr :title, :string, default: nil
  attr :description, :string, default: nil
  attr :errors, :map, default: %{}, doc: "block name => server-side error message"
  attr :hidden, :list, default: [], doc: "extra hidden inputs as {name, value}"
  attr :enctype, :string, default: nil, doc: "multipart/form-data for a :file block"
  attr :logo, :string, default: nil, doc: "an image beside the head block (a logo)"

  attr :submit_event, :string,
    default: nil,
    doc: "a LiveView's phx-submit event instead of the POST"

  attr :switch, :string,
    default: nil,
    doc: "the :select block whose value shows that `group` only"

  attr :guard, :string,
    default: nil,
    doc: "a public form's bot protection before the submit block: the Turnstile site key"

  slot :block do
    attr :name, :any
    attr :names, :list, doc: "the two field names of a :datetime pair"
    attr :type, :atom
    attr :label, :string
    attr :required, :boolean
    attr :hint, :string
    attr :min, :any
    attr :max, :any
    attr :step, :any
    attr :value, :any, doc: "the current value; a :datetime pair's [date, time] in `zone`"
    attr :at, :any, doc: "a :datetime pair's current instant (UTC)"
    attr :zone, :string, doc: "the zone a :datetime pair is typed in"
    attr :options, :list, doc: "choices for :select / :multi, strings or {label, value}"
    attr :placeholder, :string
    attr :input, :string, doc: "a :text block's input type: email, tel (default text)"
    attr :prompt, :string, doc: "a :select dropdown's empty first option"
    attr :maxlength, :integer
    attr :list, :string, doc: "a :text block's <datalist> id, for suggestions while typing"
    attr :other, :string, doc: "a :select pills value that opens a free-text field when chosen"
    attr :other_name, :any, doc: "that free-text field's name"
    attr :other_value, :string, doc: "that free-text field's current text"
    attr :other_placeholder, :string
    attr :accept, :string, doc: "a :file block's accepted types"
    attr :preview, :string, doc: "a :file block's current image"
    attr :preview_alt, :string, doc: "that image's text"
    attr :remove, :string, doc: "a :file block's remove box name (shown with a preview)"
    attr :remove_label, :string
    attr :rows, :integer, doc: "a :longtext or :rich block's height in lines"
    attr :upload, :string, doc: "a :rich block's image upload address (none: no Image button)"
    attr :group, :string, doc: "shown only while the form's `switch` block has this value"
  end

  slot :submit do
    attr :note, :string
    attr :quiet, :boolean, doc: "a plain button when the page's gold action is elsewhere"
    attr :disabled, :boolean, doc: "shown but not usable (a preview)"

    attr :menu, :list,
      doc: "alternatives beside the button (`dropdown_button/1` items); none = a plain button"
  end

  def form_for(assigns) do
    assigns =
      assign(assigns,
        verb: if(assigns.method in ["get", "post"], do: assigns.method, else: "post"),
        override: if(assigns.method not in ["get", "post"], do: assigns.method),
        shown: switched(assigns)
      )

    ~H"""
    <form
      class="form"
      id={@id}
      action={@action}
      method={@verb}
      enctype={@enctype}
      data-switch={@switch}
      phx-submit={@submit_event}
    >
      <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
      <input :if={@override} type="hidden" name="_method" value={@override} />
      <input :for={{name, value} <- @hidden} type="hidden" name={name} value={value} />
      <div :if={@title || @description} class={if @logo, do: "f-head with-logo", else: "f-head"}>
        <img :if={@logo} class="club-logo" src={@logo} alt="" />
        <div>
          <h3 :if={@title}>{@title}</h3>
          <p :if={@description}>{@description}</p>
        </div>
      </div>
      <div
        :for={block <- @block}
        class={["f-block", @errors[block[:name]] && "err"]}
        data-group={block[:group]}
        hidden={block[:group] && to_string(block[:group]) != @shown}
      >
        <label :if={block[:label]} class="q">
          {block[:label]} <span :if={block[:required]} class="req">*</span>
        </label>
        {if block[:type] == :custom, do: render_slot(block), else: control(block)}
        <div :if={@errors[block[:name]]} class="error">{@errors[block[:name]]}</div>
        <div :if={block[:hint] && !@errors[block[:name]]} class="hint">{block[:hint]}</div>
      </div>
      <.bot_guard :if={@guard} site_key={@guard} error={@errors[:turnstile]} />
      <div :for={submit <- @submit} class="f-submit">
        <.dropdown_button
          :if={submit[:menu] not in [nil, []]}
          items={submit[:menu]}
          quiet={submit[:quiet]}
          disabled={submit[:disabled]}
        >
          {render_slot(submit)}
        </.dropdown_button>
        <button
          :if={submit[:menu] in [nil, []]}
          type="submit"
          class={if submit[:quiet], do: "btn-quiet", else: "btn-go"}
          disabled={submit[:disabled]}
        >
          {render_slot(submit)}
        </button>
        <span :if={submit[:note]} class="note">{submit[:note]}</span>
      </div>
    </form>
    """
  end

  # the value of the block named by `switch`: the group shown first
  defp switched(%{switch: nil}), do: nil

  defp switched(%{switch: name, block: blocks}) do
    Enum.find_value(blocks, fn b -> to_string(b[:name]) == name && to_string(b[:value]) end)
  end

  # the Turnstile widget (when configured) in its own block; it follows
  # the footer's light/dark choice, the system's otherwise
  attr :site_key, :string, required: true
  attr :error, :string, default: nil

  defp bot_guard(assigns) do
    ~H"""
    <div class={["f-block", "f-guard", @error && "err"]}>
      <div
        class="cf-turnstile"
        data-sitekey={@site_key}
        data-language={Gettext.get_locale(Ui.Gettext)}
        data-theme="auto"
        data-size="flexible"
      >
      </div>
      <div :if={@error} class="error">{@error}</div>
      <script>
        (() => {
          const theme = document.documentElement.dataset.theme
          if (theme === "light" || theme === "dark")
            document.querySelectorAll(".cf-turnstile").forEach((el) => (el.dataset.theme = theme))
        })()
      </script>
      <script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer>
      </script>
    </div>
    """
  end

  defp control(block) do
    assigns = %{b: block, name: to_string(block[:name] || "")}

    case block[:type] || :text do
      :text ->
        ~H"""
        <input
          type={@b[:input] || "text"}
          name={@name}
          value={@b[:value]}
          placeholder={@b[:placeholder]}
          maxlength={@b[:maxlength]}
          required={@b[:required]}
          list={@b[:list]}
        />
        """

      :phone ->
        assigns =
          Map.put(assigns, :id, "phone-" <> String.replace(assigns.name, ~r/[^A-Za-z0-9_-]/, "-"))

        ~H"""
        <div class="phonefield" id={@id} phx-hook="PhoneField" data-msg-country={gettext("Country")}>
          <input
            type="tel"
            name={@name}
            value={@b[:value] && Core.Forms.phone_display(@b[:value])}
            placeholder={@b[:placeholder] || "+380 50 123 4567"}
            autocomplete="tel"
            inputmode="tel"
            data-phone
            data-required={@b[:required] && "true"}
            data-msg-required={Ui.FormComponents.answer_error(:required, "text")}
            data-msg-invalid={Ui.FormComponents.answer_error({:invalid, :phone}, "phone")}
          />
        </div>
        """

      :email ->
        ~H"""
        <input
          type="email"
          name={@name}
          value={@b[:value]}
          placeholder={@b[:placeholder] || "name@example.com"}
          maxlength={@b[:maxlength]}
          autocomplete="email"
          inputmode="email"
          data-email
          data-required={@b[:required] && "true"}
          data-msg-required={Ui.FormComponents.answer_error(:required, "text")}
          data-msg-invalid={Ui.FormComponents.answer_error({:invalid, :email}, "email")}
        />
        """

      :telegram ->
        ~H"""
        <input
          type="text"
          name={@name}
          value={@b[:value] && "@" <> String.replace_prefix(to_string(@b[:value]), "@", "")}
          placeholder={@b[:placeholder] || "@username"}
          maxlength="33"
          autocomplete="off"
          autocapitalize="none"
          spellcheck="false"
          data-telegram
          data-required={@b[:required] && "true"}
          data-msg-required={Ui.FormComponents.answer_error(:required, "text")}
          data-msg-invalid={Ui.FormComponents.answer_error({:invalid, :telegram}, "telegram")}
        />
        """

      :longtext ->
        ~H"""
        <textarea
          rows={@b[:rows] || 3}
          name={@name}
          placeholder={@b[:placeholder]}
          maxlength={@b[:maxlength]}
          required={@b[:required]}
        >{@b[:value]}</textarea>
        """

      :rich ->
        ~H"""
        <.rich
          name={@name}
          value={@b[:value]}
          rows={@b[:rows]}
          placeholder={@b[:placeholder]}
          upload={@b[:upload]}
          label={@b[:label]}
        />
        """

      :date ->
        ~H"""
        <input type="date" name={@name} value={@b[:value]} required={@b[:required]} />
        """

      :int ->
        ~H|<input type="number" name={@name} value={@b[:value]} min={@b[:min]} max={@b[:max]} />|

      :float ->
        ~H"""
        <input
          type="number"
          name={@name}
          value={@b[:value]}
          min={@b[:min]}
          max={@b[:max]}
          step={@b[:step]}
          style="width:130px"
        />
        """

      :scale ->
        ~H"""
        <div class="scale">
          <label :for={i <- (@b[:min] || 1)..(@b[:max] || 5)}>
            <input type="radio" name={@name} value={i} checked={same?(@b[:value], i)} />
            <span>{i}</span>
          </label>
        </div>
        """

      :yesno ->
        ~H"""
        <div class="pills">
          <label>
            <input type="radio" name={@name} value="yes" checked={@b[:value] in [true, "yes"]} />
            <span>{gettext("Yes")}</span>
          </label>
          <label>
            <input type="radio" name={@name} value="no" checked={@b[:value] in [false, "no"]} />
            <span>{gettext("No")}</span>
          </label>
        </div>
        """

      :select ->
        options = Enum.map(block[:options] || [], &option/1)
        assigns = Map.put(assigns, :options, options)

        if length(options) <= 4 do
          ~H"""
          <div class="pills-field">
            <div class="pills">
              <label :for={{label, value} <- @options}>
                <input type="radio" name={@name} value={value} checked={same?(@b[:value], value)} />
                <span>{label}</span>
              </label>
            </div>
            <input
              :if={@b[:other]}
              type="text"
              class="pills-other"
              name={to_string(@b[:other_name])}
              value={@b[:other_value]}
              placeholder={@b[:other_placeholder]}
              maxlength="60"
              aria-label={@b[:other_placeholder]}
            />
          </div>
          """
        else
          ~H"""
          <select name={@name}>
            <option :if={@b[:prompt]} value="">{@b[:prompt]}</option>
            <option :for={{label, value} <- @options} value={value} selected={same?(@b[:value], value)}>
              {label}
            </option>
          </select>
          """
        end

      :multi ->
        assigns = Map.put(assigns, :options, Enum.map(block[:options] || [], &option/1))

        ~H"""
        <div class="opts">
          <label :for={{label, value} <- @options}>
            <input
              type="checkbox"
              name={@name <> "[]"}
              value={value}
              checked={value in List.wrap(@b[:value])}
            />
            {label}
          </label>
        </div>
        """

      :check ->
        ~H"""
        <div class="opts">
          <label>
            <input type="checkbox" name={@name} value="yes" checked={@b[:value] in [true, "yes"]} />
            {gettext("Yes")}
          </label>
        </div>
        """

      :file ->
        ~H"""
        <div class="file-field">
          <img
            :if={@b[:preview]}
            class="club-logo lg"
            src={@b[:preview]}
            alt={@b[:preview_alt] || ""}
          />
          <input type="file" name={@name} accept={@b[:accept]} aria-label={@b[:label]} />
          <label :if={@b[:preview] && @b[:remove]} class="file-remove">
            <input type="checkbox" name={@b[:remove]} value="yes" />
            {@b[:remove_label]}
          </label>
        </div>
        """

      :datetime ->
        [date_name, time_name] = Enum.map(block[:names] || [:date, :time], &to_string/1)

        [date_value, time_value] = block[:value] || [nil, nil]

        assigns =
          Map.merge(assigns, %{
            date_name: date_name,
            time_name: time_name,
            date_value: date_value,
            time_value: time_value
          })

        ~H"""
        <div class="half" data-at={@b[:at] && DateTime.to_iso8601(@b[:at])}>
          <input type="date" name={@date_name} value={@date_value} aria-label={gettext("Date")} />
          <input type="time" name={@time_name} value={@time_value} aria-label={gettext("Time")} />
          <input type="hidden" name="zone" value={@b[:zone]} />
        </div>
        """
    end
  end

  @doc """
  A rich text field (a form block of type `:rich`): a toolbar (headings
  2 and 3, bold, italic, lists, quote, link, image, gallery, divider,
  undo, redo) over an editable area, the HTML going out in the textarea named
  `name`. ui.js loads the editor (rich_editor_page.js, TipTap) when the
  page names its bundle in `<meta name="rich-editor-src">`; without
  JavaScript the textarea shows the HTML itself. Images go to `upload`
  (a POST of the file as `image` with the CSRF token, answering JSON
  `{"url": ...}` or `{"error": ...}`); without it there are no Image
  and Gallery buttons. A gallery (several images picked at once, with
  their descriptions and a caption) goes out as
  `<figure class="gallery"><img ...>...<figcaption>...</figcaption></figure>`. The server must sanitise what arrives: the editor only helps.
  """
  attr :name, :string, required: true
  attr :value, :string, default: nil
  attr :rows, :integer, default: nil
  attr :placeholder, :string, default: nil
  attr :upload, :string, default: nil
  attr :label, :string, default: nil

  def rich(assigns) do
    assigns =
      assign(assigns,
        id:
          "rich-" <>
            (assigns.name |> String.replace(~r/[^A-Za-z0-9_-]+/, "-") |> String.trim("-")),
        tools: rich_tools(assigns.upload)
      )

    ~H"""
    <div
      class="rich"
      id={@id}
      data-rich
      data-upload={@upload}
      data-placeholder={@placeholder}
      data-msg-uploading={gettext("Uploading the image...")}
      data-msg-uploading-many={gettext("Uploading the images...")}
      data-msg-upload-failed={gettext("The image could not be uploaded.")}
      phx-update="ignore"
    >
      <div class="rich-head">
        <div class="rich-bar" role="toolbar" aria-label={gettext("Formatting")} hidden>
          <%= for group <- @tools do %>
            <span class="rich-group">
              <button
                :for={{cmd, label} <- group}
                type="button"
                class="rich-tool"
                data-cmd={cmd}
                title={label}
                aria-label={label}
              >
                <.rich_icon name={cmd} />
              </button>
            </span>
          <% end %>
        </div>
        <div class="rich-pop" data-pop="link" hidden>
          <input
            type="text"
            inputmode="url"
            autocapitalize="none"
            spellcheck="false"
            placeholder={gettext("Paste or type the address")}
            aria-label={gettext("Link address")}
            data-link
          />
          <button type="button" class="btn-quiet btn-sm" data-act="link-apply">
            {gettext("Apply")}
          </button>
          <button type="button" class="btn-link" data-act="link-remove">
            {gettext("Remove link")}
          </button>
          <button type="button" class="btn-link" data-act="close">{gettext("Cancel")}</button>
        </div>
        <div :if={@upload} class="rich-pop" data-pop="image" hidden>
          <input
            type="text"
            maxlength="200"
            placeholder={gettext("What the image shows")}
            aria-label={gettext("Image description")}
            data-alt
          />
          <button type="button" class="btn-quiet btn-sm" data-act="alt-apply">
            {gettext("Apply")}
          </button>
          <button type="button" class="btn-link" data-act="close">{gettext("Close")}</button>
        </div>
        <div :if={@upload} class="rich-pop rich-pop--gallery" data-pop="gallery" hidden>
          <ul class="rich-photos" data-gallery-list></ul>
          <input
            type="text"
            maxlength="300"
            placeholder={gettext("A caption under the images (optional)")}
            aria-label={gettext("Gallery caption")}
            data-caption
          />
          <button type="button" class="btn-quiet btn-sm" data-act="gallery-add">
            {gettext("Add images")}
          </button>
          <button type="button" class="btn-link" data-act="close">{gettext("Close")}</button>
          <template data-gallery-row>
            <li class="rich-photo">
              <img src="" alt="" />
              <input
                type="text"
                maxlength="200"
                placeholder={gettext("What the image shows")}
                aria-label={gettext("Image description")}
                data-photo-alt
              />
              <button type="button" class="btn-link" data-act="photo-remove">
                {gettext("Remove")}
              </button>
            </li>
          </template>
        </div>
        <input
          :if={@upload}
          type="file"
          accept="image/jpeg,image/png,image/webp"
          hidden
          data-file
          aria-label={gettext("Image")}
        />
        <input
          :if={@upload}
          type="file"
          accept="image/jpeg,image/png,image/webp"
          multiple
          hidden
          data-files
          aria-label={gettext("Gallery")}
        />
        <div class="rich-status" role="status" aria-live="polite"></div>
      </div>
      <textarea class="rich-source" name={@name} rows={@rows || 14} aria-label={@label}>{@value}</textarea>
    </div>
    """
  end

  defp rich_tools(upload) do
    [
      [{"h2", gettext("Heading 2")}, {"h3", gettext("Heading 3")}],
      [{"bold", gettext("Bold")}, {"italic", gettext("Italic")}],
      [
        {"bullet", gettext("Bullet list")},
        {"ordered", gettext("Numbered list")},
        {"quote", gettext("Quote")}
      ],
      [{"link", gettext("Link")}] ++
        if(upload, do: [{"image", gettext("Image")}, {"gallery", gettext("Gallery")}], else: []) ++
        [{"rule", gettext("Divider")}],
      [{"undo", gettext("Undo")}, {"redo", gettext("Redo")}]
    ]
  end

  attr :name, :string, required: true

  defp rich_icon(%{name: name} = assigns) when name in ~w(h2 h3 bold italic) do
    assigns =
      assign(assigns,
        text: %{"h2" => "H2", "h3" => "H3", "bold" => "B", "italic" => "I"}[name]
      )

    ~H"""
    <span class={["rich-glyph", "rich-glyph--" <> @name]} aria-hidden="true">{@text}</span>
    """
  end

  defp rich_icon(assigns) do
    ~H"""
    <svg viewBox="0 0 20 20" aria-hidden="true">
      <%= case @name do %>
        <% "bullet" -> %>
          <circle cx="4" cy="5" r="1.4" /><circle cx="4" cy="10" r="1.4" /><circle
            cx="4"
            cy="15"
            r="1.4"
          /><path d="M8 5h9M8 10h9M8 15h9" />
        <% "ordered" -> %>
          <path d="M3 3.5h1.5v4M3 7.5h3M2.8 12.2c.4-.6 2.6-.8 2.6.6 0 1-2.6 1.6-2.6 3h2.8M9 5h8M9 10h8M9 15h8" />
        <% "quote" -> %>
          <path d="M4 4v12M8 6h8M8 10h8M8 14h5" />
        <% "link" -> %>
          <path d="M8.5 11.5a3 3 0 0 0 4.2 0l2.6-2.6a3 3 0 0 0-4.2-4.2l-1 1M11.5 8.5a3 3 0 0 0-4.2 0l-2.6 2.6a3 3 0 0 0 4.2 4.2l1-1" />
        <% "image" -> %>
          <rect x="2.5" y="4" width="15" height="12" rx="2" /><circle cx="7" cy="8.2" r="1.4" /><path d="M3 14.5l4.5-4 3.5 3 2.5-2 4 3.5" />
        <% "gallery" -> %>
          <rect x="2.5" y="5.5" width="11" height="11" rx="1.5" /><path d="M6.5 3h9a2 2 0 0 1 2 2v9" /><path d="M3 14l3-2.6 2.5 2 2-1.4 2.5 2.2" />
        <% "rule" -> %>
          <path d="M3 10h14" />
        <% "undo" -> %>
          <path d="M7.5 5L4 8.5 7.5 12M4 8.5h8a4 4 0 0 1 0 8H9" />
        <% "redo" -> %>
          <path d="M12.5 5L16 8.5 12.5 12M16 8.5H8a4 4 0 0 0 0 8h3" />
      <% end %>
    </svg>
    """
  end

  defp option({label, value}), do: {label, value}
  defp option(value), do: {value, value}

  defp same?(nil, _candidate), do: false
  defp same?(value, candidate), do: to_string(value) == to_string(candidate)
end
