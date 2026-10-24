// Contact fields: phone (per country), e-mail, Telegram - the typing
// helpers of cab's :phone / :email / :telegram form blocks (CabWeb.Ui
// form_for). The server checks every value again; these only help people
// type them. cab's app.js uses this module; other sites load the
// standalone build, cab's /assets/js/contact-fields.js
// (contact_fields_page.js), on pages that render these blocks.
// The messages come from the fields' data-msg-* attributes, which the
// blocks render in the page's language.
import * as libphone from "../vendor/libphonenumber-min"

const msg = (input, kind, fallback) =>
  input.dataset["msg" + kind.charAt(0).toUpperCase() + kind.slice(1)] || fallback

// the library's own object (its default export is the parse function)
const lpn = typeof libphone.getCountries === "function" ? libphone : libphone.default

// a region's flag, built from its ISO code (no emoji in the source)
const flag = (code) => String.fromCodePoint(...[...code].map(ch => 0x1F1E6 + ch.charCodeAt(0) - 65))

// a phone field: the +code in the picker before it (flag and code), the
// national number in the field, spaced as it is typed; a +code typed or
// pasted into the field moves to the picker; checked when the field is
// left (see the field checks below); it goes out as +E.164
export const PhoneField = {
  mounted() {
    const input = this.el.querySelector('input[type="tel"]')
    if (!input || this.el.querySelector(".phonecountry")) return
    const select = document.createElement("select")
    select.className = "phonecountry"
    select.setAttribute("aria-label", (this.el.dataset.msgCountry || "Country"))
    // no country yet: just the +, the code typed decides
    const any = document.createElement("option")
    any.value = ""
    any.textContent = "+"
    select.appendChild(any)
    // only flag and code, by code (+1 ..., +7 ...), a flag telling
    // apart the countries that share one
    lpn.getCountries()
      .map(c => ({c, code: lpn.getCountryCallingCode(c)}))
      .sort((a, b) => Number(a.code) - Number(b.code) || a.c.localeCompare(b.c))
      .forEach(x => {
        const o = document.createElement("option")
        o.value = x.c
        o.textContent = `${flag(x.c)} +${x.code}`
        select.appendChild(o)
      })
    this.el.insertBefore(select, input)

    // the code lives in the picker, the field keeps the national number:
    // a +code typed or pasted into the field moves to the picker as soon
    // as it names a country (shared codes like +1 once the digits say
    // which); with a country picked the field takes the national number,
    // spaced as it is typed; the form sends +E.164
    const digitsOf = (v) => v.replace(/\D/g, "")
    const placeholder = input.placeholder
    // the national number spaced for its country: as written there
    // (050 123 4567), or - without the trunk 0, as it is left after a
    // +code - spaced the international way minus the code (50 123 4567)
    const national = (c, digits) => {
      const local = new lpn.AsYouType(c).input(digits)
      if (local !== digits) return local
      const code = "+" + lpn.getCountryCallingCode(c)
      const intl = new lpn.AsYouType().input(code + digits)
      return intl.startsWith(code) ? intl.slice(code.length).trim() : local
    }
    const takeCode = () => {
      const typer = new lpn.AsYouType()
      const shown = typer.input("+" + digitsOf(input.value))
      const c = typer.getCountry()
      if (!c) { input.value = shown; return }
      select.value = c
      const rest = typer.getNationalNumber() || ""
      input.value = rest ? national(c, rest) : ""
    }
    const showPicked = () => { input.placeholder = select.value ? "" : placeholder }
    const fullNumber = () => {
      const d = digitsOf(input.value)
      if (!d) return ""
      if (input.value.trim().startsWith("+")) return "+" + d
      // no country: the digits as typed, the server decides
      if (!select.value) return d
      try { return lpn.parsePhoneNumber(d, select.value).number } catch (_e) {
        return "+" + lpn.getCountryCallingCode(select.value) + d
      }
    }

    // the field checks (below) ask the number whether it is whole
    input.phoneValid = () => { const n = fullNumber(); return !!n && lpn.isValidPhoneNumber(n) }
    const check = () => recheckField(input)
    const format = () => {
      const typed = input.value.trim()
      if (!digitsOf(typed)) { input.value = typed.startsWith("+") ? "+" : ""; check(); return }
      // only a typed + or the picker gives the country: digits with
      // neither stay as typed (no country guessed from them)
      if (typed.startsWith("+")) takeCode()
      else if (select.value) input.value = national(select.value, digitsOf(typed))
      else input.value = digitsOf(typed)
      showPicked()
      check()
    }
    if (input.value.trim().startsWith("+") && digitsOf(input.value)) { takeCode(); showPicked() }
    // reformat only while typing at the end, so an edit in the middle keeps its caret
    input.addEventListener("input", () => (input.selectionStart === input.value.length ? format() : check()))
    // another country: the same national digits, spaced for it
    select.addEventListener("change", () => {
      const d = digitsOf(input.value)
      if (d && !input.value.trim().startsWith("+")) input.value = select.value ? national(select.value, d) : "+" + d
      showPicked()
      input.focus()
      check()
    })
    // picking a country is not leaving the number
    select.addEventListener("focusout", (e) => { if (e.relatedTarget !== input) checkField(input) })
    if (input.form) {
      input.form.addEventListener("submit", () => {
        const n = fullNumber()
        if (n) input.value = n
      })
    }
  },
}

// a Telegram username as people paste it: "@name" from "name",
// "t.me/name" or "https://t.me/name"; letters, digits and _ only
const telegramTyped = (value) => {
  const name = value.trim()
    .replace(/^(https?:\/\/)?(www\.)?(t|telegram)\.me\//i, "")
    .replace(/\/+$/, "").replace(/^@+/, "")
    .replace(/[^A-Za-z0-9_]/g, "").slice(0, 32)
  // a typed @ is the leading one when there is none yet
  return name ? "@" + name : value.includes("@") ? "@" : ""
}

// The contact fields' checks, the server's rules and words: a value is
// cleaned as it is typed and checked as it is typed, but its error
// shows only once the field is left - under it, where the server puts
// its own - and goes away as soon as the value is right again.
const CONTACT = "[data-email], [data-telegram], [data-phone]"
const dotted = (p) => p !== "" && !p.startsWith(".") && !p.endsWith(".") && !p.includes("..")
const emailOk = (v) => {
  if (v.length > 254 || /[\s\p{C}%"'(),:;<>[\]\\]/u.test(v)) return false
  const parts = v.split("@")
  if (parts.length !== 2 || !dotted(parts[0]) || !dotted(parts[1])) return false
  const labels = parts[1].split(".")
  return labels.length > 1 && /^(\p{L}{2,63}|xn--[a-z0-9-]{1,59})$/iu.test(labels[labels.length - 1])
}
const telegramOk = (v) => /^@?[A-Za-z0-9_]{5,32}$/.test(v)

const contactError = (input) => {
  const v = input.value.trim()
  if (!v) return input.dataset.required ? msg(input, "required", "Fill this in.") : null
  if (input.matches("[data-email]") && !emailOk(v))
    return msg(input, "invalid", "Enter an e-mail address like name@example.com.")
  if (input.matches("[data-telegram]") && !telegramOk(v))
    return msg(input, "invalid", "Enter a Telegram username: 5 to 32 letters, digits or _, like @name or t.me/name.")
  if (input.matches("[data-phone]") && input.phoneValid && !input.phoneValid())
    return msg(input, "invalid", "Enter a full phone number for its country, like +380 50 123 4567.")
  return null
}

// the error under the field (the form's own .error), its hint hidden
// meanwhile, as the server renders a refused answer
const showFieldError = (input, message) => {
  const block = input.closest(".f-block")
  if (!block) return
  let box = block.querySelector(":scope > .error")
  const hint = block.querySelector(":scope > .hint")
  if (message) {
    if (!box) {
      box = document.createElement("div")
      box.className = "error"
      box.setAttribute("aria-live", "polite")
      hint ? block.insertBefore(box, hint) : block.appendChild(box)
    }
    box.textContent = message
  } else if (box) box.remove()
  block.classList.toggle("err", !!message)
  if (hint) hint.hidden = !!message
  input.setAttribute("aria-invalid", message ? "true" : "false")
}
// on leaving the field
const checkField = (input) => showFieldError(input, contactError(input))
// while typing: only an error already shown follows the value
const recheckField = (input) => { if (input.closest(".f-block.err")) checkField(input) }

let installed = false

// the document-wide listeners (typing, leaving a field); once per page
export function installContactFields() {
  if (installed) return
  installed = true
  document.addEventListener("input", e => {
    const el = e.target
    if (!(el instanceof HTMLInputElement)) return
    if (el.matches("[data-email]")) {
      const v = el.value.replace(/\s+/g, "")
      if (v !== el.value) el.value = v
    } else if (el.matches("[data-telegram]")) {
      const v = telegramTyped(el.value)
      if (v !== el.value) el.value = v
    }
    if (el.matches("[data-email], [data-telegram]")) recheckField(el)
  })
  document.addEventListener("focusout", e => {
    const el = e.target
    if (!(el instanceof HTMLInputElement) || !el.matches(CONTACT)) return
    // an e-mail's domain in lowercase once the field is left
    if (el.matches("[data-email]")) {
      const at = el.value.lastIndexOf("@")
      if (at > 0) el.value = el.value.slice(0, at + 1) + el.value.slice(at + 1).toLowerCase()
    }
    // moving from a phone number to its country picker is not leaving it
    const picker = el.closest(".phonefield")?.querySelector(".phonecountry")
    if (picker && e.relatedTarget === picker) return
    checkField(el)
  })
}

// every phone field under `root` set up (a page without LiveView, where
// no hook runs): the same as the PhoneField hook's mounted()
export function mountPhoneFields(root = document) {
  root.querySelectorAll(".phonefield").forEach(el => PhoneField.mounted.call({el}))
}
