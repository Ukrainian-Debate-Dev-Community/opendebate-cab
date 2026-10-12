// cab's API reference: Scalar, served by cab itself. Nothing is loaded
// from other companies: no default fonts, no telemetry, no AI agent or
// MCP, no request proxy (try-it calls go straight to cab), no button
// out to Scalar's hosted client, and the Powered by credit links to
// scalar.com without tracking tags. The
// engine is internal, so its description has no try-it client.
(function () {
  var stored = null
  try { stored = localStorage.getItem("cab-theme") } catch (_e) {}
  var dark = stored === "dark" ||
    (stored !== "light" && window.matchMedia("(prefers-color-scheme: dark)").matches)
  document.body.classList.add(dark ? "dark-mode" : "light-mode")

  var el = document.getElementById("api-docs")
  var common = {
    theme: "none",
    withDefaultFonts: false,
    telemetry: false,
    proxyUrl: "",
    agent: { disabled: true },
    mcp: { disabled: true },
    darkMode: dark,
    showDeveloperTools: "never",
    // no button out to Scalar's hosted client (client.scalar.com):
    // try-it stays on this page
    hideClientButton: true
  }
  // one document per page: cab's at /api/cab/docs, the engine's at
  // /api/engine/docs; the engine is internal, so no try-it there
  var config = Object.assign({}, common, { url: el.dataset.spec })
  if (el.dataset.doc === "engine") {
    // served as is, straight from the engine, under /api/engine/v2
    config.servers = [{ url: "/api/engine/v2" }]
    config.hideTestRequestButton = true
  }
  Scalar.createApiReference("#api-docs", config)

  // keep the "Powered by Scalar" credit, without its tracking tags
  var clean = function () {
    document.querySelectorAll('a[href*="scalar.com"]').forEach(function (a) {
      if (a.getAttribute("href") !== "https://scalar.com/") a.setAttribute("href", "https://scalar.com/")
      a.setAttribute("target", "_blank")
      a.setAttribute("rel", "noopener noreferrer")
    })
  }
  new MutationObserver(clean).observe(document.body, { childList: true, subtree: true })
  clean()
})()
