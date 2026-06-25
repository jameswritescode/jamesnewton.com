// Neon mosaic page transition across the site<->/links crossings.
// This file's exported functions are the pure/logic layer (dependency-injected
// for testing). The canvas animation layer is added separately; jsdom cannot
// run <canvas>, so only this layer is unit-tested.

const FLAG = "pixel-in"

const NEON = ["#19c9ff", "#ff31d9", "#b6ff00", "#8ff6ff"]
const SETTLE = "#05010a"
const BLOCK = 18 // px, fixed cell size; cell count scales with the viewport
const HALF_MS = 550 // duration of each half
const FLASH_MS = 90 // neon glow before a cell settles (out) or clears (in)

// Fisher-Yates shuffle of [0, count).
export function shuffledOrder(count, rand = Math.random) {
  const a = Array.from({length: count}, (_, i) => i)
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1))
    ;[a[i], a[j]] = [a[j], a[i]]
  }
  return a
}

export function prefersReducedMotion(win = window) {
  return win.matchMedia("(prefers-reduced-motion: reduce)").matches
}

// Should the destination page play a mosaic-in? Yes when we arrived via the
// transition (flag set) or we are on /links (covers direct loads / refreshes).
// Never when the user prefers reduced motion.
export function shouldMosaicIn(win = window, storage = win.sessionStorage) {
  if (prefersReducedMotion(win)) return false
  return storage.getItem(FLAG) === "1" || win.location.pathname === "/links"
}

// Read-and-clear the one-shot handoff flag.
export function consumeInFlag(storage = window.sessionStorage) {
  const had = storage.getItem(FLAG) === "1"
  storage.removeItem(FLAG)
  return had
}

// Click handler for a[data-pixel] links: set the handoff flag and run `out`
// (the canvas mosaic-out, injected by initPixelTransition). Leaves modifier and
// middle clicks alone so open-in-new-tab still works, and bails under
// reduced-motion so the browser navigates normally.
export function onPixelClick(event, {win = window, storage = win.sessionStorage, out} = {}) {
  if (event.defaultPrevented) return
  if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return

  const link = event.target.closest && event.target.closest("a[data-pixel]")
  if (!link) return
  if (prefersReducedMotion(win)) return

  event.preventDefault()
  storage.setItem(FLAG, "1")
  out(link.getAttribute("href"))
}

// --- canvas layer (not unit-tested: jsdom has no <canvas>) ---

function createOverlay(doc, win) {
  const canvas = doc.createElement("canvas")
  canvas.className = "pixel-overlay"
  canvas.setAttribute("aria-hidden", "true")
  canvas.width = win.innerWidth
  canvas.height = win.innerHeight
  doc.body.appendChild(canvas)
  return canvas
}

// Reveal (out) or clear (in) cells in random order over HALF_MS, each cell
// flashing a random neon colour for FLASH_MS first. `direction` is "out" | "in".
function runMosaic(canvas, direction, win, done) {
  const ctx = canvas.getContext("2d")
  const cols = Math.ceil(canvas.width / BLOCK)
  const rows = Math.ceil(canvas.height / BLOCK)
  const order = shuffledOrder(cols * rows)
  const total = order.length
  const active = new Map() // index -> {at, color}

  if (direction === "in") {
    ctx.fillStyle = SETTLE
    ctx.fillRect(0, 0, canvas.width, canvas.height)
  }

  const start = win.performance.now()
  function frame(now) {
    const t = Math.min(1, (now - start) / HALF_MS)
    const target = Math.floor(t * total)
    while (active.size < target) {
      const idx = order[active.size]
      active.set(idx, {at: now, color: NEON[Math.floor(Math.random() * NEON.length)]})
    }

    let glowing = false
    active.forEach(({at, color}, idx) => {
      const x = (idx % cols) * BLOCK
      const y = Math.floor(idx / cols) * BLOCK
      const flash = now - at < FLASH_MS
      if (flash) glowing = true
      if (direction === "out") {
        ctx.fillStyle = flash ? color : SETTLE
        ctx.fillRect(x, y, BLOCK, BLOCK)
      } else if (flash) {
        ctx.fillStyle = color
        ctx.fillRect(x, y, BLOCK, BLOCK)
      } else {
        ctx.clearRect(x, y, BLOCK, BLOCK)
      }
    })

    if (t < 1 || glowing) {
      win.requestAnimationFrame(frame)
    } else {
      done()
    }
  }
  win.requestAnimationFrame(frame)
}

// Guard against re-entry: a second click (or overlapping in/out) must not stack
// overlays or queue a second navigation while a transition is already running.
let running = false

export function pixelOut(href, {doc = document, win = window} = {}) {
  if (running) return
  running = true
  const canvas = createOverlay(doc, win)
  runMosaic(canvas, "out", win, () => {
    win.location.href = href
  })
}

export function pixelIn({doc = document, win = window} = {}) {
  if (running) return
  running = true
  const canvas = createOverlay(doc, win)
  runMosaic(canvas, "in", win, () => {
    canvas.remove()
    running = false
  })
}

// Install the delegated click listener and run a mosaic-in if we arrived via the
// transition or landed on /links. Call once per full document load.
export function initPixelTransition({doc = document, win = window, storage = win.sessionStorage} = {}) {
  doc.addEventListener("click", (event) =>
    onPixelClick(event, {win, storage, out: (href) => pixelOut(href, {doc, win})})
  )

  if (shouldMosaicIn(win, storage)) {
    consumeInFlag(storage)
    pixelIn({doc, win})
  }
}
