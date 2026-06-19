import {describe, it, expect, vi, afterEach} from "vitest"
import {RippleCanvas, frownPoints} from "./ripple_canvas"

// Build a 2D-context spy and a fake canvas, stub the animation + matchMedia
// globals, then run the hook's mounted() against them.
function mountWith({reduce}) {
  const ctx = {
    clearRect: vi.fn(),
    fillRect: vi.fn(),
    beginPath: vi.fn(),
    arc: vi.fn(),
    fill: vi.fn(),
    fillStyle: ""
  }
  const canvas = {getContext: () => ctx, width: 0, height: 0}

  window.matchMedia = vi.fn(() => ({
    matches: reduce,
    addEventListener: vi.fn(),
    removeEventListener: vi.fn()
  }))

  const raf = vi.fn(() => 1)
  vi.stubGlobal("requestAnimationFrame", raf)
  vi.stubGlobal("cancelAnimationFrame", vi.fn())

  const hook = Object.create(RippleCanvas)
  hook.el = canvas
  hook.mounted()

  return {ctx, raf}
}

describe("RippleCanvas + prefers-reduced-motion", () => {
  afterEach(() => vi.unstubAllGlobals())

  it("starts the animation loop when reduced motion is off", () => {
    const {raf} = mountWith({reduce: false})
    expect(raf).toHaveBeenCalled()
  })

  it("paints the static dot matrix and does not animate when reduced motion is on", () => {
    const {ctx, raf} = mountWith({reduce: true})
    expect(raf).not.toHaveBeenCalled()
    expect(ctx.arc).toHaveBeenCalled()
  })
})

describe("frownPoints", () => {
  it("places two eyes symmetric about centre and above it", () => {
    const {eyes} = frownPoints(1000, 800)
    expect(eyes).toHaveLength(2)
    const [l, r] = eyes
    expect(l.x).toBeLessThan(500)
    expect(r.x).toBeGreaterThan(500)
    expect((l.x + r.x) / 2).toBeCloseTo(500) // centred on width/2
    expect(l.y).toBe(r.y) // level
    expect(l.y).toBeLessThan(400) // above vertical centre
  })

  it("samples a frowning mouth: middle sits higher on screen than the corners", () => {
    const {mouth, eyes} = frownPoints(1000, 800)
    expect(mouth.length).toBeGreaterThanOrEqual(5)
    const mid = mouth[(mouth.length - 1) / 2]
    const left = mouth[0]
    const right = mouth[mouth.length - 1]
    // smaller y = higher on screen; a frown's middle is the high point
    expect(mid.y).toBeLessThan(left.y)
    expect(mid.y).toBeLessThan(right.y)
    expect(left.y).toBeCloseTo(right.y) // symmetric droop
    expect(mid.y).toBeGreaterThan(eyes[0].y) // mouth sits below the eyes
  })

  it("scales the face with the viewport", () => {
    const small = frownPoints(1000, 1000)
    const big = frownPoints(2000, 2000)
    expect(big.eyes[1].x - big.eyes[0].x).toBeGreaterThan(small.eyes[1].x - small.eyes[0].x)
  })
})
