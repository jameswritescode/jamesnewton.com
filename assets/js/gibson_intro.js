// Owns the /links cinematic. Decides the mode (full flight on first visit,
// straight to the parked menu tower on repeat visits, plain DOM page as the
// fallback), injects the lazy three.js bundle behind the Phase B mosaic
// cover, and wires the parked ending's hotspot overlay. Effectful
// (canvas/three.js); not unit-tested — the mode decision is (gibson_gate).
import {cinematicMode, markGibsonSeen} from "./gibson_gate"
import {setMosaicInHook, setMosaicInGate, requestMosaicIn} from "./pixel_transition"

const BUNDLE = "/assets/js/gibson.js"
const FADE_MS = 400

function injectBundle(doc, win) {
  return new Promise((resolve, reject) => {
    if (win.__gibsonRun) return resolve()
    const s = doc.createElement("script")
    // Dynamically appended scripts load async by default — no `defer` needed.
    // ALWAYS cache-bust: dynamically-injected scripts dodge hard-reload cache
    // invalidation, and a stale scene bundle is far worse than re-downloading
    // one file for a once-per-visitor cinematic.
    s.src = `${BUNDLE}?v=${Date.now()}`
    s.onload = () => resolve()
    s.onerror = () => reject(new Error("gibson bundle failed to load"))
    doc.head.appendChild(s)
  })
}

// Remove the DOM page from sight AND from interaction (clicks, tab order,
// a11y tree) while the Gibson owns the viewport. It stays in the document as
// the no-JS/SEO fallback; visibility (not display) so that if the canvas ever
// blanks — GPU context reclaimed in a background tab — the visitor sees
// black, never the covered page bleeding through as a phantom second UI.
function hideMain(doc) {
  const main = doc.getElementById("main")
  if (!main) return
  main.setAttribute("inert", "")
  main.setAttribute("aria-hidden", "true")
  main.style.visibility = "hidden"
}

export function initGibsonIntro({doc = document, win = window, storage = win.localStorage} = {}) {
  if (win.location.pathname !== "/links") return
  const mode = cinematicMode(win, storage, doc)
  // The root layout's pre-paint blackout (anti-FOUC inline script) becomes
  // the Gibson's backdrop for the WHOLE session: buffer resizes (window
  // resize, pixel-ratio changes) clear the canvas, and whatever the
  // compositor catches in that gap must be black — never the covered page.
  // It also keeps the header/skip-link out of the tab order under the
  // canvas. Released only when the DOM page should return.
  const releaseHold = () => {
    win.clearTimeout(win.__gibsonHoldFailsafe)
    doc.documentElement.classList.remove("gibson-takeover")
  }
  if (mode === "none") return releaseHold()
  // Taking over: the inline script's 4s failsafe must not yank the backdrop.
  win.clearTimeout(win.__gibsonHoldFailsafe)
  // The Gibson is running: /links gets its mosaic-in. The fallback page never
  // reaches this line, so it gets no transition — and still mode never wants
  // one (real reduced-motion suppresses it anyway; skipping here keeps the
  // ?still preview faithful).
  if (mode !== "still") requestMosaicIn()
  // The DOM page leaves NOW, not at arrival: visible, it flashes until the
  // cover/scene paints (still mode has no mosaic to hide behind); interactive,
  // its links sit invisibly under the canvas taking clicks and tab focus for
  // the whole flight. The bail path (finish) restores it.
  hideMain(doc)

  const canvas = doc.createElement("canvas")
  canvas.className = "gibson-canvas"
  canvas.setAttribute("aria-hidden", "true")
  doc.body.appendChild(canvas)

  // Skip affordance only makes sense when there is a flight to skip.
  let skipBtn = null
  if (mode === "flight") {
    skipBtn = doc.createElement("button")
    skipBtn.type = "button"
    skipBtn.className = "gibson-skip"
    skipBtn.textContent = "SKIP ▸"
    skipBtn.setAttribute("aria-label", "Skip intro")
    doc.body.appendChild(skipBtn)
  }

  let mosaicDone = false
  let control = null
  let started = false
  let finished = false
  let hotspots = null

  // Debug mode (dev-only, ` to toggle): shows the fps HUD and arms the
  // pause/scrub keys. Toggling it OFF resumes playback from wherever the
  // flight currently is.
  let debugMode = false
  let debugPaused = false
  const debugHud = doc.createElement("div")
  debugHud.setAttribute("aria-hidden", "true")
  debugHud.style.cssText =
    "position:fixed;right:20px;top:20px;z-index:9001;pointer-events:none;display:none;text-align:right;" +
    "font:11px monospace;letter-spacing:.1em;color:#8ff6ff;opacity:.75"
  doc.body.appendChild(debugHud)
  const hudTimer = win.setInterval(() => {
    if (!debugMode) return
    const f = win.__gibsonFps
    debugHud.textContent =
      (f ? `${f.fps}fps · worst ${f.worst}ms` : "fps —") + (debugPaused ? " · PAUSED" : "")
  }, 250)

  function toggleDebug() {
    debugMode = !debugMode
    debugHud.style.display = debugMode ? "block" : "none"
    // Leaving debug mode resumes wherever things are.
    if (!debugMode && debugPaused && control?.togglePause) {
      debugPaused = control.togglePause()
    }
  }

  function cleanupSkipUi() {
    if (skipBtn) skipBtn.remove()
    debugHud.remove()
    win.clearInterval(hudTimer)
    win.removeEventListener("keydown", onKey)
  }

  // BAIL path: abandon the 3D takeover and reveal the DOM page (WebGL too
  // slow, bundle failure, or skip before the flight began).
  function finish() {
    if (finished) return
    finished = true
    releaseHold()
    cleanupSkipUi()
    if (hotspots) hotspots.remove()
    const main = doc.getElementById("main")
    if (main) {
      main.removeAttribute("inert")
      main.removeAttribute("aria-hidden")
      main.style.visibility = ""
    }
    markGibsonSeen(storage)
    canvas.style.transition = `opacity ${FADE_MS}ms ease`
    canvas.style.opacity = "0"
    win.setTimeout(() => canvas.remove(), FADE_MS)
  }

  // PARK path: the flight has landed on the menu tower. The scene stays live;
  // an invisible hotspot overlay makes the tower's menu rows real links
  // (hover/focus highlights the row in-scene). The DOM menu stays in the
  // document as the fallback but leaves the a11y tree while covered.
  function arrive() {
    if (finished) return
    markGibsonSeen(storage)
    if (skipBtn) skipBtn.remove()

    let items = []
    try {
      const el = doc.getElementById("gibson-links")
      items = el ? JSON.parse(el.textContent).filter((x) => x && x.name && x.url) : []
    } catch {
      items = []
    }
    hotspots = doc.createElement("nav")
    hotspots.setAttribute("aria-label", "Links")
    hotspots.style.cssText = "position:fixed;inset:0;z-index:9002;pointer-events:none"
    const anchors = items.map((item, i) => {
      const a = doc.createElement("a")
      a.href = item.url
      if (item.external) {
        a.target = "_blank"
        a.rel = "noopener noreferrer"
      }
      // Full navigation, never a Swup swap: an SPA content swap would replace
      // the hidden DOM page underneath while the canvas keeps covering it —
      // URL changes, nothing visibly happens. Leaving the parked scene must
      // tear the whole page down.
      a.setAttribute("data-no-swup", "")
      // Links marked pixel:true leave through the same mosaic transition the
      // site arrived by (the delegated handler matches on a[data-pixel]).
      if (item.pixel) a.setAttribute("data-pixel", "")
      a.setAttribute("aria-label", item.name)
      a.style.cssText = "position:absolute;pointer-events:auto;cursor:pointer;outline:none"
      const hot = () => control.menuHighlight(i)
      const cool = () => control.menuHighlight(-1)
      a.addEventListener("mouseenter", hot)
      a.addEventListener("focus", hot)
      a.addEventListener("mouseleave", cool)
      a.addEventListener("blur", cool)
      hotspots.appendChild(a)
      return a
    })
    function layout() {
      control.menuRects().forEach((r, i) => {
        const a = anchors[i]
        if (!a) return
        a.style.left = `${r.left}px`
        a.style.top = `${r.top}px`
        a.style.width = `${r.width}px`
        a.style.height = `${r.height}px`
      })
    }
    layout()
    win.addEventListener("resize", () => win.setTimeout(layout, 60))
    doc.body.appendChild(hotspots)
  }

  function maybeStart() {
    // `!finished` guards the skip-before-bundle-loads race: if the user skipped
    // before the bundle resolved, don't start the flight on a removed canvas.
    // Parked mode doesn't wait for the mosaic — there's no flight to hold back,
    // and the live scene should already be running when the cover clears.
    if ((mosaicDone || mode === "parked") && control && !started && !finished) {
      started = true
      control.start()
    }
  }

  function doSkip() {
    if (control) control.skip() // skip() -> onComplete -> finish()
    else finish() // not loaded yet: just reveal the menu
  }

  function onKey(e) {
    // Production key: skip.
    if (e.key === "Escape" || e.key === " " || e.code === "Space") {
      e.preventDefault()
      doSkip()
      return
    }
    // ` toggles debug mode; the inspection keys below only work inside it.
    if (e.code === "Backquote" || e.key === "`") {
      e.preventDefault()
      toggleDebug()
      return
    }
    if (!debugMode) return
    // P pauses/resumes the flight (the path ribbon lighting up is the paused
    // indicator); arrows scrub while paused.
    if ((e.key === "p" || e.key === "P") && control?.togglePause) {
      e.preventDefault()
      debugPaused = control.togglePause()
    }
    if ((e.key === "ArrowLeft" || e.key === "ArrowRight") && control?.nudge) {
      e.preventDefault()
      control.nudge(e.key === "ArrowRight" ? 0.02 : -0.02)
    }
  }

  if (skipBtn) skipBtn.addEventListener("click", doSkip)
  win.addEventListener("keydown", onKey)

  // Take over the reveal: when the mosaic-in clears, the scene (built behind it)
  // takes the screen. Start the flight once both the cover is gone and the
  // bundle is ready. The gate holds the mosaic's clearing animation until the
  // scene's first frame is painted, so the mosaic reveals the city — not a
  // black canvas racing a slow bundle load.
  let sceneReady
  setMosaicInGate(new Promise((resolve) => (sceneReady = resolve)))
  setMosaicInHook(() => {
    mosaicDone = true
    maybeStart()
  })

  injectBundle(doc, win)
    .then(() => {
      // Skipped before the bundle loaded: the canvas is already gone, so never
      // build the scene (it would leak a WebGL context on a detached canvas).
      if (finished) return
      control = win.__gibsonRun(canvas, {onComplete: finish, onArrived: arrive, mode})
      sceneReady()
      maybeStart()
    })
    .catch(() => {
      // Bundle failed: drop the canvas + skip UI and let the DOM menu show.
      releaseHold()
      sceneReady()
      cleanupSkipUi()
      canvas.remove()
    })
}
