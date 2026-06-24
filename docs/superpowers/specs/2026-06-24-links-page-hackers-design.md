# /links — the HACKERS "Gibson" page (design)

**Status:** Approved design, pending implementation plan.
**Date:** 2026-06-24

## Goal

A public `/links` page that is a full-screen tribute to the interfaces in the
movie *Hackers* (1995) — specifically "the Gibson." Clicking **Links** from the
main site pixel-dissolves into a cinematic fly-through of a neon data-tower
city that lands on a movie-accurate menu of James's outbound links.

The page intentionally breaks away from the rest of the site: no shared header,
no shared chrome, its own palette and typography.

## Aesthetic

- **Palette:** electric cyan (`#19c9ff`/`#00e5ff`), hot magenta (`#ff31d9`/`#ff5cc8`),
  acid green (`#b6ff00`) accents, on near-black (`#020207`).
- **Type:** heavy, condensed, uppercase, letter-spaced sans for the menu items
  (the chunky movie look); monospace for the readout/technical text.
- **Texture:** faint scrolling columns of code/numbers behind everything; CRT
  scanline overlay; neon glow (`text-shadow`/`box-shadow`, and real bloom in the
  WebGL layer).

## Architecture — two layers

The page is built as two independent layers so it degrades gracefully:

1. **Base layer — the static Gibson menu (HTML/CSS).** The real, accessible
   content: a left column of chunky neon menu items (one `<a>` per link) plus a
   magenta **readout panel** immediately to their right that reflects the
   currently-focused/hovered link (name, URL, one-line description). Works with
   no JS and no WebGL. This is what screen readers and crawlers see.

2. **Enhancement layer — the three.js cinematic.** A full-screen `<canvas>`
   overlay that plays the entrance, then fades out to reveal the base menu
   beneath it. Because it is purely additive, every fallback path
   (reduced-motion, no WebGL, repeat visit) simply skips it and shows layer 1.

The static menu is not throwaway scaffolding — it is the literal scene the
camera resolves into. The cinematic lands on the same DOM.

## The destination menu (layer 1)

- **Layout:** menu column + readout panel grouped as one left-aligned cluster,
  vertically centered; the code-tower texture fills the remaining void to the
  right.
- **Menu items:** uppercase, heavy, cyan with neon glow, each with a `▶` marker.
  Hover/focus turns the item magenta and updates the readout. A final
  `◀ JN.SYS [HOME]` item (magenta) returns to the main site.
- **Readout panel:** magenta-bordered, monospace; shows `// READOUT`, the link
  name, the URL, and a short description for the focused item. Defaults to the
  first link.
- **Interaction:** items are real anchors. Hover and keyboard focus both drive
  the readout. Click/Enter navigates (external links open per normal site
  conventions). Fully keyboard-navigable.

## The cinematic entrance (layer 2)

Four beats:

1. **Pixel-dissolve in** — the mosaic overlay from the page transition clears,
   resolving the scene from chunky blocks (see Page transition).
2. **Drop into the Gibson** — camera enters from above, pitching down into the
   tower field.
3. **Drive the roads** — camera follows a curve (CatmullRom) between receding
   neon towers along circuit-trace "roads."
4. **Land** — camera pushes into the face of the final/largest tower, which
   resolves; the canvas fades and the static menu (layer 1) is revealed.

**WebGL scene (three.js):** extruded chip/tower geometry, circuit-trace ground
detail, emissive neon materials, and `UnrealBloomPass` post-processing for the
glow. Camera animates along a predefined curve over ~4–5s with eased timing.

## Entrance behavior

- **First visit only.** The full cinematic plays once; a `localStorage` flag is
  set so subsequent visits skip straight to the static menu.
- **`prefers-reduced-motion`:** skip the cinematic entirely; show the static
  menu immediately (no fly-through, no pixelation).
- **WebGL unavailable / three.js fails to load:** skip to the static menu.

## Page transition (main site → /links)

- **Launch approach — mosaic overlay.** On click of the Links nav item, a grid
  of theme-colored blocks builds up over the outgoing page; after navigation the
  /links page clears the same mosaic as the cinematic begins. Cross-browser,
  needs no page screenshot, reads as "pixelizing." This replaces the site's
  default `transition-fade` for this navigation only.
- **Future:** a more advanced/authentic transition (e.g. true content
  pixelation, or the cross-document **View Transitions API**) is explicitly
  deferred. The mosaic is the starting point.

## three.js delivery

- Lazy `import('three')` (and the post-processing addons) so it is **only**
  loaded on `/links` and never enters the main bundle that every other page
  ships.
- **Research/build item:** the project ships a single `app.js` bundle; confirm
  how to code-split or separately load three.js under that constraint (esbuild
  `splitting`, a dedicated entry, or an equivalent). Resolve in the plan before
  building the WebGL layer.

## Data

- **`Newton.Links`** — a hardcoded Elixir module. `all/0` returns an ordered
  list of link structs: `%{name, url, description}`. No database, no admin UI.
- **Launch link set** (real handles/URLs to be filled in at implementation):
  GitHub, LinkedIn, Bluesky (BSKY), Mark OS (`https://markos.ai`),
  Email (`mailto:hello@jamesnewton.com`), RSS.
- **RSS caveat:** the site has no RSS feed yet. The RSS link is part of the
  design but should only be enabled once the feed exists (separate future work).
- The `JN.SYS [HOME]` back-to-site item is part of the template, not the link
  data.

## Routing & layout

- `get "/links", LinksController, :index` in the existing public `:browser`
  scope (no authentication).
- `LinksController` renders `links_html/index.html.heex`, which builds its own
  full-screen markup and **does not** use `<Layouts.app>` (so the shared site
  header is omitted for the takeover). It still renders inside the existing
  public `root.html.heex` (fonts, `app.css`, `app.js`).
- Add a **Links** entry to the `site_nav` component (the click target).
- `assets/css/links.css`, scoped under a `.links` root class, imported into
  `app.css`.

## Accessibility

- Real anchors; full keyboard navigation; visible focus states that mirror hover.
- `prefers-reduced-motion` honored (no fly-through, no pixelation).
- The static menu is the accessible source of truth; the canvas is decorative
  (`aria-hidden`).

## Testing

- **Elixir:** `LinksController` test — `GET /links` returns 200 and renders the
  real link names/URLs from `Newton.Links`; `Newton.Links` test asserts the
  expected ordered set/shape. Behavior-focused, no template-structure assertions.
- **JS (vitest):** the entrance **gating logic**, extracted as pure functions —
  "plays on first visit only" (localStorage), "skips under reduced-motion",
  "skips when WebGL unavailable". The WebGL scene itself is not unit-tested.

## Out of scope (future work)

- Blogroll / curated "cool sites" section (the page is designed to accommodate a
  second section later, but it is not built now).
- Building the actual RSS feed.
- A more advanced page transition beyond the mosaic overlay.
- Any admin/database management of links.

## Open items to resolve in the plan

1. three.js bundling/code-splitting under the single-`app.js` constraint.
2. Real URLs/handles for GitHub, LinkedIn, Bluesky.
3. How the existing client-side init (the ripple canvas / page-transition JS) is
   wired, so the links init and mosaic transition follow the same pattern.
