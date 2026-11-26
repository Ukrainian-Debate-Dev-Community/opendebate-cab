// The guided tour's player (/tour). Each step shows a demo page in
// the frame (or a title card), spotlights one part of it with the
// caption beside it, types into its fields, moves a cursor to what gets
// clicked, holds, and moves on; the next step shows what the click led
// to. The frame's links and forms never act: it is watched, not used,
// but it scrolls. Without this script the page reads as the list of
// steps.
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

  // ---- the frame ------------------------------------------------------

  const doc = () => frame.contentDocument
  const view = () => frame.contentWindow

  const loaded = src => new Promise(resolve => {
    if (frame.getAttribute("src") === src && doc() && doc().readyState === "complete") return resolve()
    frame.addEventListener("load", () => resolve(), {once: true})
    frame.setAttribute("src", src)
  })

  // watched, not used: no link, form or drag acts; scrolling still works
  const tame = () => {
    const d = doc()
    if (!d || d.documentElement.classList.contains("in-tour")) return
    d.documentElement.classList.add("in-tour")
    const stop = e => { if (e.isTrusted) { e.preventDefault(); e.stopPropagation() } }
    ;["click", "submit", "dragstart", "mousedown", "keydown"].forEach(type =>
      d.addEventListener(type, stop, true))
  }

  const clear = () => {
    const d = doc()
    if (d) d.querySelectorAll(".tour-hole, .tour-callout, .tour-cursor").forEach(el => el.remove())
  }

  // the sticky bars at the top of the page (the chrome, the phone's nav)
  const topInset = () => {
    const d = doc()
    let inset = 0
    d.querySelectorAll(".chrome, .sidenav .bar").forEach(el => {
      const box = el.getBoundingClientRect()
      const style = view().getComputedStyle(el)
      if ((style.position === "sticky" || style.position === "fixed") && box.top < 5 && box.height < 160)
        inset = Math.max(inset, box.bottom)
    })
    return inset
  }

  // the spotlight: a box over the whole target, on the frame's own page;
  // it stays there for the step - typing and clicks happen inside it
  const spotlight = (step) => {
    const d = doc()
    const v = view()
    clear()
    const target = step.target && d.querySelector(step.target)
    if (!target) return null

    const inset = topInset()
    const room = v.innerHeight - inset
    let box = target.getBoundingClientRect()
    // a part that fits shows whole with room for the caption; a taller
    // one starts at its top
    const fits = box.height + 160 < room
    const want = box.top + v.scrollY - inset - (fits ? Math.max(16, (room - box.height - 140) / 2) : 16)
    v.scrollTo({top: Math.max(0, want), behavior: "instant"})
    box = target.getBoundingClientRect()

    const hole = d.createElement("div")
    hole.className = "tour-hole"
    Object.assign(hole.style, {
      top: `${box.top + v.scrollY - 6}px`,
      left: `${box.left + v.scrollX - 6}px`,
      width: `${box.width + 12}px`,
      height: `${box.height + 12}px`
    })
    d.body.appendChild(hole)

    // the caption floats in the frame's view: below the part, above
    // it, or at the foot of the screen for a tall one
    const callout = d.createElement("div")
    callout.className = "tour-callout"
    callout.setAttribute("role", "status")
    const who = d.createElement("p")
    who.className = "tour-callout-chapter"
    who.textContent = step.as || step.chapter
    const text = d.createElement("p")
    text.textContent = step.text
    callout.append(who, text)
    d.body.appendChild(callout)

    const width = Math.min(400, v.innerWidth - 24)
    callout.style.width = `${width}px`
    callout.style.left = `${Math.min(Math.max(12, box.left + 6), v.innerWidth - width - 12)}px`
    const tall = callout.offsetHeight
    let top
    if (box.bottom + 18 + tall < v.innerHeight - 8) top = box.bottom + 18
    else if (box.top - tall - 18 > inset + 8) top = box.top - tall - 18
    else top = v.innerHeight - tall - 12
    callout.style.top = `${top}px`
    return target
  }

  // ---- the cursor, typing and the click -------------------------------

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
      el.style.left = `${view().scrollX + view().innerWidth / 2}px`
      el.style.top = `${view().scrollY + view().innerHeight / 2}px`
      d.body.appendChild(el)
    }
    return el
  }

  // the sticky bars stay on screen: nothing to scroll to
  const pinned = el => el.closest(".chrome, .sidenav") !== null

  // the field or button acted on comes into view (the spotlight stays on
  // its part); the caption steps aside when it covers it
  const reveal = async (el) => {
    const v = view()
    let box = el.getBoundingClientRect()
    if (!pinned(el) && (box.top < topInset() + 8 || box.bottom > v.innerHeight - 8)) {
      v.scrollBy({top: box.top - topInset() - (v.innerHeight - topInset()) / 3, behavior: "smooth"})
      await sleep(450)
      box = el.getBoundingClientRect()
    }
    const callout = doc().querySelector(".tour-callout")
    if (!callout) return
    // the screen's foot or top, whichever leaves the element clear (the
    // foot when both do; else the one that covers less of it)
    const tall = callout.offsetHeight
    const spots = [v.innerHeight - tall - 12, topInset() + 12]
    const covered = top => Math.max(0, Math.min(box.bottom, top + tall) - Math.max(box.top, top))
    const best = spots.reduce((a, b) => covered(b) < covered(a) ? b : a)
    callout.style.top = `${best}px`
  }

  const pointAt = async (el, mine) => {
    await reveal(el)
    if (mine !== run) return
    const now = el.getBoundingClientRect()
    const pointer = cursor()
    pointer.style.left = `${now.left + view().scrollX + Math.min(now.width * 0.75, now.width - 10)}px`
    pointer.style.top = `${now.top + view().scrollY + now.height / 2}px`
    await sleep(650)
  }

  const type = async ([selector, value], mine) => {
    const el = doc().querySelector(selector)
    if (!el) return
    await pointAt(el, mine)
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
    await sleep(500)
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
    // whose screen it is; a switch to someone else is flagged
    const as = $(".tour-as")
    const was = $(".tour-as-name").textContent
    $(".tour-as-name").textContent = step.as || ""
    as.hidden = !step.as
    as.classList.remove("changed")
    if (step.as && was && was !== step.as) { void as.offsetWidth; as.classList.add("changed") }
    chapters.forEach(button => {
      const at = Number(button.dataset.chapter)
      button.classList.toggle("on", at === step.chapter_index)
      button.classList.toggle("done", at < step.chapter_index)
    })
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
