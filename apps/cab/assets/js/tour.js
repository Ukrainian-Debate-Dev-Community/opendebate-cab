// The guided tour's player (/tour/:key): each step shows a demo page in
// the frame (or a title card), spotlights one part of it and holds for
// its seconds; the slider and the button move and pause it. Without
// this script the page reads as the list of steps.
export const mountTour = () => {
  const root = document.getElementById("tour")
  if (!root) return

  const steps = JSON.parse(root.dataset.steps)
  const frame = root.querySelector(".tour-frame")
  const card = root.querySelector(".tour-card")
  const slider = root.querySelector(".tour-slider")
  const play = root.querySelector(".tour-play")
  const count = root.querySelector(".tour-count")
  const chapter = root.querySelector(".tour-chapter b")
  const text = root.querySelector(".tour-text")

  let index = 0
  let playing = true
  let timer = null

  // the spotlight: a box drawn over the target on the frame's own page
  // (the target's ancestors may clip anything drawn on the target)
  const spotlight = () => {
    const doc = frame.contentDocument
    if (!doc || !doc.body) return
    const view = doc.defaultView
    doc.querySelectorAll(".tour-hole").forEach(el => el.remove())
    const target = steps[index].target && doc.querySelector(steps[index].target)
    if (!target) { view.scrollTo({top: 0, behavior: "smooth"}); return }

    const box = target.getBoundingClientRect()
    const hole = doc.createElement("div")
    hole.className = "tour-hole"
    Object.assign(hole.style, {
      top: `${box.top + view.scrollY - 6}px`,
      left: `${box.left + view.scrollX - 6}px`,
      width: `${box.width + 12}px`,
      height: `${box.height + 12}px`
    })
    doc.body.appendChild(hole)
    target.scrollIntoView({block: box.height > view.innerHeight ? "start" : "center", behavior: "smooth"})
  }

  const label = () => {
    const ended = !playing && index === steps.length - 1
    root.classList.toggle("tour-ended", ended)
    const name = ended ? root.dataset.labelReplay : playing ? root.dataset.labelPause : root.dataset.labelPlay
    play.textContent = ended ? "↻" : playing ? "II" : "▶"
    play.setAttribute("aria-label", name)
    play.title = name
  }

  const schedule = () => {
    clearTimeout(timer)
    if (playing) timer = setTimeout(next, steps[index].seconds * 1000)
    label()
  }

  const show = (n) => {
    index = n
    const step = steps[index]
    slider.value = index
    count.textContent = `${index + 1} / ${steps.length}`
    chapter.textContent = step.chapter
    text.textContent = step.text

    if (step.src) {
      card.hidden = true
      if (frame.getAttribute("src") === step.src) spotlight()
      else frame.setAttribute("src", step.src)
    } else {
      card.hidden = false
      card.querySelector(".tour-card-chapter").textContent = step.chapter
      card.querySelector(".tour-card-text").textContent = step.text
    }
    schedule()
  }

  const next = () => {
    if (index < steps.length - 1) show(index + 1)
    else { playing = false; schedule() }
  }

  frame.addEventListener("load", spotlight)
  slider.addEventListener("input", () => show(Number(slider.value)))
  play.addEventListener("click", () => {
    if (!playing && index === steps.length - 1) { playing = true; show(0); return }
    playing = !playing
    schedule()
  })
  document.addEventListener("keydown", e => {
    if (e.key === " ") { e.preventDefault(); play.click() }
    if (e.key === "ArrowRight" && index < steps.length - 1) show(index + 1)
    if (e.key === "ArrowLeft" && index > 0) show(index - 1)
  })

  root.classList.add("tour-on")
  show(0)
}
