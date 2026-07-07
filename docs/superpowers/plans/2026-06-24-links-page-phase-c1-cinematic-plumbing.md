# /links Phase C1 — Cinematic Plumbing/Skeleton — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the entire first-visit cinematic pipeline — gating, lazy three.js delivery, the mosaic-in handoff, skip + `?intro` replay, and fallbacks — driving a **minimal placeholder scene** that crossfades to the menu. (The real Gibson art is Phase C2.)

**Architecture:** Three small always-present modules in the `app.js` bundle — `gibson_gate.js` (pure gating + WebGL detection), a one-function seam added to `pixel_transition.js`, and `gibson_intro.js` (the effectful controller) — plus a separately-bundled, lazily-injected `gibson.js` esbuild entry that imports three.js and renders the scene. The controller gates on first-visit/`?intro`/reduced-motion/WebGL, injects the bundle behind the Phase B mosaic cover, hooks the mosaic-in completion to start the flight, then crossfades the canvas out to reveal the real DOM menu.

**Tech Stack:** Vanilla JS, three.js (new dep), esbuild (new entry), vitest (jsdom), CSS, Playwright (smoke).

**Context for the implementer:**
- Phases A and B shipped. Phase A: the static `/links` menu (DOM). Phase B: `assets/js/pixel_transition.js` — a neon mosaic page transition; on `/links` it plays a mosaic-in whose `pixelIn` removes its canvas on completion, revealing the DOM menu. THIS plan inserts the cinematic between that mosaic-in and the menu, on first visit only.
- jsdom cannot run `<canvas>`/WebGL or `matchMedia`. Follow the established pattern (`assets/js/navigation.js`, `assets/js/pixel_transition.js`): pure functions take injectable `win`/`storage`/`doc` params with defaults so jsdom tests pass fakes; effectful canvas/three.js code is verified by build + a Playwright smoke, not unit tests.
- JS deps use **pnpm**. esbuild config is in `config/config.exs` under `config :esbuild` (currently `args: ~w(js/app.js js/admin.js --bundle ...)`). `mix assets.build` runs `esbuild newton`; `assets.deploy` runs `esbuild newton --minify`. A second entry (`admin.js`) already exists — adding a third is the same pattern.
- `assets/js/app.js` initializes page JS once on initial load (`initPhotos()`, `initLinks()`, `initPixelTransition()`).
- The cinematic state flag persists across sessions, so it uses **localStorage** (key `gibson-seen`). Phase B's `pixel-in` flag is sessionStorage — different store, intentional.
- Design spec: `docs/superpowers/specs/2026-06-24-links-page-phase-c-cinematic-design.md`.

**Shared contract (keep identical across tasks):**
- The lazy bundle defines `window.__gibsonRun(canvas, {onComplete})` which builds the scene on `canvas`, renders frame 0 immediately, and returns a control object `{start(), skip()}`. `start()` runs the camera move; `skip()` jumps to the end; `onComplete()` fires exactly once when the move finishes or is skipped.
- The seam: `setMosaicInHook(fn)` (in `pixel_transition.js`) registers a one-shot callback fired when the next mosaic-in finishes.

---

### Task 1: Gating logic + WebGL detection (`gibson_gate.js`)

**Files:**
- Create: `assets/js/gibson_gate.js`
- Test: `assets/js/gibson_gate.test.js`

- [ ] **Step 1: Write the failing test**

```javascript
// assets/js/gibson_gate.test.js
import {describe, it, expect} from "vitest"
import {hasWebGL, shouldPlayCinematic, markGibsonSeen} from "./gibson_gate"

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
})

describe("shouldPlayCinematic", () => {
  const doc = fakeDoc(true)

  it("plays on a first visit (flag unset, WebGL, motion ok)", () => {
    expect(shouldPlayCinematic(fakeWin(), fakeStorage(), doc)).toBe(true)
  })
  it("does not play on a repeat visit (flag set)", () => {
    expect(shouldPlayCinematic(fakeWin(), fakeStorage({"gibson-seen": "1"}), doc)).toBe(false)
  })
  it("?intro forces it even when the flag is set", () => {
    expect(shouldPlayCinematic(fakeWin({search: "?intro"}), fakeStorage({"gibson-seen": "1"}), doc)).toBe(true)
  })
  it("never plays under reduced-motion", () => {
    expect(shouldPlayCinematic(fakeWin({reduced: true, search: "?intro"}), fakeStorage(), doc)).toBe(false)
  })
  it("never plays without WebGL", () => {
    expect(shouldPlayCinematic(fakeWin({search: "?intro"}), fakeStorage(), fakeDoc(false))).toBe(false)
  })
})

describe("markGibsonSeen", () => {
  it("sets the persistent flag", () => {
    const s = fakeStorage()
    markGibsonSeen(s)
    expect(s.getItem("gibson-seen")).toBe("1")
  })
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pnpm --dir assets test gibson_gate`
Expected: FAIL — `./gibson_gate` does not exist.

- [ ] **Step 3: Implement the module**

```javascript
// assets/js/gibson_gate.js
// Pure decisions for the /links cinematic. Dependency-injected for testing;
// jsdom can't make a real WebGL context, so `doc` is injectable.
import {prefersReducedMotion} from "./pixel_transition"

const SEEN = "gibson-seen"

export function hasWebGL(doc = document) {
  try {
    const c = doc.createElement("canvas")
    return !!(c.getContext("webgl2") || c.getContext("webgl"))
  } catch {
    return false
  }
}

// Play only on a first visit (or forced via ?intro), with motion allowed and
// WebGL available.
export function shouldPlayCinematic(win = window, storage = win.localStorage, doc = document) {
  if (prefersReducedMotion(win)) return false
  if (!hasWebGL(doc)) return false
  if (new URLSearchParams(win.location.search).has("intro")) return true
  return storage.getItem(SEEN) !== "1"
}

export function markGibsonSeen(storage = window.localStorage) {
  storage.setItem(SEEN, "1")
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `pnpm --dir assets test gibson_gate`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add assets/js/gibson_gate.js assets/js/gibson_gate.test.js
git commit -m "$(cat <<'EOF'
Add the Gibson cinematic gating (first-visit/?intro, reduced-motion, WebGL)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Mosaic-in completion seam in `pixel_transition.js`

**Files:**
- Modify: `assets/js/pixel_transition.js`
- Test: `assets/js/pixel_transition.test.js` (add a describe block)

This exposes the seam the spec calls for: a one-shot hook fired when the mosaic-in finishes, so Phase C can take over the reveal. Phase B's default behavior (remove canvas → reveal whatever's beneath) is unchanged when no hook is registered.

- [ ] **Step 1: Write the failing test**

Append to `assets/js/pixel_transition.test.js`:

```javascript
import {setMosaicInHook, finishMosaicIn} from "./pixel_transition"

describe("mosaic-in completion seam", () => {
  it("fires a registered hook once when the mosaic-in finishes, then clears it", () => {
    let calls = 0
    setMosaicInHook(() => (calls += 1))
    finishMosaicIn({remove: () => {}})
    finishMosaicIn({remove: () => {}}) // hook already consumed
    expect(calls).toBe(1)
  })

  it("removes the canvas on finish even with no hook", () => {
    let removed = false
    finishMosaicIn({remove: () => (removed = true)})
    expect(removed).toBe(true)
  })
})
```

(Add `setMosaicInHook, finishMosaicIn` to the existing `import {...} from "./pixel_transition"` line at the top of the test file rather than a second import, if you prefer — either works.)

- [ ] **Step 2: Run the test to verify it fails**

Run: `pnpm --dir assets test pixel_transition`
Expected: FAIL — `setMosaicInHook`/`finishMosaicIn` are not exported.

- [ ] **Step 3: Implement the seam**

In `assets/js/pixel_transition.js`, just below the `let running = false` line, add:

```javascript
// One-shot hook fired when the next mosaic-in finishes. Phase C registers this
// to take over the reveal (run the cinematic) instead of showing the menu
// directly. Null by default, so Phase B just removes the canvas.
let mosaicInHook = null
export function setMosaicInHook(fn) {
  mosaicInHook = fn
}

// Completion of a mosaic-in: remove the cover, release the run-guard, and fire
// (and clear) the one-shot hook if registered.
export function finishMosaicIn(canvas) {
  canvas.remove()
  running = false
  const hook = mosaicInHook
  mosaicInHook = null
  if (hook) hook()
}
```

Then change `pixelIn` to use it — replace its `runMosaic` completion callback:

```javascript
export function pixelIn({doc = document, win = window} = {}) {
  if (running) return
  running = true
  const canvas = createOverlay(doc, win)
  runMosaic(canvas, "in", win, () => finishMosaicIn(canvas))
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `pnpm --dir assets test pixel_transition`
Expected: PASS (the existing 14 plus 2 new = 16).

- [ ] **Step 5: Commit**

```bash
git add assets/js/pixel_transition.js assets/js/pixel_transition.test.js
git commit -m "$(cat <<'EOF'
Expose a mosaic-in completion seam for the Phase C cinematic handoff

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: three.js delivery — the lazy `gibson.js` bundle + placeholder scene

**Files:**
- Modify: `assets/package.json` (via `pnpm add three`)
- Create: `assets/js/gibson.js`
- Modify: `config/config.exs` (add `js/gibson.js` to the esbuild args)

- [ ] **Step 1: Install three.js**

Run: `pnpm --dir assets add three`
Expected: `three` appears in `assets/package.json` dependencies; `pnpm-lock.yaml` updated.

- [ ] **Step 2: Add the esbuild entry**

In `config/config.exs`, change the esbuild `args` line to include `js/gibson.js`:

```elixir
    args:
      ~w(js/app.js js/admin.js js/gibson.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
```

(The `assets.deploy` minify step runs the same `esbuild newton` task, so it picks up the new entry automatically.)

- [ ] **Step 3: Create the placeholder scene bundle**

```javascript
// assets/js/gibson.js
// Lazily-loaded WebGL bundle (its own esbuild entry → /assets/js/gibson.js).
// Phase C1 ships a PLACEHOLDER scene (a few neon boxes + a short camera move) to
// prove the pipeline; Phase C2 replaces the scene body with the real Gibson.
//
// Contract: window.__gibsonRun(canvas, {onComplete}) -> {start, skip}
//   - builds the scene on `canvas` and renders frame 0 immediately
//   - start() runs the camera move; skip() jumps to the end
//   - onComplete() fires exactly once, when the move finishes or is skipped
import * as THREE from "three"

window.__gibsonRun = function (canvas, {onComplete}) {
  const w = window.innerWidth
  const h = window.innerHeight

  const renderer = new THREE.WebGLRenderer({canvas, antialias: true})
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2))
  renderer.setSize(w, h, false)
  renderer.setClearColor(0x020207, 1)

  const scene = new THREE.Scene()
  const camera = new THREE.PerspectiveCamera(60, w / h, 0.1, 1000)
  const startPos = new THREE.Vector3(0, 6, 14)
  const endPos = new THREE.Vector3(0, 0.5, 3)
  camera.position.copy(startPos)
  camera.lookAt(0, 0, 0)

  const colors = [0x19c9ff, 0xff31d9, 0xb6ff00]
  const boxes = colors.map((c, i) => {
    const mesh = new THREE.Mesh(
      new THREE.BoxGeometry(1, 2.4, 1),
      new THREE.MeshBasicMaterial({color: c}),
    )
    mesh.position.set((i - 1) * 2.2, 0, 0)
    scene.add(mesh)
    return mesh
  })

  const render = () => renderer.render(scene, camera)
  render() // frame 0

  const DURATION = 1600
  let raf = null
  let startTime = null
  let done = false

  function finish() {
    if (done) return
    done = true
    if (raf) cancelAnimationFrame(raf)
    renderer.dispose()
    onComplete()
  }

  function frame(now) {
    if (startTime === null) startTime = now
    const t = Math.min(1, (now - startTime) / DURATION)
    const e = t * t * (3 - 2 * t) // smoothstep
    camera.position.lerpVectors(startPos, endPos, e)
    camera.lookAt(0, 0, 0)
    boxes.forEach((b, i) => (b.rotation.y = e * Math.PI * (i + 1)))
    render()
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

- [ ] **Step 4: Verify it builds**

Run: `mix assets.build`
Expected: succeeds; `priv/static/assets/js/gibson.js` is produced and includes the three.js code (file size noticeably larger than the source).

Run: `pnpm --dir assets test`
Expected: PASS (no test imports `gibson.js`, so suites are unaffected).

- [ ] **Step 5: Commit**

```bash
git add assets/package.json assets/pnpm-lock.yaml assets/js/gibson.js config/config.exs
git commit -m "$(cat <<'EOF'
Add the lazily-bundled three.js gibson entry with a placeholder scene

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: The Gibson controller — gate, inject, coordinate, crossfade

**Files:**
- Create: `assets/js/gibson_intro.js`
- Modify: `assets/js/app.js` (import + init once on initial load)
- Modify: `assets/css/site.css` (the `.gibson-canvas` rule)

This is the effectful orchestrator (no jsdom unit test; verified by build + the Task 6 smoke). SKIP is added in Task 5.

- [ ] **Step 1: Create the controller**

```javascript
// assets/js/gibson_intro.js
// Owns the /links first-visit cinematic. Decides whether to play, injects the
// lazy three.js bundle behind the Phase B mosaic cover, starts the flight when
// the cover clears AND the scene is ready, then crossfades the canvas out to
// reveal the real DOM menu. Effectful (canvas/three.js); not unit-tested.
import {shouldPlayCinematic, markGibsonSeen} from "./gibson_gate"
import {setMosaicInHook} from "./pixel_transition"

const BUNDLE = "/assets/js/gibson.js"
const FADE_MS = 400

function injectBundle(doc, win) {
  return new Promise((resolve, reject) => {
    if (win.__gibsonRun) return resolve()
    const s = doc.createElement("script")
    s.src = BUNDLE
    s.defer = true
    s.onload = () => resolve()
    s.onerror = () => reject(new Error("gibson bundle failed to load"))
    doc.head.appendChild(s)
  })
}

export function initGibsonIntro({doc = document, win = window, storage = win.localStorage} = {}) {
  if (win.location.pathname !== "/links") return
  if (!shouldPlayCinematic(win, storage, doc)) return

  const canvas = doc.createElement("canvas")
  canvas.className = "gibson-canvas"
  canvas.setAttribute("aria-hidden", "true")
  doc.body.appendChild(canvas)

  let mosaicDone = false
  let control = null
  let started = false

  function maybeStart() {
    if (mosaicDone && control && !started) {
      started = true
      control.start()
    }
  }

  function finish() {
    markGibsonSeen(storage)
    canvas.style.transition = `opacity ${FADE_MS}ms ease`
    canvas.style.opacity = "0"
    win.setTimeout(() => canvas.remove(), FADE_MS)
  }

  // Take over the reveal: when the mosaic-in clears, the scene (built behind it)
  // takes the screen. Start the flight once both the cover is gone and the
  // bundle is ready.
  setMosaicInHook(() => {
    mosaicDone = true
    maybeStart()
  })

  injectBundle(doc, win)
    .then(() => {
      control = win.__gibsonRun(canvas, {onComplete: finish})
      maybeStart()
    })
    .catch(() => {
      // Bundle failed: drop the canvas and let the DOM menu show.
      canvas.remove()
    })
}
```

- [ ] **Step 2: Wire it into `app.js`**

Add the import near the other page-specific imports:

```javascript
import {initGibsonIntro} from "./gibson_intro"
```

In the initial-load section, call it once AFTER `initPixelTransition()` (order is not critical — the seam is registered synchronously, well before the ~550ms mosaic-in completes — but keep it adjacent for readability):

```javascript
initPhotos()
initLinks()
initPixelTransition()
initGibsonIntro()
scrollToHash()
```

- [ ] **Step 3: Add the canvas CSS**

In `assets/css/site.css`, near the `.pixel-overlay` rule, add:

```css
/* The /links cinematic canvas. Sits above the page (and the DOM menu) but BELOW
   the mosaic overlay (z 9999), so the mosaic-in reveals the scene; it then
   crossfades out to show the menu. Never interactive. */
.gibson-canvas {
  position: fixed;
  inset: 0;
  z-index: 9000;
  pointer-events: none;
}
```

- [ ] **Step 4: Build + test**

Run: `mix assets.build`
Expected: succeeds, no errors.

Run: `pnpm --dir assets test`
Expected: PASS (unchanged suites).

- [ ] **Step 5: Commit**

```bash
git add assets/js/gibson_intro.js assets/js/app.js assets/css/site.css
git commit -m "$(cat <<'EOF'
Wire the /links cinematic controller: gate, inject, mosaic handoff, crossfade

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: SKIP control (button + Esc/Space)

**Files:**
- Modify: `assets/js/gibson_intro.js` (add the skip affordance)
- Modify: `assets/css/site.css` (the `.gibson-skip` rule)

- [ ] **Step 1: Add the skip UI + keyboard handling to the controller**

In `assets/js/gibson_intro.js`, add a `doSkip` path and a focusable button. Replace **everything in `initGibsonIntro` after the `doc.body.appendChild(canvas)` line** (i.e. the entire `let mosaicDone ... injectBundle(...).catch(...)` block from Task 4) with the block below. The module-level `injectBundle`/`BUNDLE`/`FADE_MS`, the imports, and the early-return guards + `canvas` creation above this point stay unchanged:

```javascript
  const skipBtn = doc.createElement("button")
  skipBtn.type = "button"
  skipBtn.className = "gibson-skip"
  skipBtn.textContent = "SKIP ▸"
  doc.body.appendChild(skipBtn)

  let mosaicDone = false
  let control = null
  let started = false
  let finished = false

  function cleanupSkipUi() {
    skipBtn.remove()
    win.removeEventListener("keydown", onKey)
  }

  function finish() {
    if (finished) return
    finished = true
    cleanupSkipUi()
    markGibsonSeen(storage)
    canvas.style.transition = `opacity ${FADE_MS}ms ease`
    canvas.style.opacity = "0"
    win.setTimeout(() => canvas.remove(), FADE_MS)
  }

  function maybeStart() {
    if (mosaicDone && control && !started) {
      started = true
      control.start()
    }
  }

  function doSkip() {
    if (control) control.skip() // skip() -> onComplete -> finish()
    else finish() // not loaded yet: just reveal the menu
  }

  function onKey(e) {
    if (e.key === "Escape" || e.key === " " || e.code === "Space") {
      e.preventDefault()
      doSkip()
    }
  }

  skipBtn.addEventListener("click", doSkip)
  win.addEventListener("keydown", onKey)

  setMosaicInHook(() => {
    mosaicDone = true
    maybeStart()
  })

  injectBundle(doc, win)
    .then(() => {
      control = win.__gibsonRun(canvas, {onComplete: finish})
      maybeStart()
    })
    .catch(() => {
      cleanupSkipUi()
      canvas.remove()
    })
```

(Note: `finish` is now guarded by `finished` so the skip-then-complete or double-skip paths each only crossfade once. Keep the earlier `canvas`, `markGibsonSeen`, `injectBundle`, and the early-return guards above unchanged.)

- [ ] **Step 2: Add the skip button CSS**

In `assets/css/site.css`, after `.gibson-canvas`, add:

```css
/* Skip affordance shown during the cinematic. Above the canvas; the only
   interactive element of the intro. */
.gibson-skip {
  position: fixed;
  right: 20px;
  bottom: 20px;
  z-index: 9001;
  font-family: "SF Mono", "Courier New", monospace;
  font-size: 12px;
  letter-spacing: 0.15em;
  color: #8ff6ff;
  background: rgba(2, 2, 7, 0.6);
  border: 1px solid #19c9ff;
  box-shadow: 0 0 10px rgba(0, 229, 255, 0.3);
  padding: 6px 12px;
  cursor: pointer;
  transition: color 0.1s ease, border-color 0.1s ease;
}

.gibson-skip:hover,
.gibson-skip:focus-visible {
  color: #ff5cc8;
  border-color: #ff31d9;
  box-shadow: 0 0 12px rgba(255, 49, 217, 0.4);
  outline: none;
}
```

- [ ] **Step 3: Build + test**

Run: `mix assets.build`
Expected: succeeds.

Run: `pnpm --dir assets test`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add assets/js/gibson_intro.js assets/css/site.css
git commit -m "$(cat <<'EOF'
Add a skippable SKIP control (button + Esc/Space) to the /links cinematic

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Verification (automated + smoke)

**Files:** none committed (the smoke script is temporary, mirroring how Phase B was verified).

- [ ] **Step 1: Full suites**

Run: `pnpm --dir assets test`
Expected: PASS (gibson_gate + pixel_transition seam tests included).

Run: `mix precommit`
Expected: clean (format, compile warnings-as-errors, tests, Dialyzer).

- [ ] **Step 2: Playwright smoke against a running server**

Start the server yourself if not running: `PORT=4001 mix phx.server` (use the existing one if already up; note its port).

Create `assets/gibson_smoke.mjs`:

```javascript
import {chromium} from "playwright"

const BASE = process.env.BASE_URL ?? "http://localhost:4000"
const results = []
const check = (name, cond, detail = "") => {
  results.push(cond)
  console.log(`${cond ? "PASS" : "FAIL"}  ${name}${detail ? "  — " + detail : ""}`)
}

const observerInit = `
  window.__sawCanvas = false
  new MutationObserver((muts) => {
    for (const m of muts) for (const n of m.addedNodes) {
      if (n.nodeType === 1 && n.matches && n.matches("canvas.gibson-canvas")) window.__sawCanvas = true
    }
  }).observe(document, {childList: true, subtree: true})
`

async function sawCanvas(page) {
  let saw = false
  for (let i = 0; i < 40 && !saw; i++) {
    saw = await page.evaluate(
      () => window.__sawCanvas || !!document.querySelector("canvas.gibson-canvas"),
    )
    if (!saw) await page.waitForTimeout(50)
  }
  return saw
}

const browser = await chromium.launch()
try {
  // 1. ?intro forces the cinematic (canvas appears), and the menu ends visible.
  {
    const ctx = await browser.newContext()
    await ctx.addInitScript(observerInit)
    const page = await ctx.newPage()
    await page.goto(`${BASE}/links?intro`, {waitUntil: "domcontentloaded"})
    check("?intro shows the gibson canvas", await sawCanvas(page))
    await page.waitForTimeout(3500)
    const menuVisible = await page.evaluate(() => {
      const el = document.querySelector(".links-menu")
      return !!el && getComputedStyle(el).display !== "none"
    })
    check("?intro ends with the DOM menu visible", menuVisible)
    await ctx.close()
  }

  // 2. A repeat visit (flag pre-set) shows NO cinematic.
  {
    const ctx = await browser.newContext()
    await ctx.addInitScript(observerInit)
    await ctx.addInitScript(`try { localStorage.setItem("gibson-seen", "1") } catch (e) {}`)
    const page = await ctx.newPage()
    await page.goto(`${BASE}/links`, {waitUntil: "domcontentloaded"})
    await page.waitForTimeout(900)
    check("repeat visit shows no gibson canvas", (await page.evaluate(() => window.__sawCanvas)) === false)
    await ctx.close()
  }

  // 3. Reduced-motion never plays the cinematic (even with ?intro).
  {
    const ctx = await browser.newContext({reducedMotion: "reduce"})
    await ctx.addInitScript(observerInit)
    const page = await ctx.newPage()
    await page.goto(`${BASE}/links?intro`, {waitUntil: "domcontentloaded"})
    await page.waitForTimeout(900)
    check("reduced-motion shows no gibson canvas", (await page.evaluate(() => window.__sawCanvas)) === false)
    await ctx.close()
  }
} finally {
  await browser.close()
}
const failed = results.filter((r) => !r).length
console.log(`\n${results.length - failed}/${results.length} checks passed`)
process.exit(failed ? 1 : 0)
```

Run: `cd assets && pnpm exec node gibson_smoke.mjs` (set `BASE_URL=http://localhost:4001` if using the alt port)
Expected: `5/5 checks passed`.

- [ ] **Step 3: Remove the temporary smoke script**

Run: `rm assets/gibson_smoke.mjs`

- [ ] **Step 4: Manual eyeball (human)**

Visit `/links?intro` in a browser: the mosaic resolves into the placeholder scene (neon boxes), the camera moves briefly, then it crossfades to the menu. Confirm SKIP (and Esc/Space) cut to the menu, and that a plain reload of `/links` (after the first view) goes straight to the menu.

---

## What C1 delivers

The complete first-visit cinematic pipeline driving a placeholder scene: gating (first-visit/`?intro`, reduced-motion, WebGL), lazy three.js delivery off the main bundle, the mosaic-in handoff, a skippable flight, the crossfade to the accessible DOM menu, and all fallbacks — unit-tested where logic lives, smoke-tested end to end.

## Deferred to Phase C2 (NOT in this plan)

- Replace the placeholder scene body in `assets/js/gibson.js` (inside `__gibsonRun`) with the real Gibson: extruded towers, circuit-trace roads, emissive neon, `UnrealBloomPass`, the CatmullRom camera path, and the tower-face landing that echoes the menu silhouette. The `window.__gibsonRun(canvas, {onComplete}) -> {start, skip}` contract stays the same, so no controller/gate changes are needed.
