# /links Phase B — Pixel (mosaic) page transition (design)

**Status:** Approved design, pending implementation plan.
**Date:** 2026-06-24
**Builds on:** Phase A (the static `/links` page). Precedes Phase C (the three.js cinematic).

## Goal

Replace the plain full-page load when crossing between the main site and the
`/links` takeover with a **neon mosaic "pixelize" transition**: a grid of
flickering neon blocks dissolves the outgoing page away and resolves the
incoming page in. It reads as the screen pixelizing rather than fading.

## Scope

The transition covers the two crossings between the warm main site and the
`/links` takeover (both are full-document navigations because the links are
`data-no-swup`):

1. **Entrance:** main site → `/links` (clicking the `Links` nav item).
2. **Exit:** `/links` → home (clicking `JN.SYS [HOME]`).
3. **Direct load / refresh of `/links`:** plays the mosaic-IN on its own, so the
   page never simply appears, even with no originating click.

Everything else on the site keeps using Swup's existing fade. The pixel
controller and Swup never both handle the same navigation.

## Mechanism — two-halves handoff

Because the crossings are full-document navigations (the DOM is wiped), the
mosaic is two halves that hand off across the load via `sessionStorage`.

- **On click** of a `data-pixel` link:
  1. `preventDefault()`.
  2. Play **mosaic-OUT**: the canvas overlay fills the viewport with neon blocks
     in random order until fully opaque.
  3. Set `sessionStorage["pixel-in"] = "1"`.
  4. `window.location.href = href` (full navigation).
- **On page load** (controller init): play **mosaic-IN** if EITHER
  `sessionStorage["pixel-in"]` is set OR the current path is `/links`. The canvas
  starts fully covering the viewport, then blocks flash neon and clear in random
  order. Remove the `pixel-in` flag after reading it.
  - Entrance: flag set by the click on the site → mosaic-in on `/links`.
  - Exit: flag set by the click on `/links` → mosaic-in on home.
  - Direct load / refresh of `/links`: no flag, but path is `/links`, so it still
    mosaics-in.
- **`prefers-reduced-motion`:** the controller does nothing — clicks navigate
  normally and no canvas is shown, in either direction.

### Why the flag is read-and-cleared

The flag exists only to bridge a single navigation. It is set immediately before
navigating and cleared the moment the destination reads it, so a later unrelated
load never replays a stale mosaic-in.

## The look (locked)

- **Style:** neon flicker. Each block briefly flashes one of cyan `#19c9ff`,
  magenta `#ff31d9`, acid green `#b6ff00`, or light-cyan `#8ff6ff`, then settles
  to near-black `#05010a` (OUT) or clears to transparent (IN).
- **Order:** random.
- **Granularity:** fine — a fixed block size (~18px) so cell count scales with
  the viewport; "fine" across a large monitor is thousands of cells.
- **Duration:** ~550ms per half (tunable).
- **Rendering:** a single full-viewport `<canvas>`, drawn with `fillRect` on
  `requestAnimationFrame`. Canvas is chosen over DOM blocks specifically because
  fine granularity at full-viewport size is thousands of cells, which canvas
  animates smoothly where thousands of transitioning `<div>`s would jank.

## Architecture & files

- **`assets/js/pixel_transition.js`** — the controller. Responsibilities:
  - Intercept clicks on `a[data-pixel]`, run mosaic-OUT, set the flag, navigate.
  - On init, decide whether to run mosaic-IN and run it.
  - Own the canvas overlay element and the block animation.
  - Honor `prefers-reduced-motion`.
  - Export small pure helpers for testing (see Testing).
- **`assets/js/app.js`** — import and initialize the controller on load,
  following the existing `initPhotos` / `initLinks` pattern. (The controller
  attaches its own document-level click listener; it is not re-run per Swup
  swap, since the `data-pixel` crossings are outside Swup.)
- **Canvas overlay** — a single fixed, full-viewport `<canvas>` on the top layer
  with `pointer-events: none`, created by the module (kept out of the server
  templates so it exists identically on every page).
- **`data-pixel`** — added to the two crossing links: the `Links` entry in
  `site_nav/1` and the `JN.SYS [HOME]` link in the `/links` template. (Both
  already carry `data-no-swup`.)
- **CSS** — minimal: the canvas overlay's fixed positioning and stacking. Lives
  with the existing public CSS (e.g. a small block in `app.css`/`site.css` or a
  dedicated file), not scoped under `.links` since the overlay must work on the
  main site too.

## Interaction with Phase C

In Phase B the mosaic-IN on `/links` reveals the static menu directly. In Phase
C the cinematic fly-through will sit between the mosaic-IN and the menu (the
mosaic resolves into the fly-through, which lands on the menu). The controller
should expose a clean seam so Phase C can hook the fly-through to the
mosaic-IN's completion without rewriting the transition.

## Accessibility

- `prefers-reduced-motion` fully bypasses the effect (normal navigation).
- The canvas overlay is decorative: `aria-hidden="true"`, `pointer-events: none`,
  and never traps focus. Navigation still happens via real link `href`s.
- If JavaScript is disabled, the `data-pixel` links are ordinary `<a href>`s and
  navigate normally (no transition, no breakage).

## Testing

- **vitest (pure logic):**
  - The random-order generator returns a permutation of all cell indices.
  - The "should mosaic-in" decision: true when the flag is set, true when path is
    `/links`, false otherwise; and false when `prefers-reduced-motion` matches.
  - The sessionStorage flag is set on out and read-then-cleared on in.
- **vitest (behavioral, navigation stubbed):** clicking a `data-pixel` link
  prevents default, sets the `pixel-in` flag, and begins the out-animation; with
  reduced-motion on, it does none of that and lets the navigation proceed.
- The canvas animation itself (visual smoothness) is not unit-tested.

## Out of scope (future)

- The three.js cinematic fly-through (Phase C).
- Any true content-pixelation of the actual page bitmap, or a cross-document
  View Transitions API upgrade. (Not possible without a page screenshot; the
  solid/neon mosaic is the deliberate, cross-browser approach.)
- Applying the pixel transition to any navigation other than the two site↔/links
  crossings.

## Open items to resolve in the plan

1. Exact canvas overlay lifecycle (single persistent element vs. created/destroyed
   per transition) and z-index relative to the existing ripple canvas / topbar.
2. Where the small overlay CSS lives.
3. The precise seam/callback Phase C will hook into.
