// The behaviour of the shared components (apps/ui), for every app's
// bundle: copy buttons, the menus of <details> (language, dropdown
// buttons), local times and date pickers, linked table rows, the theme
// switch and the contact fields. Everything listens on the document or
// watches it, so it works on pages with and without LiveView; importing
// this module installs it once.
import {PhoneField, installContactFields} from "./contact_fields"

export {PhoneField}

// ----------------------------------------------------------------
// the clipboard
// ----------------------------------------------------------------

// put text on the clipboard: the Clipboard API on secure pages, the
// old textarea + execCommand path elsewhere; done(ok) either way
export function copyText(text, done) {
  if (navigator.clipboard && window.isSecureContext) {
    navigator.clipboard.writeText(text).then(() => done(true), () => done(false))
  } else {
    const area = document.createElement("textarea")
    area.value = text
    area.style.position = "fixed"
    area.style.opacity = "0"
    document.body.appendChild(area)
    area.select()
    let ok = false
    try { ok = document.execCommand("copy") } catch (_e) { ok = false }
    area.remove()
    done(ok)
  }
}

// copy/1: [data-copy] buttons put their payload on the clipboard and
// say so for a moment, in the words the button carries
document.addEventListener("click", e => {
  const btn = e.target.closest("[data-copy]")
  if (!btn) return
  const idle = btn.dataset.labelCopy || btn.textContent
  const done = ok => {
    btn.classList.toggle("copied", ok)
    btn.textContent = ok ? (btn.dataset.labelCopied || idle) : idle
    setTimeout(() => {
      btn.classList.remove("copied")
      btn.textContent = idle
    }, 1500)
  }
  copyText(btn.dataset.copy, done)
})

// ----------------------------------------------------------------
// menus, linked rows
// ----------------------------------------------------------------

const MENUS = "details[data-langs][open], details[data-menu][open]"

// the language menu and dropdown buttons close on any click outside
// them or on Escape
document.addEventListener("click", e => {
  document.querySelectorAll(MENUS).forEach(d => { if (!d.contains(e.target)) d.open = false })
})
document.addEventListener("keydown", e => {
  if (e.key === "Escape") document.querySelectorAll(MENUS).forEach(d => { d.open = false })
})

// a linked table row opens its page; links, buttons and fields inside
// keep their own click, and a text selection is left alone
document.addEventListener("click", e => {
  const row = e.target.closest("tr[data-href]")
  if (!row || e.target.closest("a, button, input, select, textarea, label")) return
  if (String(window.getSelection())) return
  if (e.metaKey || e.ctrlKey) window.open(row.dataset.href, "_blank")
  else window.location.assign(row.dataset.href)
})

// ----------------------------------------------------------------
// the theme switch: each click moves light -> auto -> dark; auto
// follows the system; the choice is kept in this browser under the
// button's data-theme-key
// ----------------------------------------------------------------

const THEMES = ["light", "auto", "dark"]
const themeKey = () => document.querySelector('[data-cycle="theme"]')?.dataset.themeKey || "theme"
const storedTheme = () => {
  try { return localStorage.getItem(themeKey()) || "auto" } catch (_e) { return "auto" }
}
const markTheme = () => {
  const current = storedTheme()
  document.querySelectorAll('[data-cycle="theme"]').forEach(b => {
    b.dataset.state = current
    const label = b.dataset["label" + current.charAt(0).toUpperCase() + current.slice(1)]
    if (label) b.setAttribute("aria-label", label)
  })
}
const applyTheme = choice => {
  if (choice === "auto") delete document.documentElement.dataset.theme
  else document.documentElement.dataset.theme = choice
  try {
    choice === "auto" ? localStorage.removeItem(themeKey()) : localStorage.setItem(themeKey(), choice)
  } catch (_e) { /* private mode */ }
  markTheme()
}
document.addEventListener("click", e => {
  if (e.target.closest('[data-cycle="theme"]')) applyTheme(THEMES[(THEMES.indexOf(storedTheme()) + 1) % THEMES.length])
})
window.addEventListener("phx:page-loading-stop", markTheme)

// ----------------------------------------------------------------
// times: the server sends UTC instants; they show in the account's
// time zone (<html data-tz>) or the device's, in the page's language
// ----------------------------------------------------------------

export const viewerZone = () => document.documentElement.dataset.tz || undefined
const viewerLocale = () => (document.documentElement.lang === "uk" ? "uk" : "en-GB")
const WHEN = {
  date: {day: "numeric", month: "short", year: "numeric"},
  day: {day: "numeric", month: "short"},
  datetime: {day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit"},
  short: {day: "numeric", month: "short", hour: "2-digit", minute: "2-digit"},
  weekday_time: {weekday: "short", hour: "2-digit", minute: "2-digit"},
  time: {hour: "2-digit", minute: "2-digit"},
}
export const formatWhen = (iso, as) =>
  new Intl.DateTimeFormat(viewerLocale(), {...WHEN[as], hour12: false, timeZone: viewerZone()}).format(new Date(iso))
export const clock = (iso) => formatWhen(iso, "time")

const zonedParts = (iso, zone) => {
  const parts = new Intl.DateTimeFormat("en-GB", {timeZone: zone, year: "numeric", month: "2-digit",
    day: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23"}).formatToParts(new Date(iso))
  const p = Object.fromEntries(parts.map(part => [part.type, part.value]))
  return [`${p.year}-${p.month}-${p.day}`, `${p.hour}:${p.minute}`]
}

// a date and time typed in the viewer's zone, as the UTC "YYYY-MM-DD"
// and "HH:MM" the server stores
export const toUtcParts = (date, time, zone) => {
  const guess = new Date(`${date}T${time || "00:00"}:00Z`)
  const shown = new Date(guess.toLocaleString("en-US", {timeZone: zone || Intl.DateTimeFormat().resolvedOptions().timeZone}))
  const offset = shown.getTime() - new Date(guess.toLocaleString("en-US", {timeZone: "UTC"})).getTime()
  const utc = new Date(guess.getTime() - offset)
  return [utc.toISOString().slice(0, 10), utc.toISOString().slice(11, 16)]
}

// the date and time pickers arrive in the server's zone (the account's,
// else the deployment's); here they show the viewer's, and the form
// tells the server which zone they were typed in
const localizePickers = () => {
  const zone = viewerZone() || Intl.DateTimeFormat().resolvedOptions().timeZone
  document.querySelectorAll('.half > input[type="hidden"][name="zone"]').forEach(input => {
    if (input.value === zone) return
    const box = input.parentElement
    if (box.dataset.at) {
      const [date, time] = zonedParts(box.dataset.at, zone)
      box.querySelector('input[type="date"]').value = date
      box.querySelector('input[type="time"]').value = time
    }
    input.value = zone
  })
}

// an app's own fields that show times the same way (cab's prep end)
const localizers = []
export const addLocalizer = fn => { localizers.push(fn); fn() }

const localizeTimes = () => {
  document.querySelectorAll("time[data-when]").forEach(t => {
    const text = formatWhen(t.getAttribute("datetime"), t.dataset.when)
    if (t.textContent !== text) t.textContent = text
  })
  localizePickers()
  localizers.forEach(fn => fn())
}

// ----------------------------------------------------------------
// start: once the document is there
// ----------------------------------------------------------------

installContactFields()

const start = () => {
  markTheme()
  localizeTimes()
  // live updates re-render times in UTC; put them back in the viewer's zone
  new MutationObserver(localizeTimes).observe(document.documentElement,
    {subtree: true, childList: true, characterData: true, attributes: true, attributeFilter: ["value"]})
  // phone fields outside a LiveView (inside one, the PhoneField hook
  // mounts them); mounting twice changes nothing
  document.querySelectorAll(".phonefield").forEach(el => {
    if (!el.closest("[data-phx-session]")) PhoneField.mounted.call({el})
  })
}
if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start)
else start()
