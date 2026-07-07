# Gibson verification

Use when changing anything about the `/links` cinematic (scene, route, camera,
textures, the parked menu) — before claiming a visual change works.

Design rationale and architecture live in `docs/gibson.md`. This is the
how-to-verify playbook. Tools live in `assets/dev/gibson/`; outputs land in
`tmp/gibson/` (gitignored). All assume the dev server on `localhost:4000`.

## Non-negotiable capture rules

1. **Judge motion from recorded video, never static frames.** Every pathing
   bug in this scene's history lived *between* sampled frames. Record with
   `record.mjs`, extract frames with ffmpeg, or make a gif for the human.
2. **Hardware GPU flags always** (`record.mjs` et al. bake them in):
   `--use-angle=metal --enable-gpu-rasterization --ignore-gpu-blocklist`.
   Default headless WebGL is software-rendered at 2–4fps — a slideshow that
   hides every motion artifact.
3. **`deviceScaleFactor: 2` always.** dpr=1 masks retina canvas-sizing bugs
   (a missing CSS rule once showed dpr-2 users a quarter of the scene while
   dpr-1 captures looked perfect).
4. **Anchor timing on `FLIGHTSTART_S`** (printed by `record.mjs`), not
   wall-clock guesses — the cache-busted bundle load varies per run.
5. The scene is **deterministic (seed 7)**; `?seed=N` for A/B. Layout is
   reproducible; scroll/cycling are wall-clock, so byte-diffing screenshots
   only works in reduced-motion (`still`) mode.

## Tools

| Tool | Use |
|---|---|
| `node assets/dev/gibson/record.mjs [W H]` | Record the full flight; prints `FLIGHTSTART_S` + video path. THE tool for judging motion |
| `node assets/dev/gibson/stills.mjs [fracs…]` | Deterministic `?gibsonFrame` holds; exposes `window.__cam` / `window.__route` for numeric probes |
| `node assets/dev/gibson/plot_route.mjs` | Top-down SVG of the exact spline vs tower footprints (turn shape) |
| `node assets/dev/gibson/plot_profile.mjs [out]` | Side profile (altitude vs distance) + undershoot/oscillation stats (vertical smoothness) |
| `node assets/dev/gibson/fps.mjs` | Frame pacing from `window.__gibsonFps` (`SOFTWARE=1` simulates weak GPU / the bail path) |
| `node assets/dev/gibson/smoke.mjs` | Parked-ending end-to-end: hotspots, hover, click-home teardown |

Useful ffmpeg one-liners:

    # filmstrip (every 0.5s) and gif from a recording
    ffmpeg -i VID.webm -vf "fps=2,scale=340:-1,tile=6x4" strip.png
    ffmpeg -i VID.webm -vf "fps=12,scale=560:-1,split[a][b];[a]palettegen=max_colors=96[p];[b][p]paletteuse=dither=bayer" flight.gif
    # single frame at flight-time T
    ffmpeg -ss $((FLIGHTSTART_S + T)) -i VID.webm -frames:v 1 frame.png

## In-page debug controls

- `?intro` force-replays the flight; plain `/links` parks repeat visitors
  directly on the tower (`gibson-seen` in localStorage); `?fallback` forces
  the plain server-rendered page.
- **`** toggles debug mode (fps HUD + arms the inspection keys); inside it,
  **P** pauses (path ribbon lights up) and **←/→** scrub while paused.
  Toggling debug off resumes playback in place.
- `?gibsonFrame=0..1` static hold; `?gibsonView=over` overhead route view.

## What "verified" means here

- Motion changes: a recording reviewed frame-by-frame across the affected
  phase, plus the route/profile plots if the path moved.
- Geometry/texture changes: stills at aerial (0.12), street (0.6), and
  landing (1) at minimum.
- Ending/menu changes: `smoke.mjs` green (hotspot labels + hrefs, hover
  highlight, click-home full navigation with scene teardown).
- Any change: `cd assets && npx vitest run` (route invariants live in
  `js/gibson/path.test.js`), and send the human a gif/screenshot — they have
  final judgment on feel.
