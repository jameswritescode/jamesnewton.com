import {describe, it, expect} from "vitest"
import {hasWebGL, cinematicMode, markGibsonSeen, sceneSeeds} from "./gibson_gate"

function fakeStorage(initial = {}) {
  const m = new Map(Object.entries(initial))
  return {
    getItem: (k) => (m.has(k) ? m.get(k) : null),
    setItem: (k, v) => m.set(k, String(v)),
    removeItem: (k) => m.delete(k),
  }
}
// doc whose canvas returns (or refuses) a GL context
function fakeDoc(glOk) {
  return {createElement: () => ({getContext: (t) => (glOk && t.startsWith("webgl") ? {} : null)})}
}
function fakeWin({reduced = false, search = ""} = {}) {
  return {matchMedia: () => ({matches: reduced}), location: {search}}
}

describe("hasWebGL", () => {
  it("is true when a webgl context is available", () => {
    expect(hasWebGL(fakeDoc(true))).toBe(true)
  })
  it("is false when no context can be made", () => {
    expect(hasWebGL(fakeDoc(false))).toBe(false)
  })
  it("is false (not throwing) when getContext throws", () => {
    const doc = {
      createElement: () => ({
        getContext: () => {
          throw new Error("WebGL blocked")
        },
      }),
    }
    expect(hasWebGL(doc)).toBe(false)
  })
})

describe("cinematicMode", () => {
  const doc = fakeDoc(true)

  it("flies the full cinematic on a first visit (flag unset, WebGL, motion ok)", () => {
    expect(cinematicMode(fakeWin(), fakeStorage(), doc)).toBe("flight")
  })
  it("parks straight on the menu tower on a repeat visit (flag set)", () => {
    expect(cinematicMode(fakeWin(), fakeStorage({"gibson-seen": "1"}), doc)).toBe("parked")
  })
  it("?intro forces the full flight even when the flag is set", () => {
    expect(cinematicMode(fakeWin({search: "?intro"}), fakeStorage({"gibson-seen": "1"}), doc)).toBe("flight")
  })
  it("goes straight to a STILL tower under reduced-motion (no flight, no scene animation)", () => {
    expect(cinematicMode(fakeWin({reduced: true}), fakeStorage(), doc)).toBe("still")
    expect(cinematicMode(fakeWin({reduced: true, search: "?intro"}), fakeStorage(), doc)).toBe("still")
  })
  it("falls back to the DOM page without WebGL", () => {
    expect(cinematicMode(fakeWin({search: "?intro"}), fakeStorage(), fakeDoc(false))).toBe("none")
    expect(cinematicMode(fakeWin({reduced: true}), fakeStorage(), fakeDoc(false))).toBe("none")
  })
  it("?fallback forces the plain DOM page, beating everything else", () => {
    expect(cinematicMode(fakeWin({search: "?fallback"}), fakeStorage(), doc)).toBe("none")
    expect(cinematicMode(fakeWin({search: "?fallback&intro"}), fakeStorage({"gibson-seen": "1"}), doc)).toBe("none")
  })
})

describe("sceneSeeds", () => {
  const fixedRandom = () => 0.5

  it("keeps the city fixed and picks a random route seed per load", () => {
    const a = sceneSeeds(fakeWin(), () => 0.123)
    const b = sceneSeeds(fakeWin(), () => 0.789)
    expect(a.city).toBe(7)
    expect(b.city).toBe(7)
    expect(a.route).not.toBe(b.route)
    expect(Number.isInteger(a.route)).toBe(true)
    expect(a.route).toBeGreaterThan(0)
  })
  it("?routeSeed=N pins the route while the city stays fixed", () => {
    const s = sceneSeeds(fakeWin({search: "?routeSeed=42"}), fixedRandom)
    expect(s).toEqual({city: 7, route: 42})
  })
  it("?seed=N pins both streams deterministically (city N, route derived from N)", () => {
    const a = sceneSeeds(fakeWin({search: "?seed=3"}), () => 0.1)
    const b = sceneSeeds(fakeWin({search: "?seed=3"}), () => 0.9)
    expect(a).toEqual(b)
    expect(a.city).toBe(3)
    expect(a.route).toBe((3 ^ 0x9e3779b9) >>> 0)
  })
  it("?seed beats ?routeSeed when both are present", () => {
    const s = sceneSeeds(fakeWin({search: "?seed=3&routeSeed=42"}), fixedRandom)
    expect(s.route).toBe((3 ^ 0x9e3779b9) >>> 0)
  })
  it("treats a garbage seed value as 1, not NaN", () => {
    expect(sceneSeeds(fakeWin({search: "?seed=abc"}), fixedRandom).city).toBe(1)
    expect(sceneSeeds(fakeWin({search: "?routeSeed=abc"}), fixedRandom).route).toBe(1)
  })
})

describe("markGibsonSeen", () => {
  it("sets the persistent flag", () => {
    const s = fakeStorage()
    markGibsonSeen(s)
    expect(s.getItem("gibson-seen")).toBe("1")
  })
})
