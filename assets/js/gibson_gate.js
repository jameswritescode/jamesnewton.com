// Pure decisions for the /links cinematic. Dependency-injected for testing;
// jsdom can't make a real WebGL context, so `doc` is injectable.
import {prefersReducedMotion} from "./pixel_transition"

const SEEN = "gibson-seen"

export function hasWebGL(doc = document) {
  try {
    const c = doc.createElement("canvas")
    return !!(c.getContext("webgl2") || c.getContext("webgl"))
  } catch {
    return false
  }
}

// How /links presents itself:
//   "flight" — the full cinematic (first visit, or forced via ?intro)
//   "parked" — skip the flight, land directly on the menu tower (repeat visit)
//   "still"  — the menu tower as a static image: no flight, no scene animation
//              (reduced motion; ?intro never overrides an accessibility choice)
//   "none"   — the plain DOM page (no WebGL, or forced via ?fallback)
export function cinematicMode(win = window, storage = win.localStorage, doc = document) {
  const params = new URLSearchParams(win.location.search)
  if (params.has("fallback")) return "none"
  if (!hasWebGL(doc)) return "none"
  if (prefersReducedMotion(win)) return "still"
  if (params.has("intro")) return "flight"
  return storage.getItem(SEEN) === "1" ? "parked" : "flight"
}

export function markGibsonSeen(storage = window.localStorage) {
  storage.setItem(SEEN, "1")
}
