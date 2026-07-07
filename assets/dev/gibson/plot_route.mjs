import * as THREE from "three"
import {generateRoute, makeRng} from "../../js/gibson/path.js"
import {chromium} from "playwright"

const GRID = {cols: 44, rows: 44, spacing: 44, towerFrac: 0.3}
const seed = 7
const routeRand = makeRng((seed ^ 0x9e3779b9) >>> 0)
const route = generateRoute(GRID, routeRand)

// replicate scene.js densify + curve
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
const pts = curve.getPoints(900)

// bounds around the route
const xs = pts.map(p => p.x), zs = pts.map(p => p.z)
const pad = 60
const minX = Math.min(...xs) - pad, maxX = Math.max(...xs) + pad
const minZ = Math.min(...zs) - pad, maxZ = Math.max(...zs) + pad
const W = 900, Hpx = (maxZ - minZ) / (maxX - minX) * W
const sx = (x) => (x - minX) / (maxX - minX) * W
const sz = (z) => (z - minZ) / (maxZ - minZ) * Hpx

// towers in range
let towers = ""
const s = GRID.spacing, hf = s * GRID.towerFrac / 2
for (let c = 0; c < GRID.cols; c++) for (let r = 0; r < GRID.rows; r++) {
  const tx = (c - 22 + 0.5) * s, tz = (r - 22 + 0.5) * s
  if (tx > minX - s && tx < maxX + s && tz > minZ - s && tz < maxZ + s) {
    towers += `<rect x="${sx(tx-hf)}" y="${sz(tz-hf)}" width="${sx(tx+hf)-sx(tx-hf)}" height="${sz(tz+hf)-sz(tz-hf)}" fill="#1a3a55"/>`
  }
}
const poly = pts.map(p => `${sx(p.x).toFixed(1)},${sz(p.z).toFixed(1)}`).join(" ")
const wps = route.waypoints.map(w => `<circle cx="${sx(w.x)}" cy="${sz(w.z)}" r="2.5" fill="#ff31d9"/>`).join("")
const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${Hpx}" style="background:#0a0a14">
${towers}
<polyline points="${poly}" fill="none" stroke="#fff" stroke-width="2"/>
${wps}
</svg>`

const b = await chromium.launch()
const p = await b.newPage({viewport: {width: Math.ceil(W), height: Math.ceil(Hpx)}})
await p.setContent(`<body style="margin:0">${svg}</body>`)
await p.screenshot({path: new URL("../../../tmp/gibson/route_plot.png", import.meta.url).pathname})
await b.close()
console.log("ok")
