// The full-screen photo viewer: PhotoSwipe (vendor/photoswipe.min.js,
// built by tools/vendor/photoswipe.sh) over the images of a
// [data-photos] block. A click, a tap, or Enter / Space on an image
// opens it; the images of one <figure> (a gallery) open together, in
// order, from the one chosen; any other image opens alone. Sizes come
// from the images as the page loaded them, the description is the
// caption. Swipes, keys and zoom are PhotoSwipe's. The viewer's words
// come from <meta name="photo-viewer-src"> (Ui.Components.photo_viewer/1),
// in the page's language.
import {PhotoSwipe} from "../vendor/photoswipe.min.js"

const BLOCK = "[data-photos]"
const words = () => document.querySelector('meta[name="photo-viewer-src"]')?.dataset || {}

// the images that open together with this one
const groupOf = img => {
  const figure = img.closest("figure")
  return figure && figure.closest(BLOCK) ? [...figure.querySelectorAll("img")] : [img]
}

// an image's size as loaded; one not loaded yet is fetched first
const sizeOf = img => {
  if (img.complete && img.naturalWidth) return Promise.resolve([img.naturalWidth, img.naturalHeight])
  const probe = new window.Image()
  probe.src = img.currentSrc || img.src
  return probe.decode().then(() => [probe.naturalWidth, probe.naturalHeight], () => [1600, 1200])
}

let open = null

async function show(img) {
  if (open) return
  const imgs = groupOf(img)
  const sizes = await Promise.all(imgs.map(sizeOf))
  const w = words()
  const still = window.matchMedia("(prefers-reduced-motion: reduce)").matches
  const dataSource = imgs.map((el, i) => ({
    src: el.currentSrc || el.src,
    msrc: el.currentSrc || el.src,
    width: sizes[i][0],
    height: sizes[i][1],
    alt: el.alt || "",
    element: el,
    thumbCropped: getComputedStyle(el).objectFit === "cover"
  }))

  open = new PhotoSwipe({
    dataSource,
    index: Math.max(0, imgs.indexOf(img)),
    showHideAnimationType: still ? "none" : "zoom",
    bgOpacity: 1,
    closeTitle: w.close,
    zoomTitle: w.zoom,
    arrowPrevTitle: w.prev,
    arrowNextTitle: w.next,
    errorMsg: w.error,
    indexIndicatorSep: w.of ? ` ${w.of} ` : " / "
  })

  // the description under the image
  open.on("uiRegister", () => {
    open.ui.registerElement({
      name: "caption",
      order: 9,
      isButton: false,
      appendTo: "root",
      onInit: (el, pswp) => {
        el.classList.add("pswp__hide-on-close")
        el.setAttribute("aria-live", "polite")
        const set = () => { el.textContent = pswp.currSlide?.data.alt || "" }
        pswp.on("change", set)
        set()
      }
    })
  })
  open.on("destroy", () => { open = null })
  open.init()
}

// what an image says to a screen reader once it opens the viewer
const mark = img => {
  if (img.dataset.photo || img.closest("a")) return
  img.dataset.photo = "on"
  img.tabIndex = 0
  img.setAttribute("role", "button")
  const label = words().open || ""
  img.setAttribute("aria-label", img.alt ? `${img.alt} (${label})` : label)
}

const markAll = () => {
  document.querySelectorAll(BLOCK).forEach(block => {
    block.classList.add("photos-on")
    block.querySelectorAll("img").forEach(mark)
  })
}

const target = e => {
  const img = e.target.closest?.(`${BLOCK} img[data-photo]`)
  return img && !img.closest("a") ? img : null
}

export function watchPhotos() {
  markAll()
  document.addEventListener("click", e => {
    const img = target(e)
    if (!img || e.metaKey || e.ctrlKey) return
    e.preventDefault()
    show(img)
  })
  document.addEventListener("keydown", e => {
    const img = target(e)
    if (!img || (e.key !== "Enter" && e.key !== " ")) return
    e.preventDefault()
    show(img)
  })
  new MutationObserver(() => {
    if (document.querySelector(`${BLOCK} img:not([data-photo])`)) markAll()
  }).observe(document.documentElement, {subtree: true, childList: true})
}
