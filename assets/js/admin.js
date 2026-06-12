// The admin bundle, loaded only by the admin root layout. Kept separate from
// the public app.js so the CodeMirror editor never ships to public visitors.
// Sets up its own LiveSocket with the admin hooks.
import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/newton"
import topbar from "../vendor/topbar"
import {AdminTheme} from "./hooks/admin_theme"
import {MarkdownEditor} from "./hooks/markdown_editor"
import {ImageDimensions} from "./hooks/image_dimensions"
import {SortableGrid} from "./hooks/sortable_grid"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, AdminTheme, MarkdownEditor, ImageDimensions, SortableGrid},
})

// Match the loading bar to the admin accent, re-reading it when the theme flips.
const applyTopbarTheme = () => {
  const accent = getComputedStyle(document.documentElement).getPropertyValue("--admin-accent").trim()
  topbar.config({barColors: {0: accent || "#b54a2b"}, shadowColor: "rgba(0, 0, 0, .15)"})
}
applyTopbarTheme()
new MutationObserver(applyTopbarTheme).observe(document.documentElement, {
  attributeFilter: ["data-admin-theme"],
})

window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

liveSocket.connect()
window.liveSocket = liveSocket
