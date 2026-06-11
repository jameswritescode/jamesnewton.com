// The admin bundle, loaded only by the admin root layout. Kept separate from
// the public app.js so the heavy Milkdown editor (added in this plan) never
// ships to public visitors. Sets up its own LiveSocket with the admin hooks.
import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/newton"
import topbar from "../vendor/topbar"
import {AdminTheme} from "./hooks/admin_theme"
import {MilkdownEditor} from "./hooks/milkdown_editor"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, AdminTheme, MilkdownEditor},
})

topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

liveSocket.connect()
window.liveSocket = liveSocket
