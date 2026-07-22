// The admin bundle, loaded only by the admin root layout. Kept separate from
// the public app.js so the CodeMirror editor never ships to public visitors.
// Sets up its own LiveSocket with the admin hooks.
import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/newton"
import topbar from "../vendor/topbar"
import {AdminTheme} from "./hooks/admin_theme"
import {AdminNav} from "./hooks/admin_nav"
import {UnsavedGuard} from "./hooks/unsaved_guard"
import {FlashDismiss} from "./hooks/flash_dismiss"
import {MarkdownEditor} from "./hooks/markdown_editor"
import {ImageDimensions} from "./hooks/image_dimensions"
import {SortableGrid} from "./hooks/sortable_grid"
import {CopyText} from "./hooks/copy_text"
import {PasskeyRegister} from "./hooks/passkey_register"
import {PasskeyAuthenticate} from "./hooks/passkey_authenticate"
import {PasskeySudo} from "./hooks/passkey_sudo"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, AdminTheme, AdminNav, UnsavedGuard, FlashDismiss, MarkdownEditor, ImageDimensions, SortableGrid, CopyText, PasskeyRegister, PasskeyAuthenticate, PasskeySudo},
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
