# /links Phase B — Pixel (mosaic) Transition — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a neon mosaic "pixelize" transition across the two site↔/links crossings: mosaic-out on click, a sessionStorage handoff across the full-document navigation, mosaic-in on arrival (and on `/links` direct loads).

**Architecture:** One JS module split into a **tested logic layer** (random-order generator, reduced-motion / should-play decision, the sessionStorage flag, and click interception — all pure, dependency-injected functions) and an **untested canvas layer** (the `requestAnimationFrame` block animation, which jsdom can't run). `initPixelTransition()` wires them together: a delegated document click listener for `a[data-pixel]` links, plus a mosaic-in on load when arriving via the transition or landing on `/links`.

**Tech Stack:** Vanilla JS (no deps), `<canvas>` 2D, vitest (jsdom), CSS.

**Context for the implementer:**
- Phase A shipped the static `/links` page. Phase C (the three.js cinematic) is a LATER plan — do NOT build it here. In Phase B the mosaic-in reveals the static menu directly.
- The two crossing links already carry `data-no-swup` (full-document navigation): the `Links` entry in `lib/newton_web/components/site_components.ex` (`site_nav/1`) and the `JN.SYS [HOME]` link in `lib/newton_web/controllers/links_html/index.html.heex`. This task adds `data-pixel` to those same two links.
- **Test pattern:** copy `assets/js/navigation.js` — exported functions take injectable `doc`/`win` (and here `storage`) params with defaults, so jsdom tests pass fakes. jsdom does NOT implement `HTMLCanvasElement.getContext` or `window.matchMedia`, so the canvas animation and `matchMedia` are only reachable through injected params and are not unit-tested.
- **app.js wiring:** page-specific JS is initialized in `assets/js/app.js`. The pixel controller installs ONE delegated document click listener and runs once at initial load — it must NOT be added to the Swup `content:replace` hook (that would stack duplicate listeners; the listener is delegated and persists, and mosaic-in only matters on full document loads).
- Swup ignores `data-no-swup` links entirely (its `ignoreVisit` returns true for them), so it will not fight the pixel controller for these clicks.
- Design spec: `docs/superpowers/specs/2026-06-24-links-page-phase-b-pixel-transition-design.md`.

**Module constants (used across tasks — keep identical):**

```javascript
const FLAG = "pixel-in"
const NEON = ["#19c9ff", "#ff31d9", "#b6ff00", "#8ff6ff"]
const SETTLE = "#05010a"
const BLOCK = 18 // px, fixed cell size; cell count scales with the viewport
const HALF_MS = 550 // duration of each half (out, in)
const FLASH_MS = 90 // how long a cell glows neon before settling/clearing
```

---

### Task 1: Pixel-transition logic module (tested)

**Files:**
- Create: `assets/js/pixel_transition.js` (logic layer only; canvas layer added in Task 2)
- Test: `assets/js/pixel_transition.test.js`

- [ ] **Step 1: Write the failing test**

Create `assets/js/pixel_transition.test.js`:

```javascript
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pnpm --dir assets test pixel_transition`
Expected: FAIL — `./pixel_transition` does not exist.

- [ ] **Step 3: Implement the logic layer**

Create `assets/js/pixel_transition.js`:

```javascript
// Neon mosaic page transition across the site<->/links crossings.
// This file's exported functions are the pure/logic layer (dependency-injected
// for testing). The canvas animation layer is added separately; jsdom cannot
// run <canvas>, so only this layer is unit-tested.

const FLAG = "pixel-in"

// Fisher-Yates shuffle of [0, count).
export function shuffledOrder(count, rand = Math.random) {
  const a = Array.from({length: count}, (_, i) => i)
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1))
    ;[a[i], a[j]] = [a[j], a[i]]
  }
  return a
}

export function prefersReducedMotion(win = window) {
  return win.matchMedia("(prefers-reduced-motion: reduce)").matches
}

// Should the destination page play a mosaic-in? Yes when we arrived via the
// transition (flag set) or we are on /links (covers direct loads / refreshes).
// Never when the user prefers reduced motion.
export function shouldMosaicIn(win = window, storage = win.sessionStorage) {
  if (prefersReducedMotion(win)) return false
  return storage.getItem(FLAG) === "1" || win.location.pathname === "/links"
}

// Read-and-clear the one-shot handoff flag.
export function consumeInFlag(storage = window.sessionStorage) {
  const had = storage.getItem(FLAG) === "1"
  storage.removeItem(FLAG)
  return had
}

// Click handler for a[data-pixel] links: set the handoff flag and run `out`
// (the canvas mosaic-out, injected by initPixelTransition). Leaves modifier and
// middle clicks alone so open-in-new-tab still works, and bails under
// reduced-motion so the browser navigates normally.
export function onPixelClick(event, {win = window, storage = win.sessionStorage, out} = {}) {
  if (event.defaultPrevented) return
  if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return

  const link = event.target.closest && event.target.closest("a[data-pixel]")
  if (!link) return
  if (prefersReducedMotion(win)) return

  event.preventDefault()
  storage.setItem(FLAG, "1")
  out(link.getAttribute("href"))
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `pnpm --dir assets test pixel_transition`
Expected: PASS (10 tests).

- [ ] **Step 5: Commit**

```bash
git add assets/js/pixel_transition.js assets/js/pixel_transition.test.js
git commit -m "$(cat <<'EOF'
Add the pixel-transition logic layer (order, gating, click handling)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Canvas animation + integration

**Files:**
- Modify: `assets/js/pixel_transition.js` (append the canvas layer + `initPixelTransition`)
- Modify: `assets/js/app.js` (import + init once on load)
- Modify: `assets/css/site.css` (the `.pixel-overlay` rule)
- Modify: `lib/newton_web/components/site_components.ex` (add `data-pixel` to the `Links` nav anchor)
- Modify: `lib/newton_web/controllers/links_html/index.html.heex` (add `data-pixel` to the `JN.SYS [HOME]` anchor)

This task is the effectful/visual layer. jsdom cannot run `<canvas>`, so there are no new unit tests here; correctness is confirmed by the existing suite staying green plus manual verification (Step 6).

- [ ] **Step 1: Append the canvas layer and wiring to `pixel_transition.js`**

Add the following constants near the top of `assets/js/pixel_transition.js` (below the existing `const FLAG = "pixel-in"`):

```javascript
const NEON = ["#19c9ff", "#ff31d9", "#b6ff00", "#8ff6ff"]
const SETTLE = "#05010a"
const BLOCK = 18 // px, fixed cell size; cell count scales with the viewport
const HALF_MS = 550 // duration of each half
const FLASH_MS = 90 // neon glow before a cell settles (out) or clears (in)
```

Then append the canvas layer and `initPixelTransition` to the END of the file:

```javascript
// --- canvas layer (not unit-tested: jsdom has no <canvas>) ---

function createOverlay(doc, win) {
  const canvas = doc.createElement("canvas")
  canvas.className = "pixel-overlay"
  canvas.setAttribute("aria-hidden", "true")
  canvas.width = win.innerWidth
  canvas.height = win.innerHeight
  doc.body.appendChild(canvas)
  return canvas
}

// Reveal (out) or clear (in) cells in `order` over HALF_MS, each cell flashing a
// random neon colour for FLASH_MS first. `direction` is "out" or "in".
function runMosaic(canvas, direction, win, done) {
  const ctx = canvas.getContext("2d")
  const cols = Math.ceil(canvas.width / BLOCK)
  const rows = Math.ceil(canvas.height / BLOCK)
  const order = shuffledOrder(cols * rows)
  const total = order.length
  const active = new Map() // index -> {at, color}

  if (direction === "in") {
    ctx.fillStyle = SETTLE
    ctx.fillRect(0, 0, canvas.width, canvas.height)
  }

  const start = win.performance.now()
  function frame(now) {
    const t = Math.min(1, (now - start) / HALF_MS)
    const target = Math.floor(t * total)
    while (active.size < target) {
      const idx = order[active.size]
      active.set(idx, {at: now, color: NEON[Math.floor(Math.random() * NEON.length)]})
    }

    let glowing = false
    active.forEach(({at, color}, idx) => {
      const x = (idx % cols) * BLOCK
      const y = Math.floor(idx / cols) * BLOCK
      const flash = now - at < FLASH_MS
      if (flash) glowing = true
      if (direction === "out") {
        ctx.fillStyle = flash ? color : SETTLE
        ctx.fillRect(x, y, BLOCK, BLOCK)
      } else if (flash) {
        ctx.fillStyle = color
        ctx.fillRect(x, y, BLOCK, BLOCK)
      } else {
        ctx.clearRect(x, y, BLOCK, BLOCK)
      }
    })

    if (t < 1 || glowing) {
      win.requestAnimationFrame(frame)
    } else {
      done()
    }
  }
  win.requestAnimationFrame(frame)
}

export function pixelOut(href, {doc = document, win = window} = {}) {
  const canvas = createOverlay(doc, win)
  runMosaic(canvas, "out", win, () => {
    win.location.href = href
  })
}

export function pixelIn({doc = document, win = window} = {}) {
  const canvas = createOverlay(doc, win)
  runMosaic(canvas, "in", win, () => canvas.remove())
}

// Install the delegated click listener and run a mosaic-in if we arrived via the
// transition or landed on /links. Call once per full document load.
export function initPixelTransition({doc = document, win = window, storage = win.sessionStorage} = {}) {
  doc.addEventListener("click", (event) =>
    onPixelClick(event, {win, storage, out: (href) => pixelOut(href, {doc, win})})
  )

  if (shouldMosaicIn(win, storage)) {
    consumeInFlag(storage)
    pixelIn({doc, win})
  }
}
```

- [ ] **Step 2: Wire it into `app.js`**

In `assets/js/app.js`, add the import alongside the other page-specific imports (near `import {initLinks} from "./links"`):

```javascript
import {initPixelTransition} from "./pixel_transition"
```

Then, in the initial-load section (where `initPhotos()` / `initLinks()` are already called once, after the `swup` setup), add a single init call. Do NOT add it to the `content:replace` hook:

```javascript
// Initial page load (Swup doesn't fire content:replace for the first page).
initPhotos()
initLinks()
initPixelTransition()
scrollToHash()
```

- [ ] **Step 3: Add the overlay CSS**

In `assets/css/site.css`, add this rule (anywhere among the top-level rules; near the `.ripple-canvas` rule is a sensible home):

```css
/* Full-viewport overlay for the /links mosaic page transition. Above all page
   content; never interactive. */
.pixel-overlay {
  position: fixed;
  inset: 0;
  z-index: 9999;
  pointer-events: none;
}
```

- [ ] **Step 4: Opt the two crossing links into the transition**

In `lib/newton_web/components/site_components.ex`, add `data-pixel` to the `Links` anchor (it already has `data-no-swup`):

```heex
      <a href="/links" data-no-swup data-pixel>Links</a>
```

In `lib/newton_web/controllers/links_html/index.html.heex`, add `data-pixel` to the home anchor (it already has `data-no-swup`):

```heex
        <a
          class="links-item links-item--home"
          href={~p"/"}
          data-no-swup
          data-pixel
          data-name="JN.SYS"
          data-url="/"
          data-desc="Disconnect. Return to jamesnewton.com."
        >
```

- [ ] **Step 5: Run the full JS + Elixir suites to confirm nothing broke**

Run: `pnpm --dir assets test`
Expected: PASS (all suites, including `pixel_transition` from Task 1).

Run: `mix test`
Expected: PASS (no Elixir behavior changed; the template/nav edits only add an attribute).

- [ ] **Step 6: Manual verification**

Build assets and start the server on the alternate port:
Run: `PORT=4001 mix phx.server`

Verify in a browser at `http://localhost:4001`:
1. Click **Links** in the nav → the screen dissolves into neon blocks, then resolves into the `/links` menu (no white flash, no header bleed). **Watch specifically for a flash of the destination page _before_ the mosaic-in covers it** — see "Known risk" below.
2. On `/links`, click **JN.SYS [HOME]** → it dissolves back out and resolves on the home page.
3. Reload `/links` directly → it mosaics-in on its own.
4. Enable "Reduce motion" at the OS level and repeat 1–3 → navigations happen instantly with no mosaic and no errors.
5. Cmd/Ctrl-click **Links** → opens `/links` in a new tab with no mosaic on the current tab.

- [ ] **Step 7: Commit**

```bash
git add assets/js/pixel_transition.js assets/js/app.js assets/css/site.css lib/newton_web/components/site_components.ex lib/newton_web/controllers/links_html/index.html.heex
git commit -m "$(cat <<'EOF'
Add the neon mosaic canvas transition across the site/links crossings

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Final verification

- [ ] **Run the full JS suite**

Run: `pnpm --dir assets test`
Expected: PASS (including `pixel_transition.test.js`).

- [ ] **Run precommit**

Run: `mix precommit`
Expected: clean (format, compile warnings-as-errors, tests, Dialyzer).

---

## What Phase B delivers

Clicking between the main site and `/links` (either direction) pixel-dissolves through a fine neon mosaic instead of a plain page load; `/links` also mosaics-in on direct loads. The effect is fully bypassed under `prefers-reduced-motion`, leaves modifier/middle clicks alone, and degrades to ordinary `<a href>` navigation with no JS.

## Known risk: pre-cover flash on the destination

`app.js` is loaded with `defer`, so on the destination page the browser may
paint the page once before `initPixelTransition()` runs and the "in" overlay
covers it — a possible sub-frame flash of the destination before the mosaic-in.
In practice the defer script runs within a few milliseconds of parse, so this is
usually imperceptible. Confirm in Step 6, item 1. **If it is noticeable**, the
fix (a follow-up, not part of this plan) is a tiny render-blocking inline style
in the `<head>` of `root.html.heex` that paints a full-screen cover whenever the
path is `/links` (or a `pixel-in` marker is present), which `initPixelTransition`
then animates away. Left out here as YAGNI until observed.

## Deferred to Phase C (NOT in this plan)

- The three.js cinematic fly-through. When built, it will hook the mosaic-in's completion (the `done()` seam in `runMosaic` / `pixelIn`) so the mosaic resolves into the fly-through, which then lands on the menu.
