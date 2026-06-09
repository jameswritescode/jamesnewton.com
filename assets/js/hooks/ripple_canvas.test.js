import {describe, it, expect, vi, afterEach} from "vitest"
import {RippleCanvas} from "./ripple_canvas"

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
