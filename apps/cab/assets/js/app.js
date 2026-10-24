// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/cab"
import topbar from "../vendor/topbar"
import * as libphone from "../vendor/libphonenumber-min"

// Words the browser writes itself, in the page's language: the server
// puts them in <meta name="cab-i18n"> (CabWeb.Layouts.js_strings/0);
// the English fallbacks keep pages working without it. `{name}` marks
// a value filled in here.
const T = (() => {
  try { return JSON.parse(document.querySelector('meta[name="cab-i18n"]')?.content || "{}") } catch (_e) { return {} }
})()
const t = (key, fallback, vars = {}) =>
  (T[key] || fallback).replace(/\{(\w+)\}/g, (m, k) => (k in vars ? String(vars[k]) : m))

// ----------------------------------------------------------------
// Hooks: every widget is a LiveView hook, so it survives live
// re-renders. Pages rendered without LiveView mount the same hooks
// once (see mountDeadHooks below) - one implementation for both.
// ----------------------------------------------------------------

// the scored ballot: live team totals, derived ranks, tie warning
const BallotMath = {
  mounted() {
    this.grid = this.el.querySelector("[data-ballot]")
    this.msg = this.el.querySelector(".bfoot")
    this.recalc = () => {
      const teams = [...this.grid.querySelectorAll(".bteam")].map(t => ({
        el: t,
        sum: [...t.querySelectorAll("input[type=number]")].reduce((a, i) => a + (parseInt(i.value, 10) || 0), 0),
      }))
      const sums = teams.map(t => t.sum)
      const tied = sums.some((s, i) => sums.indexOf(s) !== i)
      const order = teams.slice().sort((a, b) => b.sum - a.sum)
      const names = [t("place_1", "1st"), t("place_2", "2nd"), t("place_3", "3rd"), t("place_4", "4th")]
      teams.forEach(team => {
        team.el.querySelector(".tot").textContent = String(team.sum)
        team.el.querySelector(".rk").textContent =
          names[order.indexOf(team)] || t("place_n", "{n}th", {n: order.indexOf(team) + 1})
        team.el.querySelector(".bsum").classList.toggle("tied", teams.some(o => o !== team && o.sum === team.sum))
      })
      if (!this.msg || this.msg.querySelector(".err.server")) return
      if (tied) {
        const err = document.createElement("span")
        err.className = "err"
        err.textContent = t("ballot_tied", "Two teams share a total. BP allows no ties, so adjust the scores.")
        this.msg.replaceChildren(err)
      } else {
        this.msg.textContent = t("ballot_ready", "Ready to submit.")
      }
    }
    this.grid.addEventListener("input", this.recalc)
    this.recalc()
  },
  updated() { this.recalc && this.recalc() },
}

// the prep clock on the room page: counts down to data-prep-deadline
const PrepClock = {
  mounted() {
    this.tick = () => {
      const left = new Date(this.el.dataset.prepDeadline) - Date.now()
      this.el.textContent =
        left <= 0
          ? t("prep_over", "prep time is over — debate")
          : t("prep_left", "prep: {time} left", {
              time: `${Math.floor(left / 60000)}:${String(Math.floor(left / 1000) % 60).padStart(2, "0")}`,
            })
    }
    this.tick()
    this.timer = setInterval(this.tick, 1000)
  },
  updated() { this.tick() },
  destroyed() { clearInterval(this.timer) },
}

// the allocator: drag reports a drop to the server - place {id, slot}
// or unplace {id}; the server owns the draft and re-renders the table.
// A placed chip released anywhere but a slot goes back to the tray.
const Allocator = {
  mounted() {
    let dragged = null
    let landed = false
    const accepts = slot => slot && dragged
    const clearOver = () => this.el.querySelectorAll(".slot.over").forEach(s => s.classList.remove("over"))

    this.el.addEventListener("dragstart", e => {
      const chip = e.target.closest(".chip")
      if (!chip) return
      dragged = chip
      landed = false
      chip.classList.add("dragging")
      e.dataTransfer.setData("text/plain", chip.dataset.id)
    })
    this.el.addEventListener("dragend", () => {
      if (dragged && !landed && dragged.closest(".slot")) {
        this.pushEvent("unplace", {id: parseInt(dragged.dataset.id, 10)})
      }
      if (dragged) dragged.classList.remove("dragging")
      dragged = null
      clearOver()
    })
    this.el.addEventListener("dragover", e => {
      const slot = e.target.closest(".slot")
      if (accepts(slot)) {
        e.preventDefault()
        clearOver()
        slot.classList.add("over")
      } else if (dragged && e.target.closest("[data-drop=tray]")) {
        e.preventDefault()
      }
    })
    this.el.addEventListener("drop", e => {
      if (!dragged) return
      const slot = e.target.closest(".slot")
      const id = parseInt(dragged.dataset.id, 10)
      landed = true
      e.preventDefault()
      clearOver()
      if (accepts(slot)) this.pushEvent("place", {id, slot: slot.dataset.slot})
      else if (e.target.closest("[data-drop=tray]") && dragged.closest(".slot")) this.pushEvent("unplace", {id})
    })

    // tap to place, for touch screens (drag and drop needs a mouse):
    // tap a person, then a slot (a taken one swaps); tap Waiting to
    // take a placed person out; tap the picked person again to drop it.
    // The same place/unplace events as a drop.
    this.picked = null
    this.markPicked = () => this.el.querySelectorAll(".chip").forEach(c =>
      c.classList.toggle("picked", this.picked !== null && c.dataset.id === String(this.picked)))
    const pick = id => { this.picked = id; this.markPicked() }
    this.el.addEventListener("click", e => {
      const chip = e.target.closest(".chip")
      const slot = e.target.closest(".slot")
      const tray = e.target.closest("[data-drop=tray]")
      if (this.picked === null) return chip ? pick(parseInt(chip.dataset.id, 10)) : undefined
      if (chip && chip.dataset.id === String(this.picked)) return pick(null)
      if (slot) {
        this.pushEvent("place", {id: this.picked, slot: slot.dataset.slot})
        return pick(null)
      }
      if (tray) {
        if (this.el.querySelector(`.slot .chip[data-id="${this.picked}"]`)) this.pushEvent("unplace", {id: this.picked})
        else if (chip) return pick(parseInt(chip.dataset.id, 10))
        return pick(null)
      }
    })

    // finger drag: hold a person for a moment, then drag; a copy follows
    // the finger, slots light up, and the release places (on a slot) or
    // takes a placed person out (anywhere else) - the same events as a
    // mouse drop. A quick swipe still scrolls; a quick tap is tap to place.
    const HOLD = 180, MOVE = 8, EDGE = 70
    let touch = null
    const endTouch = () => {
      if (!touch) return
      clearTimeout(touch.timer)
      cancelAnimationFrame(touch.raf)
      if (touch.ghost) touch.ghost.remove()
      touch.chip.classList.remove("dragging")
      clearOver()
      touch = null
    }
    const targetAt = (x, y) => {
      const el = document.elementFromPoint(x, y)
      return el && el.closest(".slot")
    }
    const follow = () => {
      touch.ghost.style.transform = `translate(${touch.x - touch.dx}px, ${touch.y - touch.dy}px)`
    }
    const autoscroll = () => {
      if (!touch || !touch.ghost) return
      const h = window.innerHeight
      const dy = touch.y < EDGE ? -(EDGE - touch.y) / 4 : touch.y > h - EDGE ? (touch.y - (h - EDGE)) / 4 : 0
      if (dy) window.scrollBy(0, dy)
      touch.raf = requestAnimationFrame(autoscroll)
    }
    this.el.addEventListener("touchstart", e => {
      const chip = e.target.closest(".chip")
      if (!chip || e.touches.length > 1) return
      const t = e.touches[0]
      touch = {chip, x: t.clientX, y: t.clientY, x0: t.clientX, y0: t.clientY, ghost: null}
      touch.timer = setTimeout(() => {
        if (!touch) return
        const r = chip.getBoundingClientRect()
        const ghost = chip.cloneNode(true)
        ghost.classList.add("ghost")
        ghost.style.width = `${r.width}px`
        touch.dx = touch.x - r.left
        touch.dy = touch.y - r.top
        document.body.appendChild(ghost)
        touch.ghost = ghost
        chip.classList.add("dragging")
        pick(null)
        follow()
        autoscroll()
        if (navigator.vibrate) navigator.vibrate(10)
      }, HOLD)
    }, {passive: true})
    this.el.addEventListener("touchmove", e => {
      if (!touch) return
      const t = e.touches[0]
      touch.x = t.clientX
      touch.y = t.clientY
      if (!touch.ghost) {
        if (Math.hypot(touch.x - touch.x0, touch.y - touch.y0) > MOVE) endTouch()
        return
      }
      e.preventDefault()
      follow()
      clearOver()
      const slot = targetAt(touch.x, touch.y)
      if (slot) slot.classList.add("over")
    }, {passive: false})
    this.el.addEventListener("touchend", e => {
      if (!touch) return
      if (!touch.ghost) return endTouch()
      e.preventDefault()
      const id = parseInt(touch.chip.dataset.id, 10)
      const slot = targetAt(touch.x, touch.y)
      if (slot) this.pushEvent("place", {id, slot: slot.dataset.slot})
      else if (touch.chip.closest(".slot")) this.pushEvent("unplace", {id})
      endTouch()
    })
    this.el.addEventListener("touchcancel", endTouch)

    // on touch screens the browser's own drag would fight the finger drag
    this.touchOnly = () => {
      if (window.matchMedia("(pointer: coarse)").matches) {
        this.el.querySelectorAll(".chip[draggable]").forEach(c => c.removeAttribute("draggable"))
      }
    }
    this.touchOnly()
  },
  updated() {
    if (this.markPicked) this.markPicked()
    if (this.touchOnly) this.touchOnly()
  },
}

// the room card: a PNG people paste into a messenger - who, when, the
// motion once published, the draw, the judge, and the room's short
// link as a QR code. Drawn from the server's data-card JSON.
const CARD = {
  w: 1600, pad: 64, gap: 72,
  brand: "#66347E", gold: "#D99A2B", ink: "#1C1722", muted: "#6E6478",
  line: "#E6DFEC", paper: "#FFFFFF", tint: "#F6F1F9",
  sans: '-apple-system, "Inter", "Segoe UI", system-ui, sans-serif',
}

// Times: the server sends UTC instants; they show in the account's
// time zone (<html data-tz>) or the device's, in the page's language.
const viewerZone = () => document.documentElement.dataset.tz || undefined
const viewerLocale = () => (document.documentElement.lang === "uk" ? "uk" : "en-GB")
const WHEN = {
  date: {day: "numeric", month: "short", year: "numeric"},
  day: {day: "numeric", month: "short"},
  datetime: {day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit"},
  short: {day: "numeric", month: "short", hour: "2-digit", minute: "2-digit"},
  weekday_time: {weekday: "short", hour: "2-digit", minute: "2-digit"},
  time: {hour: "2-digit", minute: "2-digit"},
}
const formatWhen = (iso, as) =>
  new Intl.DateTimeFormat(viewerLocale(), {...WHEN[as], hour12: false, timeZone: viewerZone()}).format(new Date(iso))
const clock = (iso) => formatWhen(iso, "time")

const localizeTimes = () => {
  document.querySelectorAll("time[data-when]").forEach(t => {
    const text = formatWhen(t.getAttribute("datetime"), t.dataset.when)
    if (t.textContent !== text) t.textContent = text
  })
  // the prep end arrives as a UTC instant; the head reads and types HH:MM
  document.querySelectorAll('input[name="prep_until"]').forEach(input => {
    if (/T/.test(input.value)) input.value = clock(input.value)
  })
}
// live updates re-render times in UTC; put them back in the viewer's zone
new MutationObserver(localizeTimes).observe(document.documentElement,
  {subtree: true, childList: true, characterData: true, attributes: true, attributeFilter: ["value"]})
document.addEventListener("DOMContentLoaded", localizeTimes)
localizeTimes()

// a date and time typed in the viewer's zone, as the UTC "YYYY-MM-DD"
// and "HH:MM" the server stores
const toUtcParts = (date, time, zone) => {
  const guess = new Date(`${date}T${time || "00:00"}:00Z`)
  const shown = new Date(guess.toLocaleString("en-US", {timeZone: zone || Intl.DateTimeFormat().resolvedOptions().timeZone}))
  const offset = shown.getTime() - new Date(guess.toLocaleString("en-US", {timeZone: "UTC"})).getTime()
  const utc = new Date(guess.getTime() - offset)
  return [utc.toISOString().slice(0, 10), utc.toISOString().slice(11, 16)]
}
document.addEventListener("submit", e => {
  const form = e.target.closest("#open-session-form")
  if (!form) return
  const date = form.querySelector('[name="date"]'), time = form.querySelector('[name="time"]')
  if (!date || !/^\d{4}-\d{2}-\d{2}$/.test(date.value.trim())) return
  const hhmm = time && time.value.trim().match(/^(\d{1,2}):(\d{2})$/)
  if (time && time.value.trim() && !hhmm) return
  const [d, t] = toUtcParts(date.value.trim(), hhmm && `${hhmm[1].padStart(2, "0")}:${hhmm[2]}`, viewerZone())
  date.value = d
  if (time && time.value) time.value = t
}, true)

// the prep end typed as HH:MM in the viewer's zone goes out as a UTC
// instant: today, or tomorrow when that time is already long past
document.addEventListener("submit", e => {
  const input = e.target.querySelector && e.target.querySelector('input[name="prep_until"]')
  if (!input) return
  const hhmm = input.value.trim().match(/^(\d{1,2})[:.](\d{2})$/)
  if (!hhmm) return
  const zone = viewerZone()
  const today = new Intl.DateTimeFormat("en-CA", {timeZone: zone}).format(new Date())
  const [d, t] = toUtcParts(today, `${hhmm[1].padStart(2, "0")}:${hhmm[2]}`, zone)
  let at = new Date(`${d}T${t}:00Z`)
  if (at.getTime() < Date.now() - 12 * 3600 * 1000) at = new Date(at.getTime() + 24 * 3600 * 1000)
  input.value = at.toISOString()
}, true)

const wrapLines = (ctx, text, width) => {
  const lines = []
  let line = ""
  for (const word of String(text).split(/\s+/)) {
    const next = line ? `${line} ${word}` : word
    if (ctx.measureText(next).width > width && line) { lines.push(line); line = word }
    else line = next
  }
  if (line) lines.push(line)
  return lines
}

// a card's header band: the mark and `big` (the room, or the word for
// results) | the session, club and time | the short link and its QR.
// Returns its height.
const drawBand = (ctx, d, big, draw) => {
  const {w} = CARD
  const pad = 44
  const font = (weight, size, family = CARD.sans) => { ctx.font = `${weight} ${size}px ${family}` }
  const text = (s, x, yy, color) => { if (draw) { ctx.fillStyle = color; ctx.fillText(s, x, yy) } }
  const soft = "rgba(255,255,255,.78)"
  // header band: mark + room | session, club, time | link + QR
  const qrSize = 148, bandH = qrSize + 40
  if (draw) { ctx.fillStyle = CARD.brand; ctx.fillRect(0, 0, w, bandH) }
  font(400, 44, '"Cedarville Cursive", cursive'); text("cab", pad, 62, CARD.paper)
  font(800, big.length > 4 ? 44 : 64); text(big, pad, 150, CARD.paper)

  const qrX = w - pad - qrSize, qrY = 20
  const qr = d.qr || []
  if (draw) { ctx.fillStyle = CARD.paper; ctx.fillRect(qrX, qrY, qrSize, qrSize) }
  if (qr.length && draw) {
    const n = qr.length, quiet = 2, cell = Math.floor(qrSize / (n + quiet * 2))
    const off = Math.floor((qrSize - cell * n) / 2)
    ctx.fillStyle = CARD.ink
    qr.forEach((row, rr) => { for (let c = 0; c < n; c++) if (row[c] === "1") ctx.fillRect(qrX + off + c * cell, qrY + off + rr * cell, cell, cell) })
  }
  ctx.textAlign = "right"
  font(600, 20); text(t("card_scan", "Scan or open"), qrX - 24, 92, soft)
  font(800, 28); text(d.link_text, qrX - 24, 128, CARD.paper)
  ctx.textAlign = "left"

  // the session in the middle of the band
  const midX = pad + 220
  font(800, 28); const linkW = ctx.measureText(d.link_text).width
  const midW = qrX - 24 - linkW - 40 - midX
  font(800, 32)
  const title = wrapLines(ctx, d.session || "", midW).slice(0, 2)
  let by = title.length > 1 ? 70 : 88
  for (const l of title) { text(l, midX, by, CARD.paper); by += 38 }
  const when = d.starts ? formatWhen(d.starts, "short") : formatWhen(d.date, "date")
  font(500, 24); text(`${d.club}, ${when}`, midX, by + 2, soft)

  return bandH
}

// the room card, landscape and slim: one header band - the mark and
// the room, the session, the QR with the short link; then the motion
// and the draw as one row - a column per side with the people who
// speak there, then the adjudicators (the chair marked)
const drawCard = (canvas, d, draw = true) => {
  const ctx = canvas.getContext("2d")
  const {w} = CARD
  const pad = 44
  const inner = w - pad * 2
  const font = (weight, size, family = CARD.sans) => { ctx.font = `${weight} ${size}px ${family}` }
  const text = (s, x, yy, color) => { if (draw) { ctx.fillStyle = color; ctx.fillText(s, x, yy) } }
  const rule = (x, yy, width) => { if (draw) { ctx.fillStyle = CARD.line; ctx.fillRect(x, yy, width, 2) } }

  if (draw) { ctx.fillStyle = CARD.paper; ctx.fillRect(0, 0, canvas.width, canvas.height) }

  const bandH = drawBand(ctx, d, d.room, draw)

  // the motion
  let y = bandH + 50
  if (d.motion) {
    font(800, 18); text(t("card_motion", "MOTION"), pad, y, CARD.gold); y += 36
    font(700, 32)
    for (const l of wrapLines(ctx, d.motion, inner)) { text(l, pad, y, CARD.ink); y += 40 }
    if (d.infoslide) {
      y += 2; font(400, 22)
      for (const l of wrapLines(ctx, d.infoslide, inner)) { text(l, pad, y, CARD.muted); y += 30 }
    }
    if (d.prep_until) {
      y += 4; font(600, 22)
      text(t("card_prep", "Prep until {time}", {time: clock(d.prep_until)}), pad, y, CARD.brand); y += 30
    }
  } else {
    font(500, 24); text(t("card_no_motion", "Motion: not published yet"), pad, y, CARD.muted); y += 30
  }
  y += 30

  // the draw: OG | OO | CG | CO | Adjudicators
  const cols = [...d.sides.map(s => ({head: s.side, lines: s.people.map(p => ({s: p, bold: true}))})),
    {head: t("card_adjudicators", "Adjudicators"),
     lines: d.judges.map(j => ({s: j.chair ? `${j.name} \u00A9` : j.name, bold: j.chair}))}]
  const colW = inner / cols.length
  font(800, 20)
  cols.forEach((c, k) => text(c.head, pad + k * colW, y, CARD.brand))
  y += 16; rule(pad, y, inner); y += 38
  let tallest = 1
  cols.forEach((c, k) => {
    let cy = y
    const lines = c.lines.length ? c.lines : [{s: "\u2014", bold: false}]
    for (const l of lines) {
      font(l.bold ? 700 : 400, 26)
      for (const part of wrapLines(ctx, l.s, colW - 20)) { text(part, pad + k * colW, cy, l.bold ? CARD.ink : CARD.muted); cy += 34 }
    }
    tallest = Math.max(tallest, (cy - y) / 34)
  })
  y += tallest * 34 - 8
  return y + pad - 10
}

// the same room as short plain text, for a chat that takes no pictures
const cardText = (d) => {
  const when = d.starts ? formatWhen(d.starts, "short") : formatWhen(d.date, "date")
  const lines = [`${d.room} - ${d.session}, ${when}`]
  lines.push(d.motion ? t("text_motion", "Motion: {motion}", {motion: d.motion}) : t("card_no_motion", "Motion: not published yet"))
  if (d.infoslide) lines.push(t("text_infoslide", "Infoslide: {text}", {text: d.infoslide}))
  for (const s of d.sides) lines.push(`${s.side}: ${s.people.join(", ") || "\u2014"}`)
  const judges = d.judges.map(j => (j.chair ? `${j.name} \u00A9` : j.name)).join(", ")
  lines.push(t("text_adjudicators", "Adjudicators: {names}", {names: judges || "\u2014"}), d.link_text)
  return lines.join("\n")
}

// a finished session's results card: the band, then every room as a
// table - its keyword and motion above, a header row, one row per side
// in place order (one speaker per line, their points beside the name;
// the side's speaker points; its team points), the winner tinted
const drawResults = (canvas, d, draw = true) => {
  const ctx = canvas.getContext("2d")
  const {w} = CARD
  const pad = 44
  const inner = w - pad * 2
  const font = (weight, size, family = CARD.sans) => { ctx.font = `${weight} ${size}px ${family}` }
  const text = (s, x, yy, color) => { if (draw) { ctx.fillStyle = color; ctx.fillText(s, x, yy) } }
  const right = (s, x, yy, color) => { ctx.textAlign = "right"; text(s, x, yy, color); ctx.textAlign = "left" }
  const box = (x, yy, bw, bh, color) => { if (draw) { ctx.fillStyle = color; ctx.fillRect(x, yy, bw, bh) } }
  const pts = (p) => (p == null ? "\u2014" : String(Math.round(p * 10) / 10))

  if (draw) { ctx.fillStyle = CARD.paper; ctx.fillRect(0, 0, canvas.width, canvas.height) }
  let y = drawBand(ctx, d, t("card_results", "Results"), draw) + 46

  const xPlace = pad + 16, xSide = pad + 120, xPeople = pad + 220
  const xTeam = w - pad - 16, xSpk = xTeam - 230
  const lineH = 36

  for (const room of d.rooms) {
    // the room: keyword and motion
    font(800, 28); text(room.keyword ? `${room.room}  ${room.keyword}` : room.room, pad, y, CARD.brand); y += 36
    if (room.motion) {
      font(600, 24)
      for (const l of wrapLines(ctx, room.motion, inner)) { text(l, pad, y, CARD.ink); y += 32 }
    }
    if (room.infoslide) {
      font(400, 20)
      for (const l of wrapLines(ctx, room.infoslide, inner)) { text(l, pad, y, CARD.muted); y += 27 }
    }
    y += 16

    // header row
    box(pad, y, inner, 44, CARD.tint)
    font(800, 17)
    text(t("card_place", "PLACE"), xPlace, y + 29, CARD.muted)
    text(t("card_side", "SIDE"), xSide, y + 29, CARD.muted)
    text(t("card_speakers", "SPEAKERS"), xPeople, y + 29, CARD.muted)
    right(t("card_speaker_points", "SPEAKER POINTS"), xSpk, y + 29, CARD.muted)
    right(t("card_team_points", "TEAM POINTS"), xTeam, y + 29, CARD.muted)
    y += 44

    for (const row of room.rows) {
      const people = row.speakers.length ? row.speakers : [{name: "\u2014", points: null}]
      const rowH = people.length * lineH + 22
      if (row.winner) box(pad, y, inner, rowH, "#FBF3E2")
      box(pad, y + rowH - 2, inner, 2, CARD.line)
      const base = y + 12 + 26
      const weight = row.winner ? 800 : 600
      font(weight, 26); text(row.place || "\u2014", xPlace, base, CARD.ink)
      font(800, 26); text(row.side, xSide, base, CARD.brand)
      people.forEach((sp, n) => {
        const yy = base + n * lineH
        font(weight, 26); text(sp.name, xPeople, yy, CARD.ink)
        const nameW = ctx.measureText(sp.name).width
        font(600, 24); text(pts(sp.points), xPeople + nameW + 14, yy, row.winner ? CARD.ink : CARD.muted)
      })
      font(weight, 26); right(pts(row.points), xSpk, base, CARD.ink)
      font(800, 28); right(pts(row.team_points), xTeam, base, row.winner ? CARD.brand : CARD.ink)
      y += rowH
    }
    y += 40
  }
  return y + pad - 40
}

// the results as short plain text
const resultsText = (d) => {
  const pts = (p) => (p == null ? "\u2014" : String(Math.round(p * 10) / 10))
  const when = d.starts ? formatWhen(d.starts, "short") : formatWhen(d.date, "date")
  const lines = [`${d.session}, ${when} - ${t("card_results", "Results")}`]
  for (const room of d.rooms) {
    lines.push("", room.keyword ? `${room.room} - ${room.keyword}` : room.room)
    if (room.motion) lines.push(t("text_motion", "Motion: {motion}", {motion: room.motion}))
    if (room.infoslide) lines.push(t("text_infoslide", "Infoslide: {text}", {text: room.infoslide}))
    for (const row of room.rows) {
      const people = row.speakers.map(s => `${s.name} ${pts(s.points)}`).join(", ")
      lines.push(`${row.place || "\u2014"} ${row.side}: ${people} - ${pts(row.points)} (${t("text_team_points", "team points: {points}", {points: pts(row.team_points)})})`)
    }
  }
  lines.push("", d.link_text)
  return lines.join("\n")
}

// a share card (a room, or a session's results): the picture and the
// text side by side; clicking (or Enter/Space on) either copies it
const CARDS = {room: [drawCard, cardText], results: [drawResults, resultsText]}
const ShareCard = {
  mounted() {
    this.canvas = this.el.querySelector("canvas")
    this.textBox = this.el.querySelector("[data-card-text]")
    this.msg = this.el.querySelector(".sharemsg")
    this.render = async () => {
      const d = JSON.parse(this.el.dataset.card)
      const [draw, asText] = CARDS[d.kind] || CARDS.room
      try { await document.fonts.load('60px "Cedarville Cursive"') } catch (_e) { /* fallback face */ }
      const probe = document.createElement("canvas")
      probe.width = CARD.w; probe.height = 10
      const h = draw(probe, d, false)
      this.canvas.width = CARD.w; this.canvas.height = h
      draw(this.canvas, d)
      if (this.textBox) this.textBox.textContent = asText(d)
    }
    this.say = (s) => { if (this.msg) { this.msg.textContent = s; setTimeout(() => { this.msg.textContent = "" }, 2500) } }
    const copyImage = () => {
      const blob = new Promise((resolve) => this.canvas.toBlob(resolve, "image/png"))
      if (navigator.clipboard && window.ClipboardItem) {
        navigator.clipboard.write([new ClipboardItem({"image/png": blob})])
          .then(
            () => this.say(t("card_copied", "Copied. Paste it into the chat.")),
            () => this.say(t("card_no_copy", "This browser cannot copy pictures. Right-click or hold the picture to save it.")),
          )
      } else this.say(t("card_no_copy", "This browser cannot copy pictures. Right-click or hold the picture to save it."))
    }
    const copyCardText = () =>
      copyText(this.textBox.textContent, ok =>
        this.say(ok ? t("card_copied", "Copied. Paste it into the chat.") : t("card_no_copy_text", "This browser cannot copy. Select the text and copy it.")))
    const act = (e) => {
      if (e.target.closest("[data-card-image]")) copyImage()
      else if (e.target.closest("[data-card-text]")) copyCardText()
    }
    this.el.addEventListener("click", act)
    this.el.addEventListener("keydown", (e) => { if (e.key === "Enter" || e.key === " ") { if (e.target.closest("[data-card-image], [data-card-text]")) { e.preventDefault(); act(e) } } })
    this.render()
  },
  updated() { this.render && this.render() },
}

// ----------------------------------------------------------------
// Contact fields: phone (per country), e-mail, Telegram. The server
// checks every value again; these only help people type them.
// ----------------------------------------------------------------
// the library's own object (its default export is the parse function)
const lpn = typeof libphone.getCountries === "function" ? libphone : libphone.default

// a region's flag, built from its ISO code (no emoji in the source)
const flag = (code) => String.fromCodePoint(...[...code].map(ch => 0x1F1E6 + ch.charCodeAt(0) - 65))

// a phone field: always international - a typed or pasted +code picks
// the country in the picker before it (choosing one there writes its
// code), the number is spaced as it is typed; checked when the field is
// left (see the field checks below); it goes out as +E.164 when valid
const PhoneField = {
  mounted() {
    const input = this.el.querySelector('input[type="tel"]')
    if (!input || this.el.querySelector(".phonecountry")) return
    const lang = document.documentElement.lang || "en"
    let names = null
    try { names = new Intl.DisplayNames([lang], {type: "region"}) } catch (_e) { /* names stay codes */ }

    const select = document.createElement("select")
    select.className = "phonecountry"
    select.setAttribute("aria-label", t("phone_country", "Country"))
    const any = document.createElement("option")
    any.value = ""
    any.textContent = t("phone_any", "Other: type the +code")
    select.appendChild(any)
    lpn.getCountries()
      .map(c => ({c, name: (names && names.of(c)) || c, code: lpn.getCountryCallingCode(c)}))
      .sort((a, b) => a.name.localeCompare(b.name, lang))
      .forEach(x => {
        const o = document.createElement("option")
        o.value = x.c
        // flag and code first: the narrow closed picker shows just them
        o.textContent = `${flag(x.c)} +${x.code} ${x.name}`
        select.appendChild(o)
      })
    this.el.insertBefore(select, input)

    // the country comes only from the number's own +code: the field is
    // always international ("+" in front), the code picks the country
    // in the picker, and picking a country writes its +code
    const digitsOf = (v) => v.replace(/\D/g, "")
    const codeOf = (c) => "+" + lpn.getCountryCallingCode(c)
    const follow = (typer, number) => {
      const c = typer.getCountry()
      if (c) select.value = c
      else if (select.value && !number.startsWith(codeOf(select.value))) select.value = ""
    }
    if (digitsOf(input.value)) {
      const typer = new lpn.AsYouType()
      input.value = typer.input("+" + digitsOf(input.value))
      follow(typer, "+" + digitsOf(input.value))
    }

    // the field checks (below) ask the number whether it is whole
    input.phoneValid = () => lpn.isValidPhoneNumber(input.value.trim())
    const check = () => recheckField(input)
    const format = () => {
      const digits = digitsOf(input.value)
      if (!digits) { input.value = ""; check(); return }
      const typer = new lpn.AsYouType()
      input.value = typer.input("+" + digits)
      follow(typer, "+" + digits)
      check()
    }
    // reformat only while typing at the end, so an edit in the middle keeps its caret
    input.addEventListener("input", () => (input.selectionStart === input.value.length ? format() : check()))
    // picking a country puts its +code in front of the number's own digits
    select.addEventListener("change", () => {
      let national = ""
      try { national = lpn.parsePhoneNumber("+" + digitsOf(input.value)).nationalNumber || "" } catch (_e) { /* no number yet */ }
      input.value = select.value ? new lpn.AsYouType().input(codeOf(select.value) + national) : ""
      input.focus()
      check()
    })
    // picking a country is not leaving the number
    select.addEventListener("focusout", (e) => { if (e.relatedTarget !== input) checkField(input) })
    if (input.form) {
      input.form.addEventListener("submit", () => {
        if (!digitsOf(input.value)) return
        try { const p = lpn.parsePhoneNumber(input.value.trim()); if (p && p.isValid()) input.value = p.number } catch (_e) { /* the server answers */ }
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
  return name ? "@" + name : ""
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
  if (!v) return input.dataset.required ? t("field_required", "Fill this in.") : null
  if (input.matches("[data-email]") && !emailOk(v))
    return t("field_email", "Enter an e-mail address like name@example.com.")
  if (input.matches("[data-telegram]") && !telegramOk(v))
    return t("field_telegram", "Enter a Telegram username: 5 to 32 letters, digits or _, like @name or t.me/name.")
  if (input.matches("[data-phone]") && input.phoneValid && !input.phoneValid())
    return t("field_phone", "Enter a full phone number for its country, like +380 50 123 4567.")
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

// put text on the clipboard: the Clipboard API on secure pages, the
// old textarea + execCommand path elsewhere; done(ok) either way
function copyText(text, done) {
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

// the People list's Copy links: the server renders the checked guests'
// lines into data-links; after copying, it says how many went
const CopyLinks = {
  mounted() {
    this.el.addEventListener("click", () => {
      const text = this.el.dataset.links || ""
      if (!text) return this.pushEvent("links_copied", {ok: true})
      copyText(text, ok => this.pushEvent("links_copied", {ok}))
    })
  },
}

const Hooks = {BallotMath, PrepClock, Allocator, ShareCard, CopyLinks, PhoneField}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...Hooks},
})

// pages rendered without LiveView: run each hook's mounted() once on
// elements outside any LiveView (inside one, LiveView mounts it)
const mountDeadHooks = () => {
  document.querySelectorAll("[phx-hook]").forEach(el => {
    if (el.closest("[data-phx-session]")) return
    const hook = Hooks[el.getAttribute("phx-hook")]
    if (hook) Object.assign(Object.create(hook), {el, pushEvent() {}}).mounted()
  })
}
mountDeadHooks()

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// the sidebar theme button: each click moves light -> auto -> dark.
// auto follows the system; the choice is kept in this browser.
const themeKey = "cab-theme"
const THEMES = ["light", "auto", "dark"]
const storedTheme = () => {
  try { return localStorage.getItem(themeKey) || "auto" } catch (_e) { return "auto" }
}
const applyTheme = (choice) => {
  if (choice === "auto") delete document.documentElement.dataset.theme
  else document.documentElement.dataset.theme = choice
  try { choice === "auto" ? localStorage.removeItem(themeKey) : localStorage.setItem(themeKey, choice) } catch (_e) { /* private mode */ }
  markTheme()
}
const markTheme = () => {
  const current = storedTheme()
  document.querySelectorAll('[data-cycle="theme"]').forEach(b => {
    b.dataset.state = current
    b.setAttribute("aria-label", t("theme_" + current, "Theme: " + current))
  })
}
// a linked table row opens its page; links, buttons and fields inside
// keep their own click, and a text selection is left alone
document.addEventListener("click", e => {
  const row = e.target.closest("tr[data-href]")
  if (!row || e.target.closest("a, button, input, select, textarea, label")) return
  if (String(window.getSelection())) return
  if (e.metaKey || e.ctrlKey) window.open(row.dataset.href, "_blank")
  else window.location.assign(row.dataset.href)
})

document.addEventListener("click", e => {
  const theme = e.target.closest('[data-cycle="theme"]')
  if (theme) applyTheme(THEMES[(THEMES.indexOf(storedTheme()) + 1) % THEMES.length])
  // the language menu and dropdown buttons close on any click outside them
  document.querySelectorAll("details[data-langs][open], details[data-menu][open]").forEach(d => { if (!d.contains(e.target)) d.open = false })
})
document.addEventListener("keydown", e => {
  if (e.key === "Escape") document.querySelectorAll("details[data-langs][open], details[data-menu][open]").forEach(d => { d.open = false })
})
markTheme()
window.addEventListener("phx:page-loading-stop", markTheme)

// the phone menu: the sidenav folds into a top bar with a Menu button.
// The open state lives on <html>, which LiveView never patches, so a
// server update cannot close it under the reader's thumb.
const setNav = open => {
  document.documentElement.classList.toggle("nav-open", open)
  document.querySelectorAll("[data-nav-toggle]").forEach(b => b.setAttribute("aria-expanded", String(open)))
}
document.addEventListener("click", e => {
  if (e.target.closest("[data-nav-toggle]")) return setNav(!document.documentElement.classList.contains("nav-open"))
  if (e.target.closest("#sidenav-menu a")) setNav(false)
})
document.addEventListener("keydown", e => { if (e.key === "Escape") setNav(false) })
window.addEventListener("phx:page-loading-stop", () => setNav(false))

// copy affordance: [data-copy] buttons put their payload on the
// clipboard (shared registration URL, personal guest links)
document.addEventListener("click", e => {
  const btn = e.target.closest("[data-copy]")
  if (!btn) return
  const done = ok => {
    btn.classList.toggle("copied", ok)
    btn.textContent = ok ? t("copied", "Copied") : t("copy", "Copy")
    setTimeout(() => {
      btn.classList.remove("copied")
      btn.textContent = t("copy", "Copy")
    }, 1500)
  }
  copyText(btn.dataset.copy, done)
})

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
