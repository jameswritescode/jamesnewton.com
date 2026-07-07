import {describe, it, expect} from "vitest"
import {hasWebGL, cinematicMode, markGibsonSeen} from "./gibson_gate"

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

describe("markGibsonSeen", () => {
  it("sets the persistent flag", () => {
    const s = fakeStorage()
    markGibsonSeen(s)
    expect(s.getItem("gibson-seen")).toBe("1")
  })
})
