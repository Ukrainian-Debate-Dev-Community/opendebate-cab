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

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks},
})

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

// ----------------------------------------------------------------
// Design-system v2 widgets (vanilla JS, no LiveView) — ported from
// design/components-v2.html: table sort, ballot math, elim count.
// ----------------------------------------------------------------

// table: client-side sort on th.sort + header select-all checkbox
document.querySelectorAll("table.t").forEach(table => {
  const headers = table.querySelectorAll("th.sort")
  headers.forEach(th => {
    th.addEventListener("click", () => {
      const was = th.classList.contains("desc")
      headers.forEach(x => x.classList.remove("asc", "desc"))
      th.classList.add(was ? "asc" : "desc")
      const tb = table.tBodies[0]
      const idx = [...th.parentNode.children].indexOf(th)
      ;[...tb.rows]
        .sort((a, b) => {
          const r = a.cells[idx].innerText.localeCompare(b.cells[idx].innerText, undefined, {numeric: true})
          return was ? r : -r
        })
        .forEach(r => tb.appendChild(r))
      ;[...tb.rows].forEach((r, i) => {
        const rank = r.querySelector("td.rank")
        if (rank) rank.innerText = i + 1
      })
    })
  })
  const all = table.querySelector("thead input[type=checkbox]")
  if (all) {
    all.addEventListener("click", () => {
      table.querySelectorAll("tbody input[type=checkbox]").forEach(cb => (cb.checked = all.checked))
    })
  }
})

// scored ballot: live totals, derived ranks, tie detection
document.querySelectorAll(".ballot [data-ballot]").forEach(grid => {
  const msg = grid.closest(".ballot").querySelector(".bfoot")
  const recalc = () => {
    const teams = [...grid.querySelectorAll(".bteam")].map(t => ({
      el: t,
      sum: [...t.querySelectorAll("input[type=number]")].reduce((a, i) => a + (parseFloat(i.value) || 0), 0),
    }))
    const sums = teams.map(t => t.sum)
    const tied = sums.some((s, i) => sums.indexOf(s) !== i)
    const order = teams.slice().sort((a, b) => b.sum - a.sum)
    const names = ["1st", "2nd", "3rd", "4th"]
    teams.forEach(t => {
      t.el.querySelector(".tot").textContent = t.sum.toFixed(1)
      t.el.querySelector(".rk").textContent = names[order.indexOf(t)] || `${order.indexOf(t) + 1}th`
      t.el.querySelector(".bsum").classList.toggle("tied", teams.some(o => o !== t && o.sum === t.sum))
    })
    if (!msg) return
    msg.innerHTML = tied
      ? '<span class="err">Two teams share a total - BP forbids ties. Adjust scores to submit.</span>'
      : "All totals distinct - ballot valid. Submit lives in the chrome."
  }
  grid.addEventListener("input", recalc)
  recalc()
})

// dnd table: tray chips -> slots, kind gating, swap-on-occupied (the
// displaced chip returns to the dragged chip's origin), drag-to-tray
// unassigns; slots mirror hidden inputs so submit stays a plain POST
document.querySelectorAll("form[data-dnd]").forEach(dnd => {
  const tray = dnd.querySelector("[data-tray]")
  let dragged = null
  let origin = null

  dnd.addEventListener("dragstart", e => {
    const chip = e.target.closest(".chip")
    if (!chip) return
    dragged = chip
    origin = chip.parentElement
    chip.classList.add("dragging")
  })
  dnd.addEventListener("dragend", () => {
    if (dragged) dragged.classList.remove("dragging")
    dragged = null
  })

  const targetOf = e => {
    const slot = e.target.closest(".slot")
    if (slot && dragged && slot.dataset.kind === dragged.dataset.kind) return slot
    if (e.target.closest("[data-tray]")) return tray
    return null
  }

  dnd.addEventListener("dragover", e => {
    const t = targetOf(e)
    if (!t) return
    e.preventDefault()
    if (t !== tray) t.classList.add("over")
  })
  dnd.addEventListener("dragleave", e => {
    const slot = e.target.closest(".slot")
    if (slot) slot.classList.remove("over")
  })
  dnd.addEventListener("drop", e => {
    const t = targetOf(e)
    if (!t || !dragged) return
    e.preventDefault()
    if (t !== tray) {
      t.classList.remove("over")
      const occupant = t.querySelector(".chip")
      if (occupant)
        (origin.classList && origin.classList.contains("slot") ? origin : tray).appendChild(occupant)
    }
    t.appendChild(dragged)
    refresh()
  })

  const refresh = () => {
    const count = tray.querySelectorAll(".chip").length
    const label = tray.querySelector("[data-tray-count]")
    if (label) label.textContent = count
    // slots mirror into the hidden form inputs — same POST as the API
    dnd.querySelectorAll(".slot").forEach(slot => {
      const input = slot.querySelector("input[type=hidden]")
      const chip = slot.querySelector(".chip")
      if (input) input.value = chip ? chip.dataset.id : ""
    })
    // live per-row status: empty / incomplete / ready (+ iron xN)
    dnd.querySelectorAll("tbody tr").forEach(tr => {
      const status = tr.querySelector(".status")
      if (!status) return
      const teams = [...tr.querySelectorAll("td.team")].map(td => td.querySelectorAll(".chip").length)
      const judge = tr.querySelector("td:nth-last-child(2) .chip")
      const filled = teams.reduce((a, b) => a + b, 0)
      const irons = teams.filter(n => n === 1).length
      if (filled === 0 && !judge) status.innerHTML = '<span class="tag tag-mut">empty</span>'
      else if (teams.every(n => n >= 1) && judge)
        status.innerHTML =
          '<span class="tag tag-ok">ready</span>' +
          (irons ? ` <span class="tag tag-warn">iron x${irons}</span>` : "")
      else status.innerHTML = '<span class="tag tag-warn">incomplete</span>'
    })
  }
  refresh()
})

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

// elim ballot: exactly N teams advance
document.querySelectorAll(".ballot [data-advance]").forEach(grid => {
  const msg = grid.closest(".ballot").querySelector(".bfoot")
  const n = parseInt(grid.dataset.advance, 10)
  const check = () => {
    const ticked = grid.querySelectorAll("input:checked").length
    if (!msg) return
    msg.innerHTML =
      ticked === n
        ? `${ticked} of ${n} advancing - valid.`
        : `<span class="err">${ticked} of ${n} advancing - tick exactly ${n} teams.</span>`
  }
  grid.addEventListener("input", check)
  check()
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

