// The full-screen photo viewer as a bundle of its own
// (/assets/js/photo-viewer.js): only pages with images to open load
// it. ui.js loads it when the page names it in
// <meta name="photo-viewer-src">.
import {watchPhotos} from "./photo_viewer"

if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", watchPhotos)
else watchPhotos()
