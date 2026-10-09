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

const Hooks = {BallotMath, PrepClock, Allocator}

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
