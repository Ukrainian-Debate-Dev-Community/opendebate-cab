// The guided tour's player (/tour). Each step shows a demo page in the
// frame (or a title card): a light dim with the step's part cut out and
// outlined, the caption saying whose screen and which page it is, then
// the player types into the page's fields and clicks - the field or
// button acted on gets its own ring - and the next step shows what the
// click led to. The frame's links and forms never act: it is watched,
// not used, but it scrolls. Without this script the page reads as the
// list of steps.
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms))

export const mountTour = () => {
  const root = document.getElementById("tour")
  if (!root) return

  const steps = JSON.parse(root.dataset.steps)
  const $ = selector => root.querySelector(selector)
  const frame = $(".tour-frame")
  const card = $(".tour-card")
  const slider = $(".tour-slider")
  const play = $(".tour-play")
  const chapters = [...root.querySelectorAll("[data-chapter]")]

  let index = 0
  let playing = true
  let run = 0 // bumps on every change: a stale sequence stops
  const lit = {part: null, active: null}

  // "Anna, a speaker on My page"
  const whoWhere = step => step.where
    ? root.dataset.labelWho.replace("%{who}", step.as).replace("%{where}", step.where)
    : (step.as || "")

  // ---- the frame ------------------------------------------------------

  const doc = () => frame.contentDocument
  const view = () => frame.contentWindow

  const loaded = src => new Promise(resolve => {
    if (frame.getAttribute("src") === src && doc() && doc().readyState === "complete") return resolve()
    frame.addEventListener("load", () => resolve(), {once: true})
    frame.setAttribute("src", src)
  })

  // watched, not used: no link, form or drag acts; scrolling still works
  // and keeps the spotlight on its part
  const tame = () => {
    const d = doc()
    if (!d || d.documentElement.classList.contains("in-tour")) return
    d.documentElement.classList.add("in-tour")
    const stop = e => { if (e.isTrusted) { e.preventDefault(); e.stopPropagation() } }
    ;["click", "submit", "dragstart", "mousedown", "keydown"].forEach(type =>
      d.addEventListener(type, stop, true))
    let queued = false
    const repaint = () => {
      if (queued) return
      queued = true
      view().requestAnimationFrame(() => { queued = false; paint() })
    }
    view().addEventListener("scroll", repaint, {passive: true})
    view().addEventListener("resize", repaint)
  }

  const clear = () => {
    const d = doc()
    lit.part = null
    lit.active = null
    if (d) d.querySelectorAll(".tour-dim, .tour-ring-part, .tour-ring-act, .tour-callout, .tour-cursor").forEach(el => el.remove())
  }

  // the sticky bars at the top of the page (the chrome, the phone's nav)
  const topInset = () => {
    let inset = 0
    doc().querySelectorAll(".chrome, .sidenav .bar").forEach(el => {
      const box = el.getBoundingClientRect()
      const style = view().getComputedStyle(el)
      if ((style.position === "sticky" || style.position === "fixed") && box.top < 5 && box.height < 160)
        inset = Math.max(inset, box.bottom)
    })
    return inset
  }

  // ---- the spotlight ------------------------------------------------

  const layer = (className) => {
    const d = doc()
    let el = d.querySelector(`.${className}`)
    if (!el) {
      el = d.createElement("div")
      el.className = className
      d.body.appendChild(el)
    }
    return el
  }

  const padded = (el, pad) => {
    const box = el.getBoundingClientRect()
    return {x: box.left - pad, y: box.top - pad, w: box.width + pad * 2, h: box.height + pad * 2}
  }

  const place = (el, r) => Object.assign(el.style, {
    left: `${r.x}px`, top: `${r.y}px`, width: `${r.w}px`, height: `${r.h}px`
  })

  // the dim over the screen with the part (and the element acted on)
  // cut out, their outlines on top; drawn in screen coordinates, so it
  // is drawn again as the page scrolls
  const paint = () => {
    const d = doc()
    if (!d || !lit.part || !lit.part.isConnected) return
    const v = view()
    const holes = [padded(lit.part, 6)]
    if (lit.active && lit.active.isConnected) holes.push(padded(lit.active, 4))
    const path = `M0 0H${v.innerWidth}V${v.innerHeight}H0Z` +
      holes.map(r => `M${r.x} ${r.y}h${r.w}v${r.h}h${-r.w}Z`).join("")
    layer("tour-dim").style.clipPath = `path(evenodd, "${path}")`
    place(layer("tour-ring-part"), holes[0])
    const ring = layer("tour-ring-act")
    ring.hidden = holes.length < 2
    if (holes[1]) place(ring, holes[1])
  }

  // the caption floats on the screen: below the part, above it, or at
  // the foot for a tall one; it steps aside from what is acted on
  const caption = (step, box) => {
    const d = doc()
    const v = view()
    const callout = d.createElement("div")
    callout.className = "tour-callout"
    callout.setAttribute("role", "status")
    const who = d.createElement("p")
    who.className = "tour-callout-who"
    who.textContent = whoWhere(step)
    const text = d.createElement("p")
    text.textContent = step.text
    callout.append(who, text)
    d.body.appendChild(callout)

    const width = Math.min(340, v.innerWidth - 24)
    callout.style.width = `${width}px`
    callout.style.left = `${Math.min(Math.max(12, box.left), v.innerWidth - width - 12)}px`
    const tall = callout.offsetHeight
    let top
    if (box.bottom + 14 + tall < v.innerHeight - 8) top = box.bottom + 14
    else if (box.top - tall - 14 > topInset() + 8) top = box.top - tall - 14
    else top = v.innerHeight - tall - 12
    callout.style.top = `${top}px`
  }

  const spotlight = (step) => {
    const v = view()
    clear()
    const target = step.target && doc().querySelector(step.target)
    if (!target) return

    const inset = topInset()
    const room = v.innerHeight - inset
    let box = target.getBoundingClientRect()
    // a part that fits shows whole with room for the caption; a taller
    // one starts at its top
    const fits = box.height + 150 < room
    const want = box.top + v.scrollY - inset - (fits ? Math.max(16, (room - box.height - 130) / 2) : 16)
    v.scrollTo({top: Math.max(0, want), behavior: "instant"})
    box = target.getBoundingClientRect()

    lit.part = target
    paint()
    caption(step, box)
  }

  // ---- acting: the pointer, typing, the click -------------------------

  const pinned = el => el.closest(".chrome, .sidenav") !== null

  const cursor = () => {
    const d = doc()
    let el = d.querySelector(".tour-cursor")
    if (!el) {
      el = d.createElement("div")
      el.className = "tour-cursor"
      // an arrow pointer; its tip is the element's corner
      el.innerHTML =
        '<svg viewBox="0 0 20 24" aria-hidden="true">' +
        '<path d="M1 1 L1 19 L5.6 14.8 L9 22.2 L12.4 20.7 L9.1 13.5 L15.3 13.5 Z"/></svg>'
      el.style.left = `${view().innerWidth / 2}px`
      el.style.top = `${view().innerHeight / 2}px`
      d.body.appendChild(el)
    }
    return el
  }

  // the element acted on comes into view, gets its ring, and the caption
  // takes the foot or the top of the screen, whichever leaves it clear
  const focus = async (el) => {
    const v = view()
    let box = el.getBoundingClientRect()
    if (!pinned(el) && (box.top < topInset() + 8 || box.bottom > v.innerHeight - 8)) {
      v.scrollBy({top: box.top - topInset() - (v.innerHeight - topInset()) / 3, behavior: "smooth"})
      await sleep(450)
      box = el.getBoundingClientRect()
    }
    lit.active = el
    paint()
    const callout = doc().querySelector(".tour-callout")
    if (!callout) return
    const tall = callout.offsetHeight
    const spots = [v.innerHeight - tall - 12, topInset() + 12]
    const covered = top => Math.max(0, Math.min(box.bottom + 8, top + tall) - Math.max(box.top - 8, top))
    callout.style.top = `${spots.reduce((a, b) => covered(b) < covered(a) ? b : a)}px`
  }

  const pointAt = async (el, mine) => {
    await focus(el)
    if (mine !== run) return
    const box = el.getBoundingClientRect()
    const pointer = cursor()
    pointer.style.left = `${box.left + Math.min(box.width * 0.7, box.width - 10)}px`
    pointer.style.top = `${box.top + box.height * 0.6}px`
    await sleep(650)
  }

  const type = async ([selector, value], mine) => {
    const el = doc().querySelector(selector)
    if (!el) return
    await pointAt(el.type === "radio" ? el.closest("label") || el : el, mine)
    if (mine !== run) return
    if (el.type === "radio" || el.type === "checkbox") {
      el.checked = true
      el.dispatchEvent(new Event("change", {bubbles: true}))
      return
    }
    el.value = ""
    for (const char of value) {
      if (mine !== run) return
      el.value += char
      el.dispatchEvent(new Event("input", {bubbles: true}))
      await sleep(45)
    }
  }

  const press = async (selector, mine) => {
    const el = doc().querySelector(selector)
    if (!el) return
    await pointAt(el, mine)
    if (mine !== run) return
    const pointer = cursor()
    pointer.classList.add("down")
    el.classList.add("tour-pressed")
    await sleep(450)
    pointer.classList.remove("down")
    el.classList.remove("tour-pressed")
    await sleep(600)
  }

  // ---- steps --------------------------------------------------------

  const label = () => {
    const ended = !playing && index === steps.length - 1
    root.classList.toggle("tour-ended", ended)
    root.classList.toggle("tour-paused", !playing)
    const name = ended ? root.dataset.labelReplay : playing ? root.dataset.labelPause : root.dataset.labelPlay
    play.textContent = ended ? "↻" : playing ? "II" : "▶"
    play.setAttribute("aria-label", name)
    play.title = name
  }

  const show = async (n) => {
    index = n
    const mine = ++run
    const step = steps[index]
    slider.value = index
    $(".tour-count").textContent = `${index + 1} / ${steps.length}`
    chapters.forEach(button => {
      const at = Number(button.dataset.chapter)
      button.classList.toggle("on", at === step.chapter_index)
      button.classList.toggle("done", at < step.chapter_index)
    })
    // whose screen and which page; a switch to someone else is flagged
    const as = $(".tour-as")
    const was = as.dataset.who
    as.dataset.who = step.as || ""
    $(".tour-as-name").textContent = whoWhere(step)
    as.hidden = !step.as
    as.classList.remove("changed")
    if (step.as && was && was !== step.as) { void as.offsetWidth; as.classList.add("changed") }
    label()

    const started = Date.now()
    if (step.src) {
      card.hidden = true
      await loaded(step.src)
      if (mine !== run) return
      tame()
      for (const [selector, value] of step.set) {
        const el = doc().querySelector(selector)
        if (el) { el.value = value; el.dispatchEvent(new Event("input", {bubbles: true})) }
      }
      spotlight(step)
      await sleep(900)
      for (const field of step.fill) {
        if (mine !== run || !playing) return
        await type(field, mine)
        await sleep(350)
      }
      if (step.click && playing && mine === run) await press(step.click, mine)
    } else {
      card.hidden = false
      card.classList.toggle("first", index === 0)
      card.classList.toggle("last", step.finale)
      $(".tour-card-chapter").textContent = step.chapter
      $(".tour-card-text").textContent = step.text
    }

    if (mine !== run || !playing) return
    await sleep(Math.max(1200, step.hold - (Date.now() - started)))
    if (mine !== run || !playing) return
    if (index < steps.length - 1) show(index + 1)
    else { playing = false; label() }
  }

  slider.addEventListener("input", () => show(Number(slider.value)))
  chapters.forEach(button => button.addEventListener("click", () => {
    const first = steps.findIndex(step => step.chapter_index === Number(button.dataset.chapter))
    if (first >= 0) show(first)
  }))
  play.addEventListener("click", () => {
    if (!playing && index === steps.length - 1) { playing = true; show(0); return }
    playing = !playing
    if (playing) show(index)
    else { run++; label() }
  })
  document.addEventListener("keydown", e => {
    if (e.target.closest && e.target.closest("input, button, a")) return
    if (e.key === " ") { e.preventDefault(); play.click() }
    if (e.key === "ArrowRight" && index < steps.length - 1) show(index + 1)
    if (e.key === "ArrowLeft" && index > 0) show(index - 1)
  })

  root.classList.add("tour-on")
  show(0)
}
