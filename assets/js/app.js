// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/newton"
import topbar from "../vendor/topbar"
import Swup from "../vendor/swup"
import {RippleCanvas} from "./hooks/ripple_canvas"
import {initPhotos, teardownPhotos} from "./photos"
import {initPixelTransition} from "./pixel_transition"
import {initGibsonIntro} from "./gibson_intro"
import {focusAfterNavigation} from "./navigation"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, RippleCanvas},
})

// Swup handles same-document page navigation: it swaps only the #main content,
// so the fixed ripple canvas (outside #main) persists across pages and the
// content cross-fades smoothly. Works in Chrome, Safari, and Firefox.
const scrollToHash = () => {
  if (!location.hash) return
  const el = document.querySelector(location.hash)
  if (el) el.scrollIntoView()
}

// Leave hash-only links (e.g. footnote refs) to the browser: Swup intercepts
// them and updates the URL via history.replaceState, which does NOT update the
// :target pseudo-class, so the footnote highlight never fires on click. Native
// fragment navigation updates :target and scrolls. Cross-page links with a hash
// (e.g. /posts/x#y) still start with "/", so Swup keeps handling those.
const swup = new Swup({
  containers: ["#main"],
  linkSelector: 'a[href]:not([href^="#"])',
})
// Page-specific JS (photo masonry + lightbox) re-runs on every swap.
swup.hooks.on("visit:start", teardownPhotos)
swup.hooks.on("content:replace", () => {
  initPhotos()
  // Move focus into the new content and announce the page change to AT.
  // (Focusing the target also scrolls it into view, covering hash links.)
  focusAfterNavigation()
})
// Initial page load (Swup doesn't fire content:replace for the first page).
initPhotos()
// The intro must init BEFORE the pixel transition: it registers the mosaic-in
// gate/hook that the transition's mosaic consumes as soon as it starts.
initGibsonIntro()
initPixelTransition()
scrollToHash()

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

