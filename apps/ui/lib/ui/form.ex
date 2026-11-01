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
  username: the @ added, t.me links read). A `:text` block may name its
  input type (`input`: email, tel); a `:select` dropdown may lead with
  an empty `prompt` option. A `required` `:text` or `:longtext` block's
  field is `required` in the browser too.

  Server errors render per block: pass `errors` as a map of
  block-name => message; the failing block gets the amber border +
  message, the rest stay untouched.

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
  end

  slot :submit do
    attr :note, :string
    attr :quiet, :boolean, doc: "a plain button when the page's gold action is elsewhere"
    attr :disabled, :boolean, doc: "shown but not usable (a preview)"

    attr :menu, :list,
      doc: "alternatives beside the button (`dropdown_button/1` items); none = a plain button"
  end

  def form_for(assigns) do
    ~H"""
    <form class="form" id={@id} action={@action} method={@method} enctype={@enctype}>
      <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
      <input :for={{name, value} <- @hidden} type="hidden" name={name} value={value} />
      <div :if={@title || @description} class={if @logo, do: "f-head with-logo", else: "f-head"}>
        <img :if={@logo} class="club-logo" src={@logo} alt="" />
        <div>
          <h3 :if={@title}>{@title}</h3>
          <p :if={@description}>{@description}</p>
        </div>
      </div>
      <div :for={block <- @block} class={["f-block", @errors[block[:name]] && "err"]}>
        <label :if={block[:label]} class="q">
          {block[:label]} <span :if={block[:required]} class="req">*</span>
        </label>
        {control(block)}
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
          rows="3"
          name={@name}
          placeholder={@b[:placeholder]}
          maxlength={@b[:maxlength]}
          required={@b[:required]}
        >{@b[:value]}</textarea>
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

  defp option({label, value}), do: {label, value}
  defp option(value), do: {value, value}

  defp same?(nil, _candidate), do: false
  defp same?(value, candidate), do: to_string(value) == to_string(candidate)
end
