// Neon mosaic page transition across the site<->/links crossings.
// This file's exported functions are the pure/logic layer (dependency-injected
// for testing). The canvas animation layer is added separately; jsdom cannot
// run <canvas>, so only this layer is unit-tested.

const FLAG = "pixel-in"

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
