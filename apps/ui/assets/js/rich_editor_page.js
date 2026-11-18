// The rich text editor as a bundle of its own (/assets/js/rich-editor.js):
// TipTap is large, so only pages with a :rich form block load it. ui.js
// loads it when the page names it in <meta name="rich-editor-src">.
import {watchRichEditors} from "./rich_editor"

if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", watchRichEditors)
else watchRichEditors()
