# /links Phase C2 — the real Gibson scene (design)

**Status:** Approved design, pending implementation plan.
**Date:** 2026-06-26
**Builds on:** Phase C1 (the cinematic pipeline + placeholder scene). C2 replaces ONLY the scene body.

## Goal

Replace C1's placeholder scene (three neon boxes) with a faithful recreation of
the **inside of the Gibson** from *Hackers* (1995): a city of glowing data-slab
towers along circuit-trace avenues, flown on a randomized route that turns
through the grid before diving into a tower face that becomes the menu.

Reference frames (from the film) define the target: dense rows of tall flat
slab-towers lining a central avenue, faces covered in glowing alphanumeric data
and small framed readout boxes, bright glowing edges, a dark faintly-reflective
floor carrying glowing magenta/purple PCB traces, strong one-point perspective
to a bright vanishing point, black sky, depth haze.

## Hard constraint — the C1 contract is unchanged

C2 only rewrites the body of `window.__gibsonRun(canvas, {onComplete})` in
`assets/js/gibson.js`. It must keep returning `{start, skip}`, render frame 0 on
build, call `onComplete()` exactly once at the end (or on `skip`), and dispose
its resources. The gate, controller (`gibson_intro.js`), and the Phase B seam do
NOT change. This means the whole C1 pipeline, fallbacks, and tests stay valid.

## The scene

- **Grid city.** Towers are laid out on a block grid (rows and columns) with
  avenues running both directions, so the camera has intersections to turn at.
  Towers are tall flat slabs (box geometry, much taller than wide/deep), packed
  densely, receding into black fog with a bright vanishing-point glow.
- **Tower faces.** Each face uses a **procedurally generated canvas texture** of
  glowing "data" — dense rows of tiny random alphanumerics, small framed readout
  boxes, and bar patterns — in the tower's color, on near-black. Emissive
  material so bloom makes it glow; bright vertical edges (brighter glow at the
  slab corners), a translucent-glass-slab feel.
- **Color.** Cyan-dominant towers (`#19c9ff`/`#8ff6ff` family) with a few magenta
  (`#ff31d9`) and green (`#b6ff00`) accent towers for life. Matches the `/links`
  palette. (Tunable on real renders; can shift greener toward the film's teal.)
- **Floor.** A dark, faintly reflective ground plane carrying glowing magenta/
  purple **PCB circuit-traces** (right-angle paths, rounded corners) running down
  the avenues toward the vanishing point. Reflection only if it stays performant;
  otherwise a dark plane with the trace texture is enough.
- **Atmosphere.** Black background, exponential depth fog for haze, and a bright
  glow far down the avenue. `UnrealBloomPass` post-processing for the overall
  neon bloom.

## The camera — randomized multi-segment route

A CatmullRom curve through waypoints generated **randomly each run**, kept tight
(~4–5s total, eased), so every play is a different route through the city:

1. Spawn low in one avenue and fly down it.
2. **Turn at an intersection** onto a cross-avenue and fly down it.
3. **Turn/dive into a tower face** (the final/landing tower).

The path banks (rolls) slightly into turns to sell the motion. Randomization
covers the start avenue, the turn points and directions, and which tower is the
landing tower. Two turns is the target (avenue → turn → avenue → turn-into-face);
keep it from feeling long.

## The landing

The landing tower's face texture is shaped to **echo the menu silhouette** (cyan
bars where the link items sit, a magenta block where the readout sits). The
camera dives into that face until it fills the viewport, then the canvas
crossfades to the real DOM menu — exactly the C1 handoff (`onComplete` →
controller crossfade). The menu remains accessible DOM; WebGL never renders the
link text.

## Performance

- Target a smooth ~60fps on a normal laptop for a ~4–5s one-shot. The scene is
  short-lived (built on play, disposed on completion).
- Keep the geometry cheap: instanced or shared box geometry for towers; a small
  number of distinct face textures reused across towers (not one per tower);
  fog + draw-distance to limit how many towers are visible/rendered.
- Bloom is the main GPU cost; tune its resolution/strength for the effect vs.
  framerate. Reflection is optional and first to cut if it costs frames.
- Dispose all geometries, materials, textures, render targets, and the renderer
  in the scene's `finish()` path (C1's placeholder already disposes the
  renderer; C2 must also dispose the geometry/material/texture/bloom resources it
  creates — a known C1 follow-up the reviewer flagged).
- Cap `devicePixelRatio` (e.g. at 2) as the placeholder already does.

## Accessibility / fallbacks (unchanged from C1)

Reduced-motion, no-WebGL, and repeat visits never load three.js and go straight
to the menu. The canvas stays `aria-hidden`; the SKIP control still cuts to the
menu at any point during the (now longer/real) flight.

## Testing

- The C1 gating/seam/controller unit tests and the Playwright smoke remain the
  automated coverage; they already assert the pipeline (canvas appears on
  `?intro`, menu visible at the end, no canvas on repeat/reduced-motion). C2
  changes only the scene internals, so those stay green.
- The scene visuals are **not** unit-tested. Correctness of feel is verified by
  the iterative build → Playwright-screenshot → review loop (see below) and a
  final manual eyeball.
- A guard worth adding: a vitest (or smoke) assertion that the camera-path
  generator produces a valid multi-waypoint path (right number of segments,
  ends at a tower) — IF the generator is extracted as a pure function. This is
  the one genuinely unit-testable piece of C2.

## Execution model (different from C1)

C2 is iterative visual art direction, which the subagent test-pipeline serves
poorly. Instead: build the scene in layers, and after each meaningful layer
capture **real rendered screenshots via Playwright** (entry / mid-avenue /
turn / landing) for review, then refine. Layers (rough order):

1. Renderer + scene + fog + bloom + a flat camera dolly (prove the pipeline
   renders the real path end-to-end, still crude geometry).
2. Tower grid + shared slab geometry + the procedural data-face texture(s).
3. The circuit-trace floor.
4. Materials/emissive/edge glow + color accents + bloom tuning.
5. The randomized multi-segment camera path generator + banking.
6. The landing tower-face-echoes-menu + crossfade alignment.
7. Tuning passes on real renders until the feel matches the references.

## Out of scope

- Any change to the C1 pipeline, the gate, the controller, the seam, or their
  tests (beyond the resource-disposal addition inside the scene).
- Downloaded 3D models or image textures (everything is procedural / canvas).
- Changing the Phase A menu or the Phase B transition.

## Open items to resolve in the plan

1. Whether the camera-path generator is extracted as a pure, unit-testable
   function (recommended, since it's the one testable piece).
2. Tower face-texture strategy: how many distinct textures to generate and reuse
   for variety vs. performance.
3. Whether floor reflection is included in the first pass or deferred to tuning.
