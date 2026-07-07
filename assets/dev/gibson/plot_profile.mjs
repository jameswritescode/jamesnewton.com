// Side-profile of the flight spline: altitude (y, exaggerated) vs distance
// along the route. Marks waypoints, the cruise line, and prints smoothness
// stats for the descent->level transition.
import * as THREE from "three"
import {generateRoute, makeRng} from "../../js/gibson/path.js"
import {chromium} from "playwright"

const GRID = {cols: 44, rows: 44, spacing: 44, towerFrac: 0.3}
const routeRand = makeRng((7 ^ 0x9e3779b9) >>> 0)
const route = generateRoute(GRID, routeRand)
function densify(wps, step) {
  const out = []
  for (let i = 0; i < wps.length - 1; i++) {
    const a = wps[i], b = wps[i + 1]
    out.push(new THREE.Vector3(a.x, a.y, a.z))
    const dx = b.x - a.x, dy = b.y - a.y, dz = b.z - a.z
    const n = Math.abs(dy) > 0.001 ? 1 : Math.max(1, Math.floor(Math.hypot(dx, dz) / step))
    for (let k = 1; k < n; k++) out.push(new THREE.Vector3(a.x + dx*k/n, a.y + dy*k/n, a.z + dz*k/n))
  }
  const last = wps[wps.length - 1]
  out.push(new THREE.Vector3(last.x, last.y, last.z))
  return out
}
const curve = new THREE.CatmullRomCurve3(densify(route.waypoints, GRID.spacing * 0.7))
curve.arcLengthDivisions = 20000
curve.updateArcLengths()

// sample arc 0..0.55 (opening through early cruise); x-axis = arc distance
const N = 800
const samples = []
for (let i = 0; i <= N; i++) {
  const t = (i / N) * 0.55
  const p = curve.getPointAt(Math.min(0.999, t))
  samples.push({d: t * curve.getLength(), y: p.y})
}
const cruiseY = route.cruiseY

// stats: oscillation around cruise after first approach
let minY = Infinity
let flips = 0
let prevSign = 0
for (let i = 1; i < samples.length; i++) {
  const dy = samples[i].y - samples[i - 1].y
  minY = Math.min(minY, samples[i].y)
  const sign = Math.sign(dy)
  if (sign !== 0 && prevSign !== 0 && sign !== prevSign && samples[i].y < cruiseY + 8) flips++
  if (sign !== 0) prevSign = sign
}
console.log(`cruiseY=${cruiseY.toFixed(1)} minY=${minY.toFixed(2)} undershoot=${(cruiseY - minY).toFixed(2)} slope-flips-near-cruise=${flips}`)

// SVG: y exaggerated 3x
const W = 1300, Hpx = 460
const minD = 0, maxD = samples[samples.length - 1].d
const yLo = cruiseY - 6, yHi = Math.max(...samples.map((s) => s.y)) + 8
const sxp = (d) => ((d - minD) / (maxD - minD)) * (W - 40) + 20
const syp = (y) => Hpx - 30 - ((y - yLo) / (yHi - yLo)) * (Hpx - 60)
const poly = samples.map((s) => `${sxp(s.d).toFixed(1)},${syp(s.y).toFixed(1)}`).join(" ")
const wpDots = route.waypoints
  .filter((w) => Math.abs(w.x) < 1)
  .map((w) => {
    // project waypoint to nearest sample by y+z match: use z distance mapping via nearest sample
    let best = 0, bd = Infinity
    samples.forEach((s, i) => {}) // waypoints along x=0: map by y only is ambiguous; skip precision
    return ""
  })
const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${Hpx}" style="background:#0a0a14">
<line x1="20" y1="${syp(cruiseY)}" x2="${W - 20}" y2="${syp(cruiseY)}" stroke="#3a7bff" stroke-width="1" stroke-dasharray="6 5"/>
<text x="26" y="${syp(cruiseY) - 6}" fill="#3a7bff" font-family="monospace" font-size="14">cruise altitude</text>
<polyline points="${poly}" fill="none" stroke="#fff" stroke-width="2"/>
<text x="26" y="24" fill="#8ff6ff" font-family="monospace" font-size="14">side profile: altitude (3x exaggerated by axis range) vs distance flown</text>
</svg>`
const b = await chromium.launch()
const p = await b.newPage({viewport: {width: W, height: Hpx}})
await p.setContent(`<body style="margin:0">${svg}</body>`)
await p.screenshot({path: process.argv[2] ?? new URL("../../../tmp/gibson/profile.png", import.meta.url).pathname})
await b.close()
console.log("plotted")
