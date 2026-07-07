# /links Phase C — the three.js Gibson cinematic (design)

**Status:** Approved design, pending implementation plans.
**Date:** 2026-06-24
**Builds on:** Phase A (static `/links` menu) and Phase B (the mosaic page transition).

## Goal

On a visitor's first arrival at `/links`, the mosaic-in resolves into a WebGL
"Gibson" fly-through: the camera drops into a neon data-tower city, flies a
curve between the towers, and into the final tower's face — which crossfades to
the real menu. The effect is an additive enhancement over the Phase A/B base:
reduced-motion, no-WebGL, and repeat visits all skip it and get the menu
directly.

## When it plays (gating)

Play the cinematic only when ALL of:

- **First visit** — a `localStorage` flag (e.g. `gibson-seen`) is unset — **OR**
  the URL has `?intro` (forces it regardless of the flag).
- **Not** `prefers-reduced-motion`.
- **WebGL is available** (a `webgl2`/`webgl` context can be created).

Otherwise, fall through to the Phase B behavior unchanged (mosaic-in → menu),
and three.js is never loaded.

After a successful (un-skipped or skipped) play triggered by the first-visit
flag, set `localStorage["gibson-seen"] = "1"`. A play forced by `?intro` does
not need to set or depend on the flag.

## First-visit flow

1. `/links` loads under the Phase B mosaic cover (the page starts covered).
2. **Behind the cover**, the Gibson controller lazily loads `gibson.js`, builds
   the scene, and renders frame 0 (camera high above the city). The mosaic cover
   hides this load + build — there is no separate spinner.
3. The Phase B mosaic-in clears the cover, revealing the scene's first frame.
4. The camera animates along its curve, between the towers, and into the final
   tower's face (~4–5s, eased).
5. The final tower's emissive face (shaped to echo the menu silhouette)
   crossfades (~400ms) to the real DOM menu; the canvas is removed; the
   `gibson-seen` flag is set.

**Slow-load safety:** if three.js / the scene is not ready when the mosaic-in
finishes, hold on the covered (or frame-0) state until ready, then start the
flight. A slow connection never shows a broken half-state.

## three.js delivery

- `pnpm add three` (managed with pnpm, bundled by esbuild — not hand-vendored).
- A new esbuild **entry point** `assets/js/gibson.js` producing
  `priv/static/assets/js/gibson.js` — its own bundle with three.js + the scene
  inside, mirroring the existing `js/admin.js` second entry. Added to the
  `:esbuild` args in `config/config.exs` and to the `assets.deploy` minify step.
- The bundle is injected via an **on-demand `<script>`** created by the Gibson
  controller, ONLY when the cinematic will actually play. So three.js is
  downloaded essentially never except that one first visit.

## The scene (procedural — no downloaded 3D assets)

- Extruded **chip/tower** geometry and circuit-trace ground "roads."
- Emissive neon materials in the locked palette: cyan `#19c9ff`, magenta
  `#ff31d9`, acid green `#b6ff00`.
- **`UnrealBloomPass`** post-processing for the glow.
- Camera animated along a **CatmullRom curve** through the towers and into the
  final tower's face.
- The final tower's face is an emissive panel shaped to echo the menu silhouette
  (cyan bars where the link items sit, a magenta block where the readout sits) so
  the crossfade to the DOM menu lands cleanly ("the tower becomes the menu").
- The DOM menu (Phase A) is the real menu; the tower-face morph is decorative.
  WebGL never renders the actual link text.

The precise look (tower density, road detail, camera path, bloom strength,
timing) is the iterative focus of plan C2.

## Skip & replay

- A subtle `SKIP ▸` control in a corner during the flight. **Esc** and **Space**
  also skip. Skipping jumps straight to the crossfade → menu (and still sets the
  `gibson-seen` flag if this was a first-visit play).
- `/links?intro` forces the full cinematic regardless of `gibson-seen` — for
  demos, sharing, and deterministic QA.

## Integration with Phase B

A **Gibson controller** (new module, loaded by the on-demand `gibson.js`, with a
small gate in the always-present bundle) owns `/links`:

- The always-present code decides cinematic-vs-not (the gating above). If yes, it
  injects `gibson.js` and coordinates with the **mosaic-in completion seam** —
  the `done()` callback in Phase B's `pixelIn` — so the flight starts as the
  cover clears, then crossfades to the menu.
- If no, Phase B's mosaic-in → menu path is unchanged.

This requires exposing the Phase B seam: `pixelIn` currently just removes its
canvas on completion. Phase C makes that completion hookable (a callback /
custom event) without changing Phase B's default behavior.

## Accessibility

- The DOM menu (Phase A) is always present and is the accessible source of truth.
- The WebGL `<canvas>` is `aria-hidden="true"` and `pointer-events: none` (except
  the SKIP control, which is a real focusable button).
- `prefers-reduced-motion` and no-WebGL visitors get the menu directly; three.js
  is never even loaded for them.
- Skip is reachable by keyboard (Esc/Space and the focusable SKIP button).

## Testing

- **vitest (pure gating logic):** "should play the cinematic" given the
  `gibson-seen` flag, the `?intro` param, `prefers-reduced-motion`, and
  WebGL-availability; plus the flag set/consume. The WebGL scene is not
  unit-tested.
- **Playwright smoke** (like Phase B's, against a running server): `?intro`
  produces a `<canvas>`; a repeat visit (flag set) does not; reduced-motion does
  not; and in all cases the DOM menu ends up visible.

## Decomposition — two plans

- **C1 — Plumbing / skeleton:** three.js delivery (the `gibson.js` entry + lazy
  on-demand load), the full gating + first-visit flow, the Phase B mosaic-in
  seam, skip + `?intro` replay, reduced-motion / no-WebGL / repeat-visit
  fallbacks, and a **minimal placeholder scene** (e.g. a few rotating neon boxes)
  that runs the camera move and crossfades to the menu. The gating logic is
  unit-tested; the wiring is smoke-tested. Shippable: a working (if plain)
  cinematic that resolves to the menu.
- **C2 — The scene art:** replace the placeholder with the real Gibson — towers,
  circuit roads, bloom, the CatmullRom camera path, and the tower-face landing.
  Visual and iterative; this is where the look is dialed in.

## Out of scope

- Any change to the Phase A menu content or the Phase B transition look.
- Downloaded 3D models / textures (the scene is procedural).
- A general WebGL framework beyond what this one page needs.

## Open items to resolve in the plans

1. The exact shape of the Phase B `pixelIn` completion seam (callback param vs a
   dispatched event) — decide in C1.
2. How the always-present gate code and the lazy `gibson.js` bundle communicate
   (global hook, custom event, or a small exported entry the script calls).
3. `localStorage` key name and the `?intro` parsing location (shared with the
   gate).
