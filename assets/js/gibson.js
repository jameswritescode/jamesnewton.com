// Lazily-loaded WebGL bundle (its own esbuild entry → /assets/js/gibson.js).
// Contract: window.__gibsonRun(canvas, {onComplete, onArrived}) -> control
//   - builds the scene and renders frame 0 immediately
//   - control.start() flies the camera route; control.skip() fast-forwards
//   - onArrived() fires once when the flight PARKS on the landing tower — the
//     scene keeps rendering (live city) and the tower's menu face becomes the
//     page's menu via control.menuRects()/menuHighlight()
//   - onComplete() fires only on BAIL (WebGL too slow, or skip before the
//     flight began): the scene is disposed and the DOM page takes over
import {buildScene} from "./gibson/scene.js"

window.__gibsonRun = function (canvas, {onComplete, onArrived, mode = "flight"}) {
  const built = buildScene(canvas, window, {still: mode === "still", mode})

  // Browsers reclaim WebGL contexts from backgrounded tabs. Unhandled, the
  // canvas goes permanently blank (showing whatever sits underneath).
  // preventDefault signals we want restoration; three re-uploads everything on
  // the next render after `webglcontextrestored`. If the context stays lost
  // while the page is actually visible, the mode branches below fall back to
  // the DOM page instead of presenting a void.
  const CTX_LOST_GRACE_MS = 4000
  let ctxLostAt = null
  canvas.addEventListener("webglcontextlost", (e) => {
    e.preventDefault()
    ctxLostAt = performance.now()
  })
  // A context reclaimed while the tab is hidden must get its full restore
  // grace from the moment the user RETURNS — not from the loss (which may be
  // many hidden seconds ago). pageshow covers bfcache restores (Safari
  // especially), where some engines don't fire visibilitychange.
  const restartLossGrace = () => {
    if (ctxLostAt !== null) ctxLostAt = performance.now()
  }
  document.addEventListener("visibilitychange", restartLossGrace)
  window.addEventListener("pageshow", restartLossGrace)

  // Reduced motion ("still"): the parked menu tower as a static image — no
  // flight, no render loop, no scene animation. Renders exactly once, then
  // once more per hover highlight or resize.
  if (mode === "still") {
    built.render(1)
    window.addEventListener("resize", () => setTimeout(() => built.render(1), 80))
    canvas.addEventListener("webglcontextrestored", () => {
      ctxLostAt = null
      built.render(1)
    })
    const lostCheck = setInterval(() => {
      if (ctxLostAt !== null && !document.hidden && performance.now() - ctxLostAt > CTX_LOST_GRACE_MS) {
        clearInterval(lostCheck)
        built.dispose()
        onComplete()
      }
    }, 1000)
    // Defer: the intro assigns `control` from our return value, and its
    // arrive() handler lays out hotspots via control.menuRects().
    setTimeout(() => onArrived && onArrived(), 0)
    return {
      start() {},
      skip() {},
      menuRects() {
        return built.menu ? built.menu.rects() : []
      },
      menuHighlight(i) {
        if (built.menu) {
          built.menu.highlight(i)
          built.render(1)
        }
      },
      togglePause() {
        return false
      },
      nudge() {},
    }
  }

  // Debug: ?gibsonFrame=0..1 holds a static frame at that route fraction so the
  // scene/route can be inspected independent of mosaic/bundle/flight timing.
  const frameParam = new URLSearchParams(window.location.search).get("gibsonFrame")
  if (frameParam !== null) {
    if (built.menu) built.menu.forceOpen() // static holds show the panel open
    built.render(Math.max(0, Math.min(1, parseFloat(frameParam) || 0)))
    window.__cam = built.camera // expose for debugging
    window.__route = built.route
    return {start() {}, skip() {}}
  }

  // First painted frame: the flight's opening — or, for repeat visitors
  // ("parked" mode), the landing view itself; the loop below then backdates
  // startTime so t is already 1 and the scene parks on its first frame.
  built.render(mode === "parked" ? 1 : 0)
  // Dirty the data textures and render again while still covered: the second
  // render absorbs the one-off canvas→GPU re-upload warm-up that would
  // otherwise hitch the flight when character-cycling starts (~5s in).
  built.primeDataCycle()
  built.render(mode === "parked" ? 1 : 0)

  // Context restore during flight/parked: the running loop repaints on its own.
  canvas.addEventListener("webglcontextrestored", () => {
    ctxLostAt = null
  })

  const DURATION = 14000 // slow cruise; corners stay quick via the scene's speed profile
  let raf = null
  let startTime = null
  let lastNow = null
  let lastRenderAt = 0
  let paused = false
  let parked = false
  let bailed = false

  // Abandon the 3D takeover: dispose and reveal the DOM page. Only for skips
  // before the flight begins and for hardware that can't render the scene.
  function bail() {
    if (bailed) return
    bailed = true
    if (raf) cancelAnimationFrame(raf)
    raf = null
    built.dispose()
    onComplete()
  }

  // Frame-pacing stats, sampled in 500ms windows: feeds the adaptive-quality
  // controller below, and window.__gibsonFps stays exposed as the hook the
  // dev perf probe reads (no visible readout — that returns with the planned
  // debug-tooling refactor).
  const deltas = []
  let fpsAt = 0
  // Crossing a visibility boundary poisons the pacing clocks (the first
  // visible frame's delta spans the whole hidden stretch) — start fresh.
  // pageshow covers bfcache restores, which can skip visibilitychange.
  const resetPacing = () => {
    deltas.length = 0
    lastRenderAt = 0
    fpsAt = performance.now()
  }
  document.addEventListener("visibilitychange", resetPacing)
  window.addEventListener("pageshow", resetPacing)

  // Adaptive quality: GPUs that can't hold the flight get the render
  // resolution stepped down (quadratic fill savings); effectively
  // software-rendered WebGL (a slideshow) bails to the DOM menu rather than
  // torturing the visitor — even from the parked ending. The flight starts
  // at the scene's 1.5 cap; arrival restores full resolution below.
  let quality = Math.min(window.devicePixelRatio || 1, mode === "flight" ? 1.5 : 2)
  let stepped = false
  let slideshowWindows = 0
  function adaptQuality(fps) {
    if (bailed) return
    if (fps < 12) {
      slideshowWindows++
      if (slideshowWindows >= 3) bail()
      return
    }
    slideshowWindows = 0
    // No step-down while parked: the 30fps ambience throttle would read as a
    // struggling GPU.
    if (fps < 45 && quality > 1 && !parked) {
      quality = Math.max(1, quality - 0.5)
      stepped = true
      built.setPixelRatio(quality)
    }
  }

  function frame(now) {
    if (bailed) return
    // Visible with a context that never came back: fall back to the DOM page.
    if (ctxLostAt !== null && !document.hidden && now - ctxLostAt > CTX_LOST_GRACE_MS) {
      return bail()
    }
    // Hidden tab (Firefox trickles background rAF at ~1fps; other engines
    // don't call us at all): do no work — no render, no texture uploads — and
    // freeze the flight clock so returning resumes exactly where it left off.
    // Memory can't be saved here (only disposal frees it); this is about not
    // burning GPU cycles on frames nobody sees.
    if (document.hidden) {
      if (startTime !== null && lastNow !== null) startTime += now - lastNow
      lastNow = now
      raf = requestAnimationFrame(frame)
      return
    }
    if (startTime === null) startTime = mode === "parked" ? now - DURATION : now
    // While paused, slide startTime forward so t freezes; rendering continues
    // (the glyph cycling stays alive on the frozen frame).
    if (paused && lastNow !== null) startTime += now - lastNow
    lastNow = now
    const t = Math.min(1, (now - startTime) / DURATION)
    const eased = t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2 // easeInOutQuad
    const e = built.timeToArc(eased) // slow cruise, quick corners
    // Parked = ambience: cap rendering at ~30fps. The camera is static; only
    // the city's background animation moves, and half the frames means half
    // the sustained GPU/battery cost on a page that may sit open for a while.
    // (The flight and the panel iris always render at full rate.)
    const throttled = parked && now - lastRenderAt < 32
    if (!throttled) {
      // fps samples measure RENDER pacing (truthful under the parked
      // throttle), flushed to window.__gibsonFps in 500ms windows. NEVER
      // sample while hidden: Firefox throttles background rAF to ~1fps, which
      // would read as a slideshow GPU and bail a healthy page to the DOM.
      const sampling = !document.hidden
      if (sampling && lastRenderAt > 0) deltas.push(now - lastRenderAt)
      built.render(e)
      lastRenderAt = now
      if (sampling && now - fpsAt > 500 && deltas.length) {
        fpsAt = now
        const avg = deltas.reduce((a, b) => a + b, 0) / deltas.length
        window.__gibsonFps = {fps: Math.round(1000 / avg), worst: Math.round(Math.max(...deltas))}
        deltas.length = 0
        adaptQuality(window.__gibsonFps.fps)
      }
    }
    if (t >= 1 && !parked && !paused) {
      parked = true
      // Static camera + 30fps throttle leave plenty of headroom for full
      // resolution, and the menu text deserves it. A GPU the flight already
      // stepped down keeps its reduced ratio.
      if (!stepped) {
        quality = Math.min(window.devicePixelRatio || 1, 2)
        built.setPixelRatio(quality)
      }
      if (onArrived) onArrived()
    }
    // The loop never stops: parked, the city stays alive behind the tower menu
    // (rAF self-throttles in hidden tabs; navigation away tears the page down).
    raf = requestAnimationFrame(frame)
  }

  return {
    start() {
      if (!bailed && raf === null) raf = requestAnimationFrame(frame)
    },
    skip() {
      if (bailed || parked) return
      // Flying: fast-forward to the parked ending. Not started yet: bail to
      // the DOM page (nothing worth showing).
      if (raf !== null && lastNow !== null) startTime = lastNow - DURATION
      else bail()
    },
    // Menu interaction for the parked ending (null-safe before arrival).
    menuRects() {
      return built.menu ? built.menu.rects() : []
    },
    menuHighlight(i) {
      if (built.menu) built.menu.highlight(i)
    },
    // Dev controls (additive to the C1 contract): freeze/unfreeze the flight,
    // and scrub by a fraction of the total duration while frozen.
    togglePause() {
      paused = !paused
      built.setPathVisible(paused) // paused = inspect mode: light up the flight path
      return paused
    },
    nudge(frac) {
      if (bailed || parked || startTime === null || lastNow === null) return
      // Clamp the target so scrubbing can't run past the end and trigger the park.
      const t = Math.min(1, (lastNow - startTime) / DURATION)
      const target = Math.min(0.995, Math.max(0, t + frac))
      startTime = lastNow - target * DURATION
    },
  }
}
