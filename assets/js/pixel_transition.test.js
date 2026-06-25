import {describe, it, expect, vi} from "vitest"
import {
  shuffledOrder,
  prefersReducedMotion,
  shouldMosaicIn,
  consumeInFlag,
  onPixelClick,
} from "./pixel_transition"

function fakeStorage(initial = {}) {
  const m = new Map(Object.entries(initial))
  return {
    getItem: (k) => (m.has(k) ? m.get(k) : null),
    setItem: (k, v) => m.set(k, String(v)),
    removeItem: (k) => m.delete(k),
  }
}

function fakeWin({reduced = false, pathname = "/"} = {}) {
  return {matchMedia: () => ({matches: reduced}), location: {pathname}}
}

function clickEvent(link, overrides = {}) {
  return {
    button: 0,
    metaKey: false,
    ctrlKey: false,
    shiftKey: false,
    altKey: false,
    defaultPrevented: false,
    target: {closest: (sel) => (sel === "a[data-pixel]" ? link : null)},
    preventDefault: vi.fn(),
    ...overrides,
  }
}

describe("shuffledOrder", () => {
  it("returns a permutation of every index", () => {
    const ord = shuffledOrder(50)
    expect(ord).toHaveLength(50)
    expect([...ord].sort((a, b) => a - b)).toEqual(Array.from({length: 50}, (_, i) => i))
  })

  it("is driven by the injected rand source", () => {
    // rand() === 0 makes every Fisher-Yates pick j=0, a deterministic order.
    expect(shuffledOrder(4, () => 0)).toEqual([1, 2, 3, 0])
  })
})

describe("prefersReducedMotion", () => {
  it("reflects the matchMedia result", () => {
    expect(prefersReducedMotion(fakeWin({reduced: true}))).toBe(true)
    expect(prefersReducedMotion(fakeWin({reduced: false}))).toBe(false)
  })
})

describe("shouldMosaicIn", () => {
  it("is true when the flag is set", () => {
    expect(shouldMosaicIn(fakeWin(), fakeStorage({[`pixel-in`]: "1"}))).toBe(true)
  })
  it("is true on /links even with no flag", () => {
    expect(shouldMosaicIn(fakeWin({pathname: "/links"}), fakeStorage())).toBe(true)
  })
  it("is false elsewhere with no flag", () => {
    expect(shouldMosaicIn(fakeWin({pathname: "/"}), fakeStorage())).toBe(false)
  })
  it("is false when reduced-motion is preferred, even with the flag", () => {
    expect(shouldMosaicIn(fakeWin({reduced: true, pathname: "/links"}), fakeStorage({[`pixel-in`]: "1"}))).toBe(false)
  })
})

describe("consumeInFlag", () => {
  it("returns true and clears the flag when present", () => {
    const s = fakeStorage({[`pixel-in`]: "1"})
    expect(consumeInFlag(s)).toBe(true)
    expect(s.getItem("pixel-in")).toBe(null)
  })
  it("returns false when absent", () => {
    expect(consumeInFlag(fakeStorage())).toBe(false)
  })
})

describe("onPixelClick", () => {
  it("intercepts a data-pixel link: prevents default, sets the flag, runs out", () => {
    const out = vi.fn()
    const storage = fakeStorage()
    const link = {getAttribute: () => "/links"}
    const e = clickEvent(link)
    onPixelClick(e, {win: fakeWin(), storage, out})
    expect(e.preventDefault).toHaveBeenCalled()
    expect(storage.getItem("pixel-in")).toBe("1")
    expect(out).toHaveBeenCalledWith("/links")
  })

  it("does nothing for a non-pixel target", () => {
    const out = vi.fn()
    const e = clickEvent(null)
    onPixelClick(e, {win: fakeWin(), storage: fakeStorage(), out})
    expect(e.preventDefault).not.toHaveBeenCalled()
    expect(out).not.toHaveBeenCalled()
  })

  it("does nothing when the event was already default-prevented", () => {
    const out = vi.fn()
    const link = {getAttribute: () => "/links"}
    const e = clickEvent(link, {defaultPrevented: true})
    onPixelClick(e, {win: fakeWin(), storage: fakeStorage(), out})
    expect(out).not.toHaveBeenCalled()
  })

  it("does nothing under reduced-motion (lets the browser navigate)", () => {
    const out = vi.fn()
    const link = {getAttribute: () => "/links"}
    const e = clickEvent(link)
    onPixelClick(e, {win: fakeWin({reduced: true}), storage: fakeStorage(), out})
    expect(e.preventDefault).not.toHaveBeenCalled()
    expect(out).not.toHaveBeenCalled()
  })

  it("ignores modifier/middle clicks so new-tab still works", () => {
    const out = vi.fn()
    const link = {getAttribute: () => "/links"}
    const e = clickEvent(link, {metaKey: true})
    onPixelClick(e, {win: fakeWin(), storage: fakeStorage(), out})
    expect(e.preventDefault).not.toHaveBeenCalled()
    expect(out).not.toHaveBeenCalled()
  })
})
