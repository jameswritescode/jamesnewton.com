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
//              (reduced motion, or previewed via ?still; ?intro never
//              overrides an accessibility choice)
//   "none"   — the plain DOM page (no WebGL, or forced via ?fallback)
export function cinematicMode(win = window, storage = win.localStorage, doc = document) {
  const params = new URLSearchParams(win.location.search)
  if (params.has("fallback")) return "none"
  if (!hasWebGL(doc)) return "none"
  if (prefersReducedMotion(win) || params.has("still")) return "still"
  if (params.has("intro")) return "flight"
  return storage.getItem(SEEN) === "1" ? "parked" : "flight"
}

export function markGibsonSeen(storage = window.localStorage) {
  storage.setItem(SEEN, "1")
}

// Which seeds drive the scene's two RNG streams. The city is FIXED (the same
// skyline every visit, so tuning judgments hold), while the flight route is
// random per load. Overrides for reproduction and A/B comparisons:
//   ?seed=N      — pins both streams (the historical fully-deterministic mode)
//   ?routeSeed=N — pins just the route through the fixed city (the scene logs
//                  each load's route seed, so any route can be replayed)
const CITY_SEED = 7

export function sceneSeeds(win = window, random = Math.random) {
  const params = new URLSearchParams(win.location.search)
  const seed = seedParam(params, "seed")
  if (seed !== null) return {city: seed, route: (seed ^ 0x9e3779b9) >>> 0}
  const route = seedParam(params, "routeSeed")
  return {city: CITY_SEED, route: route !== null ? route : 1 + Math.floor(random() * 0xffffff)}
}

function seedParam(params, name) {
  const s = params.get(name)
  return s == null ? null : Number(s) || 1
}
