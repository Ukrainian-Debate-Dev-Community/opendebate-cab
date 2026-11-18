// The rich text editor of the :rich form block (Ui.Form.rich/1): TipTap
// (vendor/tiptap.min.js, built by tools/vendor/tiptap.sh) mounted on
// each [data-rich] block. The block's textarea keeps the HTML and goes
// out with the form; it is hidden once the editor runs and filled on
// every change (an input event too, for LiveView's phx-change). The
// toolbar, the link and image-description fields and the messages are
// the block's own markup, in the page's language. Images go to the
// block's data-upload address; the server answers {url} or {error}.
// The server sanitises whatever arrives: this only helps people write.
import {Editor, StarterKit, Image, Placeholder} from "../vendor/tiptap.min.js"

// links the editor makes: http(s), mailto or a path on this site
const ALLOWED_LINK = /^(https?:\/\/|mailto:|\/(?![\/\\]))/i
const IMAGE_TYPES = ["image/jpeg", "image/png", "image/webp"]

// what a link field's text becomes: a bare host gets https://
function linkHref(text) {
  const value = text.trim()
  if (!value) return ""
  if (ALLOWED_LINK.test(value)) return value
  if (/^[a-z][a-z0-9+.-]*:/i.test(value)) return null
  if (/^[^\s@\/]+@[^\s@\/]+\.[^\s@\/]+$/.test(value)) return "mailto:" + value
  return "https://" + value
}

function csrfToken(el) {
  const field = el.closest("form")?.querySelector('input[name="_csrf_token"]')
  return field?.value || document.querySelector('meta[name="csrf-token"]')?.content || ""
}

export function mountRichEditor(root) {
  if (root.dataset.richOn) return
  root.dataset.richOn = "true"

  const source = root.querySelector("textarea.rich-source")
  const bar = root.querySelector(".rich-bar")
  const status = root.querySelector(".rich-status")
  const linkPop = root.querySelector('[data-pop="link"]')
  const imagePop = root.querySelector('[data-pop="image"]')
  const linkField = root.querySelector("[data-link]")
  const altField = root.querySelector("[data-alt]")
  const fileField = root.querySelector("[data-file]")
  const upload = root.dataset.upload

  const area = document.createElement("div")
  area.className = "rich-area"
  source.before(area)

  // set once TipTap is up; its first transactions come before that
  let editor = null

  const sync = () => {
    if (!editor) return
    // without the empty paragraph TipTap keeps at the end for the cursor
    const html = editor.isEmpty ? "" : editor.getHTML().replace(/(<p><\/p>)+$/, "")
    if (source.value === html) return
    source.value = html
    source.dispatchEvent(new Event("input", {bubbles: true}))
  }

  const say = (text, bad) => {
    status.textContent = text || ""
    status.classList.toggle("bad", !!bad)
  }

  // ---------------------------------------------------------------
  // images: uploaded, then put in at the cursor (or where dropped)
  // ---------------------------------------------------------------

  const uploadImage = (file, pos) => {
    if (!upload || !IMAGE_TYPES.includes(file.type)) return false
    const body = new FormData()
    body.append("image", file)
    say(root.dataset.msgUploading)
    fetch(upload, {method: "POST", body, headers: {"x-csrf-token": csrfToken(root)}, credentials: "same-origin"})
      .then(r => r.json().catch(() => ({})).then(data => ({ok: r.ok, data})))
      .then(({ok, data}) => {
        if (!ok || !data.url) throw new Error(data.error || "")
        say("")
        const chain = editor.chain().focus()
        if (typeof pos === "number") chain.insertContentAt(pos, {type: "image", attrs: {src: data.url, alt: ""}})
        else chain.setImage({src: data.url, alt: ""})
        chain.run()
        openImage()
      })
      .catch(e => say(e.message || root.dataset.msgUploadFailed, true))
    return true
  }

  const imageFiles = list => [...(list || [])].filter(f => IMAGE_TYPES.includes(f.type))

  editor = new Editor({
    element: area,
    content: source.value,
    extensions: [
      StarterKit.configure({
        heading: {levels: [2, 3]},
        code: false,
        codeBlock: false,
        underline: false,
        link: {
          openOnClick: false,
          autolink: false,
          defaultProtocol: "https",
          HTMLAttributes: {rel: null, target: null, class: null},
          isAllowedUri: url => ALLOWED_LINK.test(url)
        }
      }),
      Image.configure({inline: false, allowBase64: false}),
      Placeholder.configure({placeholder: root.dataset.placeholder || ""})
    ],
    editorProps: {
      attributes: {class: "rich-text", role: "textbox", "aria-multiline": "true",
                   "aria-label": source.getAttribute("aria-label") || ""},
      handlePaste: (_view, event) => {
        const files = imageFiles(event.clipboardData?.files)
        if (!files.length) return false
        files.forEach(f => uploadImage(f))
        return true
      },
      handleDrop: (view, event) => {
        const files = imageFiles(event.dataTransfer?.files)
        if (!files.length) return false
        event.preventDefault()
        const at = view.posAtCoords({left: event.clientX, top: event.clientY})
        files.forEach(f => uploadImage(f, at?.pos))
        return true
      }
    },
    onUpdate: () => sync(),
    onTransaction: () => refresh()
  })

  // ---------------------------------------------------------------
  // the toolbar
  // ---------------------------------------------------------------

  const commands = {
    h2: c => c.toggleHeading({level: 2}),
    h3: c => c.toggleHeading({level: 3}),
    bold: c => c.toggleBold(),
    italic: c => c.toggleItalic(),
    bullet: c => c.toggleBulletList(),
    ordered: c => c.toggleOrderedList(),
    quote: c => c.toggleBlockquote(),
    rule: c => c.setHorizontalRule(),
    undo: c => c.undo(),
    redo: c => c.redo()
  }

  const active = {
    h2: () => editor.isActive("heading", {level: 2}),
    h3: () => editor.isActive("heading", {level: 3}),
    bold: () => editor.isActive("bold"),
    italic: () => editor.isActive("italic"),
    bullet: () => editor.isActive("bulletList"),
    ordered: () => editor.isActive("orderedList"),
    quote: () => editor.isActive("blockquote"),
    link: () => editor.isActive("link"),
    image: () => editor.isActive("image")
  }

  function refresh() {
    if (!editor) return
    bar.querySelectorAll("[data-cmd]").forEach(btn => {
      const cmd = btn.dataset.cmd
      if (active[cmd]) btn.setAttribute("aria-pressed", active[cmd]() ? "true" : "false")
      if (cmd === "undo" || cmd === "redo") btn.disabled = !editor.can()[cmd]()
    })
    if (imagePop && !imagePop.hidden && !editor.isActive("image")) imagePop.hidden = true
  }

  const closePops = () => {
    linkPop.hidden = true
    if (imagePop) imagePop.hidden = true
  }

  // back to the text once a small field is done with; past an image
  // rather than on it, so what is typed next does not replace it
  const backToText = () => {
    closePops()
    editor.view.focus()
    if (editor.isActive("image")) {
      const after = editor.state.selection.to
      if (editor.state.doc.resolve(after).nodeAfter?.isTextblock) editor.commands.setTextSelection(after + 1)
    }
  }

  const openLink = () => {
    closePops()
    linkField.value = editor.getAttributes("link").href || ""
    linkPop.hidden = false
    linkField.focus()
    linkField.select()
  }

  const applyLink = () => {
    const href = linkHref(linkField.value)
    if (href === null) { linkField.focus(); return }
    backToText()
    const chain = editor.chain().focus().extendMarkRange("link")
    if (!href) chain.unsetLink()
    else if (editor.state.selection.empty && !editor.isActive("link"))
      chain.insertContent({type: "text", text: href, marks: [{type: "link", attrs: {href}}]})
    else chain.setLink({href})
    chain.run()
  }

  function openImage() {
    if (!imagePop) return
    linkPop.hidden = true
    altField.value = editor.getAttributes("image").alt || ""
    imagePop.hidden = false
    altField.focus()
  }

  const applyAlt = () => {
    editor.chain().focus().updateAttributes("image", {alt: altField.value.trim()}).run()
    backToText()
  }

  bar.addEventListener("mousedown", e => { if (e.target.closest("[data-cmd]")) e.preventDefault() })
  bar.addEventListener("click", e => {
    const btn = e.target.closest("[data-cmd]")
    if (!btn) return
    const cmd = btn.dataset.cmd
    if (cmd === "link") return openLink()
    if (cmd === "image") return editor.isActive("image") ? openImage() : fileField?.click()
    closePops()
    commands[cmd](editor.chain().focus()).run()
  })

  root.addEventListener("click", e => {
    const act = e.target.closest("[data-act]")?.dataset.act
    if (act === "link-apply") applyLink()
    else if (act === "link-remove") { linkField.value = ""; applyLink() }
    else if (act === "alt-apply") applyAlt()
    else if (act === "close") backToText()
  })

  // Enter in the small fields applies them (never submits the form);
  // Escape closes them
  root.addEventListener("keydown", e => {
    if (!e.target.matches("[data-link], [data-alt]")) return
    if (e.key === "Enter") { e.preventDefault(); e.target.matches("[data-link]") ? applyLink() : applyAlt() }
    else if (e.key === "Escape") { e.preventDefault(); backToText() }
  })

  // a click on an image in the text opens its description
  area.addEventListener("click", e => { if (e.target.closest("img")) setTimeout(openImage, 0) })

  fileField?.addEventListener("change", () => {
    const [file] = fileField.files
    if (file && !uploadImage(file)) say(root.dataset.msgUploadFailed, true)
    fileField.value = ""
  })

  source.hidden = true
  bar.hidden = false
  root.classList.add("on")
  refresh()
  return editor
}

// every [data-rich] block on the page, and those added later (LiveView)
export function mountRichEditors(scope = document) {
  scope.querySelectorAll("[data-rich]").forEach(mountRichEditor)
}

export function watchRichEditors() {
  mountRichEditors()
  new MutationObserver(() => {
    if (document.querySelector("[data-rich]:not([data-rich-on])")) mountRichEditors()
  }).observe(document.documentElement, {subtree: true, childList: true})
}
