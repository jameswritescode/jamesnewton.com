# The Gibson — `/links` intro cinematic

A HACKERS (1995) tribute: first-time visitors to `/links` get a ~12-second WebGL
fly-through of a neon data-tower city — "the Gibson" — that descends from above
an endless grid, cruises its circuit-board streets, turns twice, and rises up a
tower's data-face, which crossfades into the links menu. The menu's background
is painted as a tower face, so the landing reads as *arriving on the building
you were just flying toward*.

Everything is deterministic (default seed) and procedural — no shipped image
assets.

## Experience flow

1. **Mosaic-in** (`pixel_transition.js`): a neon pixel mosaic covers the page
   instantly, then clears cell-by-cell. The clear is *gated* on the scene's
   first rendered frame (plus a 1.8s safety timeout), so the reveal always
   uncovers a rendered city, never a black canvas racing a bundle load.
2. **Flight** (11s): opening glide over the city → street cruise → two arc
   turns → rise up the landing tower. As the camera settles, the tower's face
   dims and an ACCESS PANEL irises open from a centre line (450ms): header
   (`JN.SYS // ACCESS NODE`), numbered rows — name · dot leaders ·
   destination host — and a status footer, all drawn from the DOM menu items
   (`data-name/desc/url`). Until that moment the landing tower is
   indistinguishable from its neighbours (no spoilers).
3. **Park**: the flight ends square-on the menu tower and *stays there* — the
   city keeps animating behind it (render-throttled to ~30fps for battery; the
   flight and iris always run full-rate). An invisible hotspot overlay
   (projected from the 3D row geometry through the live camera; re-laid-out on
   resize) makes the rows real links: hover/focus inverts the row in-scene,
   reveals its description, and flips the footer to `OPEN: <host>`. Hotspot
   anchors mirror `data-no-swup` (leaving must be a full navigation — an SPA
   swap would change the URL under a canvas that keeps covering it) and
   `data-pixel` (the home link exits through the mosaic it arrived by). The
   DOM page remains underneath (`inert` + `aria-hidden`) as the fallback.
   The parked distance is ASPECT-AWARE: derived from the horizontal FOV so the
   panel always fits (portrait phones park further back), clamped so the
   camera never backs into the opposite tower row; the panel's row sizing
   shares the same value.
4. **Bail** (WebGL effectively software, unrecovered context loss, bundle
   failure, or skip before the flight begins): the canvas fades out to the
   plain server-rendered page — a feed-styled list in the site's own design
   language, free of tower metadata. The Gibson never reads that markup: it
   reads the `#gibson-links` JSON island (name/desc/url/external/pixel per
   entry) rendered into the same page, so the two presentations of the links
   evolve independently. The page serves no-JS/no-WebGL visitors and
   crawlers; `?fallback` forces it for QA.
5. **Skip**: SKIP button, `Esc`, or `Space` — during flight it fast-forwards
   to the parked ending.
6. **Visit modes** (`gibson_gate.cinematicMode`, unit-tested): `flight` (first
   visit or `?intro`) → `parked` (repeat visits: straight to the tower, live
   city, iris delayed past the mosaic) → `still` (reduced motion: the tower
   as a static interactive image — no flight, no render loop, no scroll/
   cycling/pulses; renders once plus once per hover/resize; `?intro` never
   overrides the accessibility choice) → `none` (no WebGL: plain DOM page).

Plays once per visitor (`localStorage` flag via `gibson_gate.js`); `?intro`
forces a replay.

## File map

| File | Role |
|---|---|
| `assets/js/gibson_intro.js` | Controller in `app.js`: gating, canvas + skip UI, bundle injection (always cache-busted), mosaic gate/hook handoff, dev overlay |
| `assets/js/gibson_gate.js` | Pure gating decisions (first visit, reduced motion, WebGL) |
| `assets/js/gibson.js` | Lazy bundle entry (own esbuild entry). Owns the flight clock, easing, pause/scrub, fps stats |
| `assets/js/gibson/scene.js` | Orchestrator: camera/FOV, tower city + landing tower/menu, flight curve, bloom, render loop |
| `assets/js/gibson/board.js` | The motherboard: floor plane + live activity (data pulses, breathing pads) |
| `assets/js/gibson/debug.js` | Dev furniture: pause path-ribbon, ?gibsonView=over rig |
| `assets/js/gibson/path.js` | **Pure** route generator (no three.js) — unit-tested |
| `assets/js/gibson/textures.js` | Procedural Canvas2D textures: tower faces, roofs, the floor board, the menu access panel |
| `assets/js/pixel_transition.js` | Mosaic transition; exposes the one-shot gate/hook the intro uses |
| `links_html/index.html.heex` | Server-rendered fallback page (site design language) + the `#gibson-links` JSON manifest the scene reads |
| `assets/js/gibson/path.test.js` | Route invariants (vitest) |

### The contract

`gibson.js` defines `window.__gibsonRun(canvas, {onComplete, onArrived}) -> control`:

- builds the scene and renders frame 0 immediately
- `control.start()` begins the flight; `control.skip()` fast-forwards to the
  parked ending (or bails if the flight never began)
- `onArrived()` fires once when the flight parks on the menu tower; the render
  loop keeps running (live city). `control.menuRects()` /
  `control.menuHighlight(i)` drive the hotspot overlay
- `onComplete()` fires only on **bail** (scene disposed, DOM page revealed)
- dev extensions (additive): `control.togglePause()`, `control.nudge(frac)`

`gibson_intro.js` is the only consumer. The bundle URL always carries
`?v=Date.now()` — dynamically-injected scripts dodge hard-reload cache
invalidation, and a stale scene bundle costs far more than re-downloading one
file for a once-per-visitor cinematic.

## The city

- **Grid**: `GRID = {cols: 44, rows: 44, spacing: 44, towerFrac: 0.3}` —
  streets ~2.3× the tower footprint, towers at cell centres (offset +0.5 in
  both axes so street lines are clear), uniform height `H = 2 × spacing`.
- **"Infinite" illusion**: the route is confined to the central region;
  `FogExp2(0x010108, 0.0022)` swallows the grid edge from every point on the
  flight (the high opening is the only sightline over the rooftops, and the
  edge is ~890 units away from up there). The city fades out in all
  directions; no edge is ever visible.
- **Towers** (6 InstancedMesh groups by texture): data-screen side faces,
  rooftop screens with a glowing rim, near-black undersides, and a thin
  glowing **base skirt** (instanced geometry — group-coloured band where the
  tower meets the board, the ground-level counterpart of the roof rim).
- **Palette**: cyan-dominant (`0x19c9ff` ×3, `0x8ff6ff`, `0xff31d9`,
  `0xb6ff00`).

### Tower textures (`textures.js`)

- One shared **row painter** (`drawFaceRow`) draws all "screen furniture":
  glyph runs, framed readout boxes, bars. Faces, roofs, and the live cycling
  all use it — shared visual DNA.
- **Seam-safe row grid**: 16px row pitch divides every canvas exactly
  (512×2048 faces, 512×512 roofs) and rows cover the full canvas, so the
  y-wrap seam under scrolling is just another row gap. (Painting rows short of
  the bottom edge parades a black bar around scrolling faces.)
- Faces get **vertical** edge glow only (a horizontal line would ride up the
  face under scroll); roofs carry the full glowing rim.

### Live animation

- **UV scroll with per-group personalities** (`SCROLL_PER_SEC`): some groups
  stream up, some down at different rates, some hold still. Wall-clock, so it
  stays alive while paused.
- **Character cycling**: every 140ms one texture (faces *and* roofs,
  round-robin) gets a band of rows redrawn under a clip — one small upload per
  tick. Gated off during the aerial opening (`t < 0.35`): with the whole
  minified city in frame, a band redraw repaints on every instance of the
  group at once and reads as city-wide flicker.
- **Data pulses**: 220 `Points` streaming along street lanes (pure geometry,
  zero uploads), additive, palette-coloured, wrapped within the central
  region.
- **Breathing pads**: 36 instanced additive quads at intersections, pulsing
  via per-instance colour (individual phase/rate).

## The floor (motherboard)

One texture **block spans 4×4 city cells** (2048px), aligned so street lines
land on cell boundaries — seamless by construction, and the visible repeat
period is 176 units rather than one cell. On it:

- **Indigo substrate** (`#0e0b23`) with soft "copper pour" tonal zones — reads
  as board material, not void (and raises the darkest level, kinder to
  local-dimming displays).
- **Chips**: every tower footprint is a package — outline, silkscreen part
  label (`JN-1234`), solder-pad ring, breakout traces. Towers are components
  seated on the board.
- **1–2 arterial through-buses per street** (the only full-length straight
  runs; they carry continuity across blocks) plus **44 routed traces** that
  walk the lattice with 45° chamfered turns and terminate in vias or pads.
- **Neon glow**: every trace strokes twice — wide soft halo (0.20 alpha,
  2.8× width) under a bright core (0.75+ alpha) — a class below the tower
  rims. Colours are rolled once per trace, *outside* the wrap-copy loop.
- Vias (bright ring, dark centre), junction pad arrays, silkscreen
  micro-glyphs, ground-plane dot grid.
- Anything near a block edge draws with **5×5 wrap copies** (routed traces can
  wander ~2 block-widths).

## The flight

### Route (`path.js`, pure + tested)

1. **Opening/descent**: one **analytic quadratic ease-out glide** — altitude
   `cruise + Δ(1−u)²` sampled at 23 points from high over the city interior
   down to street level. Pitch decays continuously to exactly level; there are
   no hand-placed waypoints for the spline to round into bobs.
2. **Cruise + two turns**: straight runs with single centred **quarter-arc**
   corners (radius `0.68 × spacing`, ~10°/sample). No entry/exit drift — a
   centred arc clears the inside tower corner by the same margin, and lateral
   jogs read as S-wobble through the spline.
3. **Landing**: ride until level with a tower beside the street, veer toward
   its face while **rising** to ~72% of its height, ending square-on ~13 units
   out. Returns `landing {faceX, z, lookY, …}` for the camera blend.

Randomness (turn rows, direction, cross distance, landing side) comes from a
dedicated RNG stream so tower/texture draws can change without moving the
route. The city seed is fixed (**7**) while the route seed is **random per
load** (`sceneSeeds` in `gibson_gate.js`); the scene logs each load's route
seed to the console. `?routeSeed=N` replays a specific route; `?seed=N` pins
both streams (the fully deterministic mode captures rely on).

**Test invariants** (`path.test.js`): stays deep inside the grid (edge never
visible), opens high and descends below rooftop height, xz-heading never jumps
sharply, travels both axes, keeps ≥5 units clearance from every tower
footprint across seeds, ends risen and square to the landing face, and is
seed-deterministic.

### Camera

- **Spline**: CatmullRom through the waypoints, densified with collinear
  points on *level* segments only (stops lateral bowing on long straights;
  height-changing segments stay sparse so the glide stays analytic).
  `arcLengthDivisions = 20000` — the default 200-entry arc-length table
  quantises `getPointAt` into ±30% frame-to-frame speed ripple (measured),
  which reads as camera jitter; the dense table measures 0.0%.
- **Aim**: look along the curve tangent (look where you're going), with an
  upward-pitch clamp (~35°) so the final rise can't gimbal `lookAt`.
- **Opening gaze**: an altitude-proportional downward bias so the high glide
  looks across the endless rooftops instead of at black sky, lifting exactly
  as the camera descends.
- **Landing blend**: from 80% (complete by ~94%) the look lerps onto a fixed
  point high on the landing face, so the camera climbs while facing the
  building and the squared-up shot registers before the crossfade.
- **FOV**: horizontal capped at 75°, vertical at 58° — fixed vertical FOV
  fish-eyes on wide/short windows (a 3.8:1 window would hit ~126° horizontal).
- **Timing**: 11s, easeInOutQuad, then a 600ms hold on the face before
  `finish()`.

### Rendering

- `WebGLRenderer` (antialias **off** — rendering goes through the composer's
  non-MSAA targets, so canvas MSAA would cost resolve time and never apply;
  pixel ratio ≤ 2) + `EffectComposer` with `UnrealBloomPass(strength 0.5,
  radius 0.5, threshold 0.45)` — threshold sits above the aliasing noise floor
  so shimmering pixels don't pop halos.
- **Background-tab survival**: hidden frames do ZERO work — no render, no
  texture uploads — and the flight clock freezes, so a visitor who backgrounds
  mid-flight resumes exactly where they left (Chrome/Edge/Safari stop calling
  rAF for hidden tabs anyway; Firefox trickles ~1fps, which now costs nothing).
  Pacing samples are only taken while visible (that 1fps trickle would read as
  a slideshow GPU and falsely bail); pacing clocks and the context-loss
  restore grace reset on `visibilitychange` AND `pageshow` (bfcache restores
  can skip the former). Full tab discards reload into parked mode; contexts
  reclaimed while hidden get their full 4s grace from the moment the user
  returns. Memory is the browser's to reclaim — we survive it rather than
  fight it.
- **Adaptive quality** (500ms fps windows in the flight loop): below 45fps the
  pixel ratio steps down 2 → 1.5 → 1 (quadratic fill savings — full-screen
  render + bloom's blur chain dominate GPU cost); ~software-rendered WebGL
  (<12fps for 3 windows) skips straight to the menu. Measured baselines:
  572KB minified / 146KB gzip bundle, 143ms scene build (hidden behind the
  mosaic), 120fps @ dpr 2 on Apple Silicon, ~118fps under 6× CPU throttle
  (GPU-bound).
- Max **anisotropy** on all tower/roof/floor textures — tower faces pass at
  grazing angles and the floor *is* a grazing angle; low anisotropy aliases
  the glyph rows into sparkle under motion.
- `.gibson-canvas` CSS pins `width/height: 100%` — without it, the canvas
  displays at its intrinsic buffer size (dpr × viewport) anchored top-left and
  retina browsers show only the top-left quarter. (Headless dpr=1 masks this
  entirely; it cost us a day.)

## Debug tooling

### In-page (currently shipped; teardown list pending)

| Control | Effect |
|---|---|
| `` ` `` | Toggle **debug mode**: shows the fps HUD (render pacing — reads ~30 while parked-throttled) and arms the inspection keys below. Toggling OFF hides the HUD and resumes playback from wherever the flight is |
| `P` | (debug mode) Pause/resume the flight. While paused, the **path ribbon** lights up (glowing tube, cyan start → magenta landing, floated 4.5 units below the camera line) and texture animation keeps running |
| `←` / `→` | (debug mode) Scrub ±2% of the flight while paused |
| `Esc` / `Space` | Skip (production behaviour, always active) |

`window.__gibsonFps` carries the same render-pacing samples the HUD shows;
`dev/gibson/fps.mjs` reads it headlessly.

### Query params

| Param | Effect |
|---|---|
| `?intro` | Force-replay the cinematic |
| `?fallback` | Force the plain server-rendered page (beats everything, incl. `?intro`) |
| `?seed=N` | Pin BOTH seeds (city + route) for fully deterministic captures |
| `?routeSeed=N` | Replay a specific route through the fixed city (each load logs its route seed) |
| `?gibsonFrame=0..1` | Static hold at that route fraction; exposes `window.__cam` |
| `?gibsonView=over` | Overhead debug camera + route line (fog off) |

### Harness scripts (`assets/dev/gibson/`, run with `node` from repo root)

Agent-facing verification playbook: `docs/agents/gibson-verification.md`.

- `record.mjs [W H]` — **the** capture tool: records the real flight on a
  hardware GPU, reports `FLIGHTSTART_S` for frame-anchored extraction.
- `stills.mjs [fracs…]` — deterministic `?gibsonFrame` still frames (exposes
  `window.__cam`/`__route` for probing).
- `plot_route.mjs` — top-down SVG plot of the exact spline + tower footprints
  (turn shape verification).
- `plot_profile.mjs [out]` — side profile (altitude vs distance) +
  undershoot/oscillation stats (vertical smoothness verification).
- `fps.mjs` (`SOFTWARE=1` for the software-GL case) — frame pacing readout.
- `smoke.mjs` — parked-ending end-to-end: hotspots, hover, click-home
  navigation/teardown.

Outputs land in `tmp/gibson/` (gitignored). One-off probes beyond these are
written ad hoc and deleted — the capture rules below are what matters.

### Hard-won capture rules

1. **Headless Chromium renders WebGL in software at 2–4fps.** Always launch
   with `--use-angle=metal --enable-gpu-rasterization --ignore-gpu-blocklist`
   → 120fps real GPU. Without it, recordings are slideshows and motion
   artifacts are invisible.
2. **Always test at `deviceScaleFactor: 2`** — dpr=1 masks retina canvas
   sizing bugs (see the quarter-crop incident above).
3. Judge motion from **recorded video** (ffmpeg filmstrips/gifs), never from
   static frames — the bad moments live between sampled frames.
4. The flight start varies per load (cache-busted bundle); anchor frame
   extraction on the instrumented `FLIGHTSTART_S`, not wall-clock guesses.

## Parked / open items

- **Teardown**: what stays/goes from the debug kit is a wrap-up conversation
  — current lean: keep `P` pause (+ ribbon), `?seed`, `?gibsonFrame`; strip
  build tag, fps readout, scrubbing, debug globals, one-shot scripts, and the
  served `priv/static/images/gibson-debug/` images.

## Verification

- JS: `cd assets && npx vitest run` (route invariants + the rest of the suite).
- Visual: capture rules above; deterministic seed makes captures reproducible.
- `mix precommit` before landing changes.
