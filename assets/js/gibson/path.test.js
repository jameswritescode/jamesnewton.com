import {describe, it, expect} from "vitest"
import {makeRng, generateRoute} from "./path"

// Realistic proportions: matches the scene GRID (streets ~2.3x tower footprint,
// tower height = 2 * spacing).
const grid = {cols: 40, rows: 40, spacing: 44, towerFrac: 0.3}
const extent = (grid.cols / 2) * grid.spacing

describe("makeRng", () => {
  it("is deterministic for a given seed", () => {
    const a = makeRng(42)
    const b = makeRng(42)
    expect([a(), a(), a()]).toEqual([b(), b(), b()])
  })
})

describe("generateRoute", () => {
  it("stays deep inside the grid so the city edge is never in view", () => {
    for (const seed of [1, 2, 3, 4, 5]) {
      const route = generateRoute(grid, makeRng(seed))
      for (const w of route.waypoints) {
        expect(Math.abs(w.x)).toBeLessThan(extent * 0.5)
        expect(Math.abs(w.z)).toBeLessThan(extent * 0.5)
      }
    }
  })

  it("opens high above the rooftops and descends to street level", () => {
    const route = generateRoute(grid, makeRng(1))
    const ys = route.waypoints.map((w) => w.y)
    expect(ys[0]).toBeGreaterThan(grid.spacing * 2.5) // above H = 2 * spacing
    expect(Math.min(...ys)).toBeLessThan(grid.spacing) // down into the street
  })

  it("keeps clearance from every tower: no cell is removed, none is grazed", () => {
    const s = grid.spacing
    const halfFoot = (s * grid.towerFrac) / 2
    for (const seed of [1, 2, 3, 4, 5]) {
      const route = generateRoute(grid, makeRng(seed))
      expect(route.clear ?? []).toEqual([]) // the grid stays intact
      const wps = route.waypoints
      for (let i = 0; i < wps.length - 1; i++) {
        for (let k = 0; k <= 4; k++) {
          const x = wps[i].x + ((wps[i + 1].x - wps[i].x) * k) / 4
          const y = wps[i].y + ((wps[i + 1].y - wps[i].y) * k) / 4
          const z = wps[i].z + ((wps[i + 1].z - wps[i].z) * k) / 4
          if (y >= s * 2) continue // above the rooftops
          // Chebyshev distance to the nearest tower footprint centre
          const tx = (Math.round(x / s - 0.5) + 0.5) * s
          const tz = (Math.round(z / s - 0.5) + 0.5) * s
          const d = Math.max(Math.abs(x - tx), Math.abs(z - tz))
          expect(d).toBeGreaterThan(halfFoot + 5)
        }
      }
    }
  })

  it("turns gently: the xz heading never jumps sharply between segments", () => {
    for (const seed of [1, 2, 3]) {
      const route = generateRoute(grid, makeRng(seed))
      let prev = null
      for (let i = 1; i < route.waypoints.length; i++) {
        const dx = route.waypoints[i].x - route.waypoints[i - 1].x
        const dz = route.waypoints[i].z - route.waypoints[i - 1].z
        if (Math.hypot(dx, dz) < 0.001) continue
        const h = Math.atan2(dx, dz)
        if (prev !== null) {
          let d = Math.abs(h - prev)
          if (d > Math.PI) d = 2 * Math.PI - d
          expect(d).toBeLessThan(Math.PI / 6) // < 30° per segment (rounded corners)
        }
        prev = h
      }
    }
  })

  it("travels along both axes (it turns at least once)", () => {
    const route = generateRoute(grid, makeRng(7))
    const segs = []
    for (let i = 1; i < route.waypoints.length; i++) {
      const dx = Math.abs(route.waypoints[i].x - route.waypoints[i - 1].x)
      const dz = Math.abs(route.waypoints[i].z - route.waypoints[i - 1].z)
      if (dx + dz > 0.001) segs.push(dx > dz ? "x" : "z")
    }
    expect(new Set(segs).size).toBeGreaterThanOrEqual(2)
  })

  it("ends risen up the landing tower, square to its face", () => {
    for (const seed of [1, 2, 3, 4, 5]) {
      const route = generateRoute(grid, makeRng(seed))
      const wps = route.waypoints
      const last = wps[wps.length - 1]
      expect(last.z).toBeCloseTo(route.landing.z, 5) // aligned with the tower centre
      expect(last.y).toBeGreaterThan(grid.spacing * 1.2) // rose up the face
      expect(route.landing.lookY).toBeGreaterThan(grid.spacing) // face-on look target, high
      const gap = Math.abs(last.x - route.landing.faceX)
      expect(gap).toBeGreaterThan(grid.spacing * 0.1) // not inside the tower
      expect(gap).toBeLessThan(grid.spacing * 0.7) // near enough that the menu face dominates
    }
  })

  it("reports its two corner windows as ordered, non-overlapping arc fractions", () => {
    for (const seed of [1, 2, 3, 4, 5]) {
      const route = generateRoute(grid, makeRng(seed))
      expect(route.turns).toHaveLength(2)
      const [a, b] = route.turns
      for (const t of [a, b]) {
        expect(t.start).toBeGreaterThan(0)
        expect(t.end).toBeLessThan(1)
        expect(t.end).toBeGreaterThan(t.start)
      }
      expect(b.start).toBeGreaterThan(a.end)
    }
  })

  it("is deterministic for a given seed and varies across seeds", () => {
    expect(generateRoute(grid, makeRng(3))).toEqual(generateRoute(grid, makeRng(3)))
    expect(generateRoute(grid, makeRng(3))).not.toEqual(generateRoute(grid, makeRng(4)))
  })
})
