# Theme-Aware "JN" Favicon — Design Spec

**Date:** 2026-06-21
**Status:** Approved (pending written review)
**Branch context:** `phoenix-migration`

## Overview

Replace the default favicon with a custom **"JN" monogram** drawn in the site's
**Lora** typeface, whose colors follow the viewer's **OS light/dark setting**.
This is one of two related-but-independent features the user asked for; the
**Open Graph / Twitter preview cards** are a separate spec.

## Decisions (locked)

- **"JN"** monogram, **Lora SemiBold (600)** glyphs converted to **SVG vector
  paths** (not `font-family` text, which renders inconsistently in favicons).
- **OS theme only** (via `prefers-color-scheme` inside the SVG) — favicons live in
  browser chrome and cannot follow the site's in-page theme toggle. Light: cream
  `#ffe8d6` on red `#aa4040`; dark: cream `#eed3ba` on near-black `#151311` (the
  site's `--bg`/`--text` and `--bg-dark`/`--text-dark` tokens).
- **Rounded-square** background (~20% corner radius), app-icon style.
- Ship an **SVG primary** + **PNG fallbacks** + **apple-touch-icon**; keep a
  **reproducible generation script** in the repo.
- **Out of scope:** OG/Twitter cards (separate spec); animated/interactive icons;
  following the in-page theme toggle (not possible for favicons).

## Assets (committed to `priv/static/`)

- **`favicon.svg`** — primary, theme-aware. A `viewBox="0 0 64 64"` document
  containing a rounded `<rect>` background and the "J"+"N" outlines as `<path>`s,
  plus an embedded `<style>`:
  ```css
  :root { --fav-bg: #aa4040; --fav-fg: #ffe8d6; }
  @media (prefers-color-scheme: dark) { :root { --fav-bg: #151311; --fav-fg: #eed3ba; } }
  ```
  with `rect { fill: var(--fav-bg) }` and the glyph paths `fill: var(--fav-fg)`.
- **`apple-touch-icon.png`** (180×180) — iOS ignores theme; render the **light
  (red)** variant on an opaque rounded square.
- **`favicon-96.png`**, **`favicon-32.png`** — PNG fallbacks (light/red variant)
  for browsers without SVG-favicon support.
- **`favicon.ico`** — refresh the existing legacy file to the JN mark (light
  variant; 16/32 sizes) as the last-resort fallback.

The "JN" is centered with even optical margins; glyph size tuned so it reads at
16px. Cream foreground works on both backgrounds, so only the two fills swap.

## Generation pipeline (build-time, one-time; not runtime)

A small script under `assets/favicon/` regenerates the assets so they're
reproducible (it is **not** part of the app build or the user bundle):

1. Fetch **Lora SemiBold** TTF (SIL OFL, from the google/fonts repo) into
   `assets/favicon/` (gitignored or committed — see below).
2. **`assets/favicon/generate.mjs`** (Node, dev-only deps `opentype.js` + a
   rasterizer such as `sharp`): load the TTF, extract the `J` and `N` glyph path
   data at the chosen size/position, assemble `favicon.svg` (rect + paths +
   the `prefers-color-scheme` `<style>`), then rasterize the **light** variant to
   `apple-touch-icon.png` (180), `favicon-96.png`, `favicon-32.png`, and write
   `favicon.ico`.
3. The script writes its output directly into `priv/static/`. Re-running it
   regenerates all icons deterministically.

`opentype.js`/`sharp` go in `assets/package.json` **devDependencies** only; they
never enter `app.js`/`admin.js`. The committed artifacts in `priv/static/` are
what's actually served.

## Wiring (`root.html.heex` and `admin_root.html.heex`)

Add to `<head>` (both layouts):
```heex
<link rel="icon" href={~p"/favicon.svg"} type="image/svg+xml" />
<link rel="icon" href={~p"/favicon-32.png"} sizes="32x32" />
<link rel="apple-touch-icon" href={~p"/apple-touch-icon.png"} />
```
`/favicon.ico` is auto-requested at the site root by browsers, so it needs no
explicit tag. Ensure the new filenames are in `NewtonWeb.static_paths()` (or the
`Plug.Static` `only:` list) so they're served.

## Security / CSP

No CSP change. The favicon is fetched as a separate icon resource; the SVG's
internal `<style>`/`prefers-color-scheme` is interpreted by the browser's image
renderer, not governed by the page's `style-src`/`img-src`. (The page never
inlines the SVG.)

## Testing

- **Visual (primary):** render `favicon.svg` in a light and a dark context and
  confirm the "JN" reads as Lora and the bg/fg swap; screenshot at small sizes to
  confirm legibility at 16–32px. Verified with a throwaway HTML harness +
  Playwright `colorScheme` (light/dark) screenshots, or `sharp` raster previews.
- **Wiring (controller test):** a public page's rendered `<head>` contains
  `rel="icon"` pointing at `/favicon.svg` and the `apple-touch-icon` link —
  asserting the theme-aware icon is actually referenced.
- **Build reproducibility:** re-running `generate.mjs` produces byte-stable output
  (or at least visually identical), so the committed assets can be regenerated.

## Unit breakdown

- `assets/favicon/generate.mjs` (+ the Lora TTF input) — the generator.
- `priv/static/favicon.svg`, `apple-touch-icon.png`, `favicon-96.png`,
  `favicon-32.png`, `favicon.ico` — generated, committed.
- `lib/newton_web/components/layouts/root.html.heex`,
  `lib/newton_web/components/layouts/admin_root.html.heex` — `<link>` tags.
- `lib/newton_web/endpoint.ex` / `NewtonWeb.static_paths()` — ensure the new files
  are served by `Plug.Static`.
- `assets/package.json` — dev-only `opentype.js` + rasterizer.

## Out of scope (future / separate)

- Open Graph / Twitter preview card images (separate spec — the next feature).
- A maskable/adaptive Android icon + web app manifest (could follow if PWA is ever
  wanted).
