# /links Phase C2 — the Gibson Scene — Implementation Plan

> **For agentic workers:** This phase is iterative visual art direction. It is executed INLINE (build → screenshot → review → refine), NOT via the subagent test-pipeline. Steps use checkbox (`- [ ]`) syntax. The one genuinely unit-testable piece (the camera-path generator) is done TDD; every visual layer ends in a Playwright screenshot checkpoint reviewed with the human before refining.

**Goal:** Replace C1's placeholder scene with the inside-the-Gibson city — a glowing data-slab tower grid over circuit-trace avenues, flown on a randomized multi-segment route that dives into a tower face that becomes the menu.

**Architecture:** The lazy `gibson.js` esbuild entry stays the public surface (`window.__gibsonRun(canvas,{onComplete})->{start,skip}`, unchanged). Its body is refactored to compose focused modules under `assets/js/gibson/`: `path.js` (pure, testable route generator), `textures.js` (procedural canvas textures), and `scene.js` (builds the THREE scene + bloom). esbuild already bundles `gibson.js` and follows these imports — no config change.

**Tech Stack:** three.js (already installed), `three/examples/jsm/postprocessing/*` (UnrealBloom), vitest (path generator only), Playwright (screenshot harness), procedural Canvas2D textures.

**Context for the implementer:**
- C1 shipped the whole pipeline driving a placeholder scene. C2 changes ONLY the scene. The contract is fixed: `window.__gibsonRun(canvas, {onComplete})` builds the scene + renders frame 0, returns `{start, skip}`, fires `onComplete` exactly once at the end/skip, and must dispose its GPU resources.
- Current `assets/js/gibson.js` is the placeholder (three neon boxes). This plan rewrites it.
- The cinematic is reached via `/links?intro` (forces it) — that's how we screenshot. A running server is needed; use `PORT=4001 mix phx.server` (never touch the user's 4000). The dev esbuild watcher rebuilds `gibson.js` on change.
- Reference frames + the full target are in `docs/superpowers/specs/2026-06-26-links-page-phase-c2-gibson-scene-design.md`. Re-read it before tuning passes.
- three.js core math (`Vector3`, `CatmullRomCurve3`) runs in node/jsdom (no WebGL needed), but we keep the path generator free of three so its test needs no import.

**Visual-tuning note:** The code in the visual-layer tasks is a real, runnable FIRST PASS. Exact values (counts, colors, bloom strength, timings) are expected to change during the screenshot checkpoints — that's the point of this phase, not a plan defect.

---

### Task 1: Camera-path generator (pure, TDD)

**Files:**
- Create: `assets/js/gibson/path.js`
- Test: `assets/js/gibson/path.test.js`

- [ ] **Step 1: Write the failing test**

```javascript
// assets/js/gibson/path.test.js
import {describe, it, expect} from "vitest"
import {makeRng, generateRoute} from "./path"

const grid = {cols: 8, rows: 14, spacing: 10}

describe("makeRng", () => {
  it("is deterministic for a given seed", () => {
    const a = makeRng(42)
    const b = makeRng(42)
    expect([a(), a(), a()]).toEqual([b(), b(), b()])
  })
})

describe("generateRoute", () => {
  it("produces a multi-waypoint route ending at the landing tower", () => {
    const route = generateRoute(grid, makeRng(1))
    expect(route.waypoints.length).toBeGreaterThanOrEqual(6)
    const last = route.waypoints[route.waypoints.length - 1]
    expect(last).toHaveProperty("x")
    expect(last).toHaveProperty("z")
    expect(route.landing).toHaveProperty("col")
    expect(route.landing).toHaveProperty("row")
  })

  it("turns: it changes its dominant axis of travel at least once", () => {
    const route = generateRoute(grid, makeRng(7))
    const segs = []
    for (let i = 1; i < route.waypoints.length; i++) {
      const dx = Math.abs(route.waypoints[i].x - route.waypoints[i - 1].x)
      const dz = Math.abs(route.waypoints[i].z - route.waypoints[i - 1].z)
      if (dx + dz > 0.001) segs.push(dx > dz ? "x" : "z")
    }
    expect(new Set(segs).size).toBeGreaterThanOrEqual(2) // travels along both axes
  })

  it("is deterministic for a given seed and varies across seeds", () => {
    expect(generateRoute(grid, makeRng(3))).toEqual(generateRoute(grid, makeRng(3)))
    expect(generateRoute(grid, makeRng(3))).not.toEqual(generateRoute(grid, makeRng(4)))
  })
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pnpm --dir assets test gibson/path`
Expected: FAIL — `./path` does not exist.

- [ ] **Step 3: Implement the generator**

```javascript
// assets/js/gibson/path.js
// Pure generator for the camera route through the tower grid. No three.js: it
// returns plain {x,y,z} waypoints (the scene builds a CatmullRomCurve3 from
// them), so it is unit-testable without WebGL. Avenues run between tower
// columns (along z) and between rows (along x); the camera flies the gaps.

// Seedable RNG (mulberry32) so a ?seed screenshot is reproducible.
export function makeRng(seed) {
  let a = seed >>> 0
  return function () {
    a = (a + 0x6d2b79f5) | 0
    let t = Math.imul(a ^ (a >>> 15), 1 | a)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

// grid: {cols, rows, spacing}. Returns {waypoints:[{x,y,z}], landing:{col,row}}.
export function generateRoute(grid, rand = Math.random) {
  const {cols, rows, spacing} = grid
  const pick = (n) => Math.floor(rand() * n)
  const camY = spacing * 0.34

  const avenueX = (i) => (i - cols / 2) * spacing // avenue between columns i-1,i
  const rowZ = (r) => (r - rows / 2) * spacing
  const towerX = (col) => (col - cols / 2 + 0.5) * spacing

  const av = 1 + pick(cols - 1) // start avenue (interior)
  const startRow = rows - 1
  const turnRow = 3 + pick(Math.max(1, rows - 7))
  const dir = rand() < 0.5 ? -1 : 1
  const av2 = Math.min(cols - 1, Math.max(1, av + dir * (1 + pick(2))))
  const landingCol = dir > 0 ? av2 : av2 - 1 // tower beside the cross-avenue
  const landingRow = turnRow

  const wp = []
  const push = (x, y, z) => wp.push({x, y, z})

  push(avenueX(av), camY, rowZ(startRow) + spacing) // spawn just outside
  push(avenueX(av), camY, rowZ(startRow)) // enter the avenue
  push(avenueX(av), camY, rowZ(turnRow + 1)) // approach the turn
  push(avenueX(av), camY, rowZ(turnRow)) // turn point
  push(avenueX(av2), camY, rowZ(turnRow)) // along the cross-avenue
  const tx = towerX(landingCol)
  const tz = rowZ(landingRow)
  push((avenueX(av2) + tx) / 2, camY, rowZ(turnRow) - spacing * 0.25) // arc to face
  push(tx, camY * 0.92, tz + spacing * 0.55) // just in front of the face
  push(tx, camY * 0.92, tz) // into the face

  return {waypoints: wp, landing: {col: landingCol, row: landingRow}}
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `pnpm --dir assets test gibson/path`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add assets/js/gibson/path.js assets/js/gibson/path.test.js
git commit -m "$(cat <<'EOF'
Add the Gibson camera-route generator (pure, randomized multi-segment path)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Screenshot harness (committed dev tool)

**Files:**
- Create: `assets/gibson_shots.mjs`

A reusable Playwright script that loads `/links?intro&seed=N`, lets the flight run, and captures frames at several timestamps into `tmp/gibson/` for review. Mirrors the existing `assets/screenshot.mjs` dev tool. Used at every later checkpoint.

- [ ] **Step 1: Create the harness**

```javascript
// assets/gibson_shots.mjs
// Dev tool: capture frames of the /links Gibson cinematic for visual review.
//   BASE_URL=http://localhost:4001 pnpm exec node gibson_shots.mjs [seed]
// Writes PNGs to ../tmp/gibson/. Requires a running server serving the page.
import {chromium} from "playwright"
import {mkdirSync} from "node:fs"

const BASE = process.env.BASE_URL ?? "http://localhost:4001"
const seed = process.argv[2] ?? "1"
const outDir = new URL("../tmp/gibson/", import.meta.url).pathname
mkdirSync(outDir, {recursive: true})

const stops = [400, 1200, 2200, 3200, 4200] // ms into the flight

const browser = await chromium.launch()
const page = await browser.newPage({viewport: {width: 1280, height: 720}})
await page.goto(`${BASE}/links?intro&seed=${seed}`, {waitUntil: "domcontentloaded"})

let last = 0
for (const t of stops) {
  await page.waitForTimeout(t - last)
  last = t
  const file = `${outDir}seed${seed}-${String(t).padStart(4, "0")}ms.png`
  await page.screenshot({path: file})
  console.log("shot", file)
}
await browser.close()
```

- [ ] **Step 2: Confirm `tmp/` is gitignored (so screenshots aren't committed)**

Run: `grep -q '^/tmp/\|^tmp/' .gitignore && echo present || echo "ADD tmp/ to .gitignore"`
If absent, add a line `tmp/` to `.gitignore` and include it in the commit below.

- [ ] **Step 3: Commit**

```bash
git add assets/gibson_shots.mjs .gitignore
git commit -m "$(cat <<'EOF'
Add a Playwright screenshot harness for the Gibson cinematic

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Scene scaffold — renderer, fog, bloom, camera flies the real path (crude towers)

**Files:**
- Create: `assets/js/gibson/scene.js`
- Modify: `assets/js/gibson.js` (rewrite `__gibsonRun` to compose path + scene)

Goal of this layer: the real randomized route flies through a grid of crude (untextured) box towers, with fog + bloom, and lands → crossfade. Proves the whole pipeline end-to-end before art.

- [ ] **Step 1: Create the scene module (crude towers first pass)**

```javascript
// assets/js/gibson/scene.js
// Builds the Gibson THREE scene and an UnrealBloom composer. Returns the scene,
// camera, a render(t) using the route curve, and dispose(). Towers are crude
// boxes in this first pass; textures/floor/landing arrive in later layers.
import * as THREE from "three"
import {EffectComposer} from "three/examples/jsm/postprocessing/EffectComposer.js"
import {RenderPass} from "three/examples/jsm/postprocessing/RenderPass.js"
import {UnrealBloomPass} from "three/examples/jsm/postprocessing/UnrealBloomPass.js"
import {generateRoute, makeRng} from "./path.js"

export const GRID = {cols: 8, rows: 16, spacing: 10}

export function buildScene(canvas, win) {
  const w = win.innerWidth
  const h = win.innerHeight
  const rand = seedFromUrl(win) ?? Math.random

  const renderer = new THREE.WebGLRenderer({canvas, antialias: true})
  renderer.setPixelRatio(Math.min(win.devicePixelRatio || 1, 2))
  renderer.setSize(w, h, false)

  const scene = new THREE.Scene()
  scene.background = new THREE.Color(0x010108)
  scene.fog = new THREE.FogExp2(0x010108, 0.012)

  const camera = new THREE.PerspectiveCamera(70, w / h, 0.1, 2000)

  // crude towers: a box per grid cell, random heights, dim cyan
  const towerGeo = new THREE.BoxGeometry(GRID.spacing * 0.6, 1, GRID.spacing * 0.6)
  const towerMat = new THREE.MeshBasicMaterial({color: 0x0a3550})
  const disposables = [towerGeo, towerMat]
  for (let c = 0; c < GRID.cols; c++) {
    for (let r = 0; r < GRID.rows; r++) {
      const m = new THREE.Mesh(towerGeo, towerMat)
      const hgt = GRID.spacing * (3 + (rand() * 5) | 0)
      m.scale.y = hgt
      m.position.set(
        (c - GRID.cols / 2 + 0.5) * GRID.spacing,
        hgt / 2,
        (r - GRID.rows / 2) * GRID.spacing,
      )
      scene.add(m)
    }
  }

  const route = generateRoute(GRID, rand)
  const curve = new THREE.CatmullRomCurve3(
    route.waypoints.map((p) => new THREE.Vector3(p.x, p.y, p.z)),
  )

  const composer = new EffectComposer(renderer)
  composer.addPass(new RenderPass(scene, camera))
  const bloom = new UnrealBloomPass(new THREE.Vector2(w, h), 1.3, 0.6, 0.1)
  composer.addPass(bloom)

  // place the camera at curve(t), looking a little ahead along the curve
  function render(t) {
    const tt = Math.min(0.999, Math.max(0, t))
    const pos = curve.getPointAt(tt)
    const ahead = curve.getPointAt(Math.min(0.999, tt + 0.02))
    camera.position.copy(pos)
    camera.lookAt(ahead)
    composer.render()
  }

  function dispose() {
    disposables.forEach((d) => d.dispose())
    bloom.dispose()
    composer.dispose()
    renderer.dispose()
  }

  return {scene, camera, render, dispose, route}
}

function seedFromUrl(win) {
  const s = new URLSearchParams(win.location.search).get("seed")
  if (s == null) return null
  return makeRng(Number(s) || 1)
}
```

- [ ] **Step 2: Rewrite `assets/js/gibson.js` to drive the scene along the curve**

```javascript
// assets/js/gibson.js
// Lazily-loaded WebGL bundle (its own esbuild entry → /assets/js/gibson.js).
// Contract: window.__gibsonRun(canvas, {onComplete}) -> {start, skip}
//   - builds the scene and renders frame 0 immediately
//   - start() flies the camera route; skip() jumps to the end
//   - onComplete() fires exactly once, when the flight finishes or is skipped
import {buildScene} from "./gibson/scene.js"

window.__gibsonRun = function (canvas, {onComplete}) {
  const built = buildScene(canvas, window)
  built.render(0) // frame 0

  const DURATION = 4500
  let raf = null
  let startTime = null
  let done = false

  function finish() {
    if (done) return
    done = true
    if (raf) cancelAnimationFrame(raf)
    built.dispose()
    onComplete()
  }

  function frame(now) {
    if (startTime === null) startTime = now
    const t = Math.min(1, (now - startTime) / DURATION)
    const e = t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2 // easeInOutQuad
    built.render(e)
    if (t < 1) raf = requestAnimationFrame(frame)
    else finish()
  }

  return {
    start() {
      if (!done && raf === null) raf = requestAnimationFrame(frame)
    },
    skip() {
      finish()
    },
  }
}
```

- [ ] **Step 3: Build, then verify the existing pipeline still works**

Run: `mix assets.build`
Expected: succeeds (esbuild bundles three + the postprocessing addons into gibson.js).

Run: `pnpm --dir assets test`
Expected: PASS (gibson/path tests included; nothing else changed).

- [ ] **Step 4: SCREENSHOT CHECKPOINT**

Start a server (`PORT=4001 mix phx.server`), then:
Run: `cd assets && BASE_URL=http://localhost:4001 pnpm exec node gibson_shots.mjs 1`
Review `tmp/gibson/seed1-*.png` with the human: does the camera fly down an avenue, turn, and approach a tower, with bloom glow and fog depth? Iterate the path/camera/bloom until the MOTION reads right (geometry is still crude — that's expected). Try a few seeds.

- [ ] **Step 5: Commit**

```bash
git add assets/js/gibson.js assets/js/gibson/scene.js
git commit -m "$(cat <<'EOF'
Fly the real randomized Gibson route through a crude tower grid (scaffold)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Tower slabs + procedural data-face textures

**Files:**
- Create: `assets/js/gibson/textures.js`
- Modify: `assets/js/gibson/scene.js` (use slab towers with data-face textures)

- [ ] **Step 1: Create the texture module**

```javascript
// assets/js/gibson/textures.js
// Procedural Canvas2D textures for the Gibson. dataFaceTexture draws a tower
// "screen": dense rows of tiny glowing characters, small framed readout boxes,
// and bar patterns, in `hex` on near-black. Reused across towers (we build a
// few variants, not one per tower).
import * as THREE from "three"

const CHARS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ:/.-=+*#"

export function dataFaceTexture(hex, rand = Math.random, size = 512) {
  const cv = document.createElement("canvas")
  cv.width = size
  cv.height = size * 2 // slabs are ~2x taller than wide
  const ctx = cv.getContext("2d")
  ctx.fillStyle = "#02030a"
  ctx.fillRect(0, 0, cv.width, cv.height)

  const col = "#" + hex.toString(16).padStart(6, "0")
  ctx.fillStyle = col
  ctx.font = "11px monospace"
  ctx.globalAlpha = 0.85
  const lineH = 14
  for (let y = 16; y < cv.height; y += lineH) {
    let x = 8
    while (x < cv.width - 8) {
      if (rand() < 0.12) {
        // a framed readout box
        const bw = 26 + (rand() * 60) | 0
        ctx.globalAlpha = 0.5
        ctx.strokeStyle = col
        ctx.strokeRect(x, y - 10, bw, 12)
        ctx.globalAlpha = 0.85
        x += bw + 8
      } else {
        let n = 2 + (rand() * 8) | 0
        let s = ""
        for (let i = 0; i < n; i++) s += CHARS[(rand() * CHARS.length) | 0]
        ctx.fillText(s, x, y)
        x += ctx.measureText(s).width + 7
      }
    }
  }
  // bright edges
  ctx.globalAlpha = 1
  ctx.strokeStyle = "#" + hex.toString(16).padStart(6, "0")
  ctx.lineWidth = 6
  ctx.strokeRect(0, 0, cv.width, cv.height)

  const tex = new THREE.CanvasTexture(cv)
  tex.colorSpace = THREE.SRGBColorSpace
  return tex
}
```

- [ ] **Step 2: Use slab towers with the textures in `scene.js`**

Replace the crude-tower block in `buildScene` (the `towerGeo`/`towerMat` creation and the double loop) with: a unit box slab geometry (`new THREE.BoxGeometry(1,1,1)`); a small palette of face textures built once via `dataFaceTexture` (cyan plus a magenta and green accent); `MeshBasicMaterial` per texture; per cell, scale the slab to a tall thin box and pick a (mostly cyan) texture. Register every geometry/texture/material in `disposables`. Keep the slab faces facing the avenues.

```javascript
  const PALETTE = [0x19c9ff, 0x19c9ff, 0x19c9ff, 0x8ff6ff, 0xff31d9, 0xb6ff00]
  const faceTexes = PALETTE.map((hex) => dataFaceTexture(hex, rand))
  const slabMats = faceTexes.map((tex) => new THREE.MeshBasicMaterial({map: tex, fog: true}))
  const slabGeo = new THREE.BoxGeometry(1, 1, 1)
  const disposables = [slabGeo, ...faceTexes, ...slabMats]
  for (let c = 0; c < GRID.cols; c++) {
    for (let r = 0; r < GRID.rows; r++) {
      const mat = slabMats[(rand() * slabMats.length) | 0]
      const m = new THREE.Mesh(slabGeo, mat)
      const hgt = GRID.spacing * (3 + (rand() * 6) | 0)
      m.scale.set(GRID.spacing * 0.62, hgt, GRID.spacing * 0.62)
      m.position.set(
        (c - GRID.cols / 2 + 0.5) * GRID.spacing,
        hgt / 2,
        (r - GRID.rows / 2) * GRID.spacing,
      )
      scene.add(m)
    }
  }
```

(Import `dataFaceTexture` at the top of `scene.js`: `import {dataFaceTexture} from "./textures.js"`.)

- [ ] **Step 3: Build + SCREENSHOT CHECKPOINT**

Run: `mix assets.build` (expected: succeeds), then re-run the harness and review with the human: do the towers read as glowing data-screens like the references? Tune character density, font size, edge brightness, texture count.

- [ ] **Step 4: Commit**

```bash
git add assets/js/gibson/textures.js assets/js/gibson/scene.js
git commit -m "$(cat <<'EOF'
Build glowing data-slab towers with procedural face textures

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Circuit-trace floor

**Files:**
- Modify: `assets/js/gibson/textures.js` (add `floorTexture`)
- Modify: `assets/js/gibson/scene.js` (add the floor plane)

- [ ] **Step 1: Add `floorTexture`** — a large dark canvas with glowing magenta/blue right-angle PCB traces (random L/U-shaped paths with rounded corners), tiling along the avenues. Return a `THREE.CanvasTexture` with `wrapS=wrapT=RepeatWrapping`.

```javascript
export function floorTexture(rand = Math.random, size = 1024) {
  const cv = document.createElement("canvas")
  cv.width = cv.height = size
  const ctx = cv.getContext("2d")
  ctx.fillStyle = "#020208"
  ctx.fillRect(0, 0, size, size)
  ctx.lineWidth = 3
  ctx.lineCap = "round"
  ctx.lineJoin = "round"
  const cols = ["#ff31d9", "#7a3cff", "#1f6fff"]
  for (let i = 0; i < 40; i++) {
    ctx.strokeStyle = cols[(rand() * cols.length) | 0]
    ctx.globalAlpha = 0.5 + rand() * 0.4
    ctx.beginPath()
    let x = (rand() * size) | 0
    let y = (rand() * size) | 0
    ctx.moveTo(x, y)
    const segs = 2 + ((rand() * 3) | 0)
    for (let s = 0; s < segs; s++) {
      if (rand() < 0.5) x += ((rand() * 0.4 - 0.2) * size) | 0
      else y += ((rand() * 0.4 - 0.2) * size) | 0
      ctx.lineTo(x, y)
    }
    ctx.stroke()
  }
  const tex = new THREE.CanvasTexture(cv)
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping
  tex.repeat.set(6, 12)
  tex.colorSpace = THREE.SRGBColorSpace
  return tex
}
```

- [ ] **Step 2: Add the floor plane in `buildScene`** — a large `PlaneGeometry` rotated flat at y=0, `MeshBasicMaterial({map: floorTexture(rand)})`, registered in `disposables`. (Reflection is deferred to tuning — start with the textured plane.)

```javascript
  const floorTex = floorTexture(rand)
  const floorGeo = new THREE.PlaneGeometry(GRID.cols * GRID.spacing * 4, GRID.rows * GRID.spacing * 4)
  const floorMat = new THREE.MeshBasicMaterial({map: floorTex, fog: true})
  const floor = new THREE.Mesh(floorGeo, floorMat)
  floor.rotation.x = -Math.PI / 2
  scene.add(floor)
  disposables.push(floorGeo, floorMat, floorTex)
```

(Add `floorTexture` to the `textures.js` import in `scene.js`.)

- [ ] **Step 3: Build + SCREENSHOT CHECKPOINT** — review the floor traces with the human; tune trace density/colors/repeat and whether to add faint reflection.

- [ ] **Step 4: Commit**

```bash
git add assets/js/gibson/textures.js assets/js/gibson/scene.js
git commit -m "$(cat <<'EOF'
Add the glowing circuit-trace avenue floor

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: The landing — tower face echoes the menu, aligned crossfade

**Files:**
- Modify: `assets/js/gibson/textures.js` (add `menuFaceTexture`)
- Modify: `assets/js/gibson/scene.js` (texture the landing tower's face with it; expose the landing tower)

- [ ] **Step 1: Add `menuFaceTexture`** — like `dataFaceTexture` but with a left column of a few bright cyan horizontal bars (the link items) and a magenta block to their right (the readout), over faint data, so when the camera fills the face it reads as the menu silhouette.

- [ ] **Step 2: In `buildScene`, give the landing tower (`route.landing` cell) the menu face** on the side the camera approaches, and make sure the route's final waypoints aim the camera squarely at that face. Expose nothing new — the C1 crossfade already takes over on `onComplete`.

- [ ] **Step 3: Build + SCREENSHOT CHECKPOINT** — confirm the final frames dive into a face that resembles the menu, and that the crossfade to the real DOM menu lands cleanly (compare the last screenshot to the menu). Tune the dive distance/timing and the face layout to align.

- [ ] **Step 4: Commit**

```bash
git add assets/js/gibson/textures.js assets/js/gibson/scene.js
git commit -m "$(cat <<'EOF'
Land the flight on a tower face that echoes the menu silhouette

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Tuning passes + final verification

**Files:** `assets/js/gibson/*` (values only), as needed.

- [ ] **Step 1: Tuning loop** — with the human, iterate on the screenshot harness across several seeds: bloom strength/radius, fog density, tower height distribution and density, color balance (cyan-dominant with accents; option to shift greener), camera speed/banking, vanishing-point glow. Commit notable steps.

- [ ] **Step 2: Banking on turns** — add a slight camera roll into turns (lerp `camera.up` or set `camera.rotation.z` based on the curve tangent's x-rate). Screenshot-verify it reads on the turns without nausea.

- [ ] **Step 3: Performance check** — confirm a smooth ~60fps during the flight on a normal laptop (watch for jank in the live page, not just screenshots). If heavy: lower bloom resolution, cut tower count / draw distance via fog, drop floor reflection. Cap DPR at 2 (already done).

- [ ] **Step 4: Resource disposal audit** — verify `dispose()` releases every geometry, material, texture, render target (bloom), and the renderer. Add any missing to `disposables`. (This also closes the C1 follow-up about disposing scene resources, not just the renderer.)

- [ ] **Step 5: Full automated verification** — the C1 pipeline must still pass unchanged:

Run: `pnpm --dir assets test`
Expected: PASS (path generator + all C1 suites).

Re-run the C1 Playwright smoke logic against a running server (the temporary `gibson_smoke.mjs` from C1 Task 6, recreated from that plan if needed): `?intro` shows the canvas and ends with the DOM menu visible; repeat-visit and reduced-motion show no canvas. Expected: all pass. Remove the temporary smoke script afterward.

Run: `mix precommit`
Expected: clean.

- [ ] **Step 6: Manual eyeball (human)** — watch `/links?intro` several times in a real browser: the route varies each run, the city reads like the Gibson, SKIP/Esc/Space cut out cleanly, and a plain `/links` after the first view goes straight to the menu.

- [ ] **Step 7: Commit any final tuning**

```bash
git add assets/js/gibson
git commit -m "$(cat <<'EOF'
Tune the Gibson scene: bloom, fog, banking, color, and resource disposal

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## What C2 delivers

The real inside-the-Gibson cinematic: a glowing data-slab tower city over circuit-trace avenues, flown on a randomized two-turn route (different each run) that dives into a tower face which crossfades to the accessible DOM menu — all behind the unchanged C1 contract, so the gate, controller, seam, and their tests are untouched.

## Notes

- If `three/examples/jsm/postprocessing/*` import paths fail under esbuild, they resolve from the installed `three` package (`assets/node_modules/three/examples/jsm/...`); confirm the version path during Task 3's build.
- Keep the path generator (`path.js`) free of three.js so its test never needs WebGL.
