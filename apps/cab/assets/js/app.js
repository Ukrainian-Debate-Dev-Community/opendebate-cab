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

// ----------------------------------------------------------------
// Hooks: every widget is a LiveView hook, so it survives live
// re-renders. Pages rendered without LiveView mount the same hooks
// once (see mountDeadHooks below) — one implementation for both.
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
      const names = ["1st", "2nd", "3rd", "4th"]
      teams.forEach(t => {
        t.el.querySelector(".tot").textContent = String(t.sum)
        t.el.querySelector(".rk").textContent = names[order.indexOf(t)] || `${order.indexOf(t) + 1}th`
        t.el.querySelector(".bsum").classList.toggle("tied", teams.some(o => o !== t && o.sum === t.sum))
      })
      if (!this.msg || this.msg.querySelector(".err.server")) return
      this.msg.innerHTML = tied
        ? '<span class="err">Two teams share a total — BP forbids ties. Adjust scores to submit.</span>'
        : "All totals distinct — ballot valid. Submit lives in the chrome."
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
          ? "prep time is over — debate"
          : `prep: ${Math.floor(left / 60000)}:${String(Math.floor(left / 1000) % 60).padStart(2, "0")} left`
    }
    this.tick()
    this.timer = setInterval(this.tick, 1000)
  },
  updated() { this.tick() },
  destroyed() { clearInterval(this.timer) },
}

// the allocator: drag reports a drop to the server — place {id, slot}
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
  },
}

// the room card: a PNG people paste into a messenger — who, when, the
// motion once published, the draw, the judge, and the room's short
// link as a QR code. Drawn from the server's data-card JSON.
const CARD = {
  w: 1080, pad: 64,
  brand: "#66347E", gold: "#D99A2B", ink: "#1C1722", muted: "#6E6478",
  line: "#E6DFEC", paper: "#FFFFFF", tint: "#F6F1F9",
  sans: '-apple-system, "Inter", "Segoe UI", system-ui, sans-serif',
}

// an ISO instant as the viewer's local clock time, 24-hour
const clock = (iso) => new Date(iso).toLocaleTimeString([], {hour: "2-digit", minute: "2-digit", hour12: false})

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

const drawCard = (canvas, d, draw = true) => {
  const ctx = canvas.getContext("2d")
  const {w, pad} = CARD
  const inner = w - pad * 2
  let y = 0
  const font = (weight, size, family = CARD.sans) => { ctx.font = `${weight} ${size}px ${family}` }
  const text = (s, x, yy, color) => { if (draw) { ctx.fillStyle = color; ctx.fillText(s, x, yy) } }

  if (draw) { ctx.fillStyle = CARD.paper; ctx.fillRect(0, 0, canvas.width, canvas.height) }

  // header band: the mark and the room
  if (draw) { ctx.fillStyle = CARD.brand; ctx.fillRect(0, 0, w, 132) }
  font(400, 60, '"Cedarville Cursive", cursive'); text("cab", pad, 88, CARD.paper)
  font(800, 56); ctx.textAlign = "right"; text(d.room, w - pad, 88, CARD.paper); ctx.textAlign = "left"
  y = 132 + 64

  font(800, 40)
  for (const l of wrapLines(ctx, d.session || "", inner)) { text(l, pad, y, CARD.ink); y += 50 }
  font(500, 30); text(`${d.club}, ${d.date}`, pad, y, CARD.muted); y += 44
  if (d.starts) { font(700, 30); text(`Starts at ${clock(d.starts)}`, pad, y, CARD.ink); y += 44 }
  y += 20

  if (d.motion) {
    font(800, 22); text("MOTION", pad, y, CARD.gold); y += 44
    font(700, 36)
    for (const l of wrapLines(ctx, d.motion, inner)) { text(l, pad, y, CARD.ink); y += 46 }
    if (d.infoslide) {
      y += 6; font(400, 26)
      for (const l of wrapLines(ctx, d.infoslide, inner)) { text(l, pad, y, CARD.muted); y += 34 }
    }
    if (d.prep_until) { y += 8; font(600, 26); text(`Prep until ${clock(d.prep_until)}`, pad, y, CARD.brand); y += 34 }
    y += 30
  } else {
    font(500, 28); text("Motion: not published yet", pad, y, CARD.muted); y += 62
  }

  // the draw
  font(800, 22); text("DRAW", pad, y, CARD.gold); y += 22
  for (const t of d.teams) {
    const rowH = 76
    if (draw) { ctx.fillStyle = CARD.line; ctx.fillRect(pad, y, inner, 2) }
    font(800, 26); text(t.side, pad, y + 48, CARD.brand)
    const named = t.speakers && t.speakers !== t.team
    font(700, 30); text(t.team, pad + 90, named ? y + 34 : y + 48, CARD.ink)
    if (named) { font(400, 24); text(t.speakers, pad + 90, y + 64, CARD.muted) }
    y += rowH
  }
  if (draw) { ctx.fillStyle = CARD.line; ctx.fillRect(pad, y, inner, 2) }
  font(600, 28); text(`Adjudicator: ${d.judge}`, pad, y + 48, CARD.ink); y += 96

  // footer: the QR and the short link
  const qr = d.qr || []
  const qrSize = 240
  if (draw) { ctx.fillStyle = CARD.tint; ctx.fillRect(0, y, w, qrSize + pad * 2) }
  if (qr.length && draw) {
    const n = qr.length, quiet = 3, cell = Math.floor(qrSize / (n + quiet * 2))
    const ox = pad, oy = y + pad
    ctx.fillStyle = CARD.paper; ctx.fillRect(ox, oy, cell * (n + quiet * 2), cell * (n + quiet * 2))
    ctx.fillStyle = CARD.ink
    qr.forEach((row, r) => { for (let c = 0; c < n; c++) if (row[c] === "1") ctx.fillRect(ox + (c + quiet) * cell, oy + (r + quiet) * cell, cell, cell) })
  }
  const tx = pad + qrSize + 40
  font(600, 26); text("Scan or open", tx, y + pad + 70, CARD.muted)
  font(800, 34); text(d.link_text, tx, y + pad + 120, CARD.ink)
  font(500, 24); text("this room's draw and motion, live", tx, y + pad + 162, CARD.muted)
  y += qrSize + pad * 2
  return y
}

const RoomCard = {
  mounted() {
    this.canvas = this.el.querySelector("canvas")
    this.msg = this.el.querySelector(".sharemsg")
    this.render = async () => {
      const d = JSON.parse(this.el.dataset.card)
      try { await document.fonts.load('60px "Cedarville Cursive"') } catch (_e) { /* fallback face */ }
      const probe = document.createElement("canvas")
      probe.width = CARD.w; probe.height = 10
      const h = drawCard(probe, d, false)
      this.canvas.width = CARD.w; this.canvas.height = h
      drawCard(this.canvas, d)
      this.name = `cab-${(d.room || "room").toLowerCase()}.png`
    }
    this.say = (s) => { if (this.msg) { this.msg.textContent = s; setTimeout(() => { this.msg.textContent = "" }, 2500) } }
    this.el.addEventListener("click", (e) => {
      if (e.target.closest("[data-card-copy]")) {
        const blob = new Promise((resolve) => this.canvas.toBlob(resolve, "image/png"))
        if (navigator.clipboard && window.ClipboardItem) {
          navigator.clipboard.write([new ClipboardItem({"image/png": blob})])
            .then(() => this.say("Copied. Paste it into the chat."), () => this.say("This browser cannot copy images. Use Save image."))
        } else this.say("This browser cannot copy images. Use Save image.")
      }
      if (e.target.closest("[data-card-save]")) {
        const a = document.createElement("a")
        a.download = this.name
        a.href = this.canvas.toDataURL("image/png")
        a.click()
      }
    })
    this.render()
  },
  updated() { this.render && this.render() },
}

const Hooks = {BallotMath, PrepClock, Allocator, RoomCard}

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

// the sidebar switches. Theme: light or dark, starting from the
// system's preference until the first click, then remembered.
const themeKey = "cab-theme"
const systemDark = () => window.matchMedia("(prefers-color-scheme: dark)").matches
const currentTheme = () => document.documentElement.dataset.theme || (systemDark() ? "dark" : "light")
const markTheme = () => {
  document.querySelectorAll('[data-switch="theme"]').forEach(s =>
    s.setAttribute("aria-checked", String(currentTheme() === "dark")))
}
document.addEventListener("click", e => {
  const theme = e.target.closest('[data-switch="theme"]')
  if (theme) {
    const next = currentTheme() === "dark" ? "light" : "dark"
    document.documentElement.dataset.theme = next
    try { localStorage.setItem(themeKey, next) } catch (_e) { /* private mode */ }
    markTheme()
    return
  }
  // language: the thumb slides first, then the page reloads in it
  const lang = e.target.closest('[data-switch="lang"]')
  if (lang) {
    e.preventDefault()
    lang.setAttribute("aria-checked", String(lang.getAttribute("aria-checked") !== "true"))
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    setTimeout(() => { window.location.href = lang.href }, reduce ? 0 : 240)
  }
})
markTheme()
window.addEventListener("phx:page-loading-stop", markTheme)

// copy affordance: [data-copy] buttons put their payload on the
// clipboard (shared registration URL, personal guest links)
document.addEventListener("click", e => {
  const btn = e.target.closest("[data-copy]")
  if (!btn) return
  const done = ok => {
    btn.classList.toggle("copied", ok)
    btn.textContent = ok ? "copied" : "copy"
    setTimeout(() => {
      btn.classList.remove("copied")
      btn.textContent = "copy"
    }, 1500)
  }
  if (navigator.clipboard && window.isSecureContext) {
    navigator.clipboard.writeText(btn.dataset.copy).then(() => done(true), () => done(false))
  } else {
    const area = document.createElement("textarea")
    area.value = btn.dataset.copy
    area.style.position = "fixed"
    area.style.opacity = "0"
    document.body.appendChild(area)
    area.select()
    let ok = false
    try { ok = document.execCommand("copy") } catch (_e) { ok = false }
    area.remove()
    done(ok)
  }
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
