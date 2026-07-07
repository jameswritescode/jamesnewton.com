// Pure generator for the camera route: a high opening INSIDE the city (so
// towers fade into fog in every direction — no visible edge, ever), a shallow
// glide down into a central street, a couple of RANDOM gentle turns onto
// crossing streets (corners are sampled quarter-circle arcs, not sharp bends),
// then a turn toward a tower and a RISE up its face, ending square to it — the
// face that becomes the menu. No three.js — returns plain {x,y,z} waypoints so
// it is unit-testable; the scene builds a curve from them.

// Seedable RNG (mulberry32) so a ?seed run is reproducible.
export function makeRng(seed) {
  let a = seed >>> 0
  return function () {
    a = (a + 0x6d2b79f5) | 0
    let t = Math.imul(a ^ (a >>> 15), 1 | a)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

// grid: {cols, rows, spacing, towerFrac}. Streets run along the grid lines;
// towers sit at cell centres (offset half a cell in both x and z). The whole
// route stays within the central ~40% of the grid so, from any point on it,
// the nearest grid edge is beyond the fog-opaque distance.
// Returns {waypoints:[{x,y,z}], landing:{col,row,x,z,faceX,side,lookY}}.
// `endDistFrac` (in spacing units) is how far in front of the landing face the
// camera parks — the scene computes it from the viewport's horizontal FOV so
// the menu panel always fits the frame (portrait phones need to stand further
// back), clamped so the camera never backs into the opposite tower row.
export function generateRoute(grid, rand = Math.random, endDistFrac = 0.34) {
  const {cols, rows, spacing} = grid
  const towerFrac = grid.towerFrac ?? 0.3
  const pick = (n) => Math.floor(rand() * Math.max(1, n))
  const cruiseY = spacing * 0.78 // street cruise height (~40% of tower height)
  const halfFoot = (spacing * towerFrac) / 2

  const avX = (i) => (i - cols / 2) * spacing // street line for column-gap i

  const wp = []
  let pathLen = 0
  const push = (x, y, z) => {
    const prev = wp[wp.length - 1]
    if (prev) pathLen += Math.hypot(x - prev.x, y - prev.y, z - prev.z)
    wp.push({x, y, z})
  }

  // Corner at intersection `c`: arrive along unit `u`, leave along unit `v`.
  // A single centred quarter-arc between the two street centre lines — no
  // entry/exit drift (lateral jogs read as S-wobble through the spline, and a
  // centred arc at this radius clears the inside-corner tower by the same
  // margin anyway). Finely sampled so the spline hugs a true circle and the
  // heading pans ~10°/segment.
  const R = spacing * 0.68 // arc radius
  // Each corner records its span of the route (in path length, later
  // normalised to arc fractions) so the flight can run a speed profile:
  // slow cruise, quick corners.
  const turnSpans = []
  const corner = (c, u, v, r = R, n = 9) => {
    const cx = c.x + (v.x - u.x) * r
    const cz = c.z + (v.z - u.z) * r
    let start = 0
    for (let k = 0; k <= n; k++) {
      const th = (k / n) * (Math.PI / 2)
      push(
        cx - v.x * r * Math.cos(th) + u.x * r * Math.sin(th),
        cruiseY,
        cz - v.z * r * Math.cos(th) + u.z * r * Math.sin(th),
      )
      // The window opens at the arc's FIRST point — the straight run leading
      // here belongs to the cruise, not the corner.
      if (k === 0) start = pathLen
    }
    turnSpans.push({start, end: pathLen})
  }

  // --- deterministic opening: above the rooftops, gliding down ---
  // Low enough that the glowing tower FACES (not dark roofs) carry the view —
  // endless lit rows fading into fog — and shallow so there's no lookAt roll.
  const sx = avX(Math.round(cols / 2)) // central street, heading -z
  // One ANALYTIC glide: altitude follows a quadratic ease-out from the opening
  // height down to cruise — pitch decays continuously to exactly level, with
  // no waypoint corners for the spline to round (hand-placed flare points made
  // the spline invent small bobs between them). Sampled densely so the curve
  // reproduces the parabola faithfully.
  const openY = spacing * 4.8
  const openZ = spacing * 7.5
  const glideEndZ = -spacing * 2.6
  const GLIDE_N = 22
  for (let i = 0; i <= GLIDE_N; i++) {
    const u = i / GLIDE_N
    push(sx, cruiseY + (openY - cruiseY) * (1 - u) * (1 - u), openZ + (glideEndZ - openZ) * u)
  }

  // --- random turns onto crossing streets ---
  // Legs are ≥4 cells so each corner's outward drift + arc (~1.4 cells on each
  // side of the intersection) still leaves a straight run between manoeuvres.
  const k1 = 4 + pick(2) // rows of street before the first turn
  const z1 = -spacing * k1
  const dir = rand() < 0.5 ? -1 : 1
  corner({x: sx, z: z1}, {x: 0, z: -1}, {x: dir, z: 0})

  const m2 = 4 + pick(2) // cross 4-5 cells
  const x2 = sx + dir * spacing * m2
  corner({x: x2, z: z1}, {x: dir, z: 0}, {x: 0, z: -1})

  // --- landing tower beside the final street ---
  const side = rand() < 0.5 ? -1 : 1
  const kd = 2 + pick(2) // rows ridden before the landing tower
  const tz = -spacing * (k1 + kd + 0.5) // a tower centre beside the street
  const tx = x2 + side * spacing * 0.5
  const fx = tx - side * halfFoot // its face fronting the street

  // --- rise up the tower face (near-vertical climb on the street centre
  // line), ending square to it, close enough that the menu fills the view ---
  const upY = spacing * 1.45 // ~72% up the (2 * spacing tall) face
  push(x2, cruiseY, tz + spacing * 0.8)
  push(x2, cruiseY + spacing * 0.28, tz + spacing * 0.3)
  push(x2 + side * spacing * 0.005, cruiseY + spacing * 0.55, tz + spacing * 0.08)
  push(fx - side * spacing * endDistFrac, upY, tz)

  const col = Math.round(x2 / spacing + cols / 2) + (side > 0 ? 0 : -1)
  const row = Math.round(rows / 2 - (k1 + kd + 1))
  const turns = turnSpans.map((t) => ({start: t.start / pathLen, end: t.end / pathLen}))
  return {waypoints: wp, cruiseY, turns, landing: {col, row, x: tx, z: tz, faceX: fx, side, lookY: upY}}
}
