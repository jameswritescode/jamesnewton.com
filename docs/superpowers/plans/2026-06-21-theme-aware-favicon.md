# Theme-Aware "JN" Favicon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Note:** Task 1 involves visual judgment (does the "JN" read as Lora at favicon sizes); it's best executed inline, not by a subagent.

**Goal:** A custom "JN" monogram favicon in Lora that swaps colors with the viewer's OS light/dark setting, plus PNG/ico/apple-touch fallbacks, wired into both layouts.

**Architecture:** A build-time Node script (`assets/favicon/generate.mjs`) extracts the "J"+"N" glyph outlines from the Lora variable font (at weight 600) as SVG vector paths, composes a `prefers-color-scheme`-aware `favicon.svg`, and rasterizes the light variant into PNG/ico fallbacks — all written to `priv/static/` and committed. The layouts reference them with `<link>` tags.

**Tech Stack:** Node (dev-only npm: `fontkit` for glyph paths, `sharp` for SVG→PNG, `png-to-ico` for the ico), HEEx layouts, `Plug.Static`.

**Reference spec:** `docs/superpowers/specs/2026-06-21-theme-aware-favicon-design.md`

**Session constraints:** Commit signed (1Password; if it fails, `--no-gpg-sign` then re-sign later). Commit trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`. Don't modify `config/dev.exs`. Servers (if needed) on PORT=4001.

---

## Task 1: Generate the favicon assets

**Files:**
- Create: `assets/favicon/generate.mjs`
- Create (generated, committed): `priv/static/favicon.svg`, `priv/static/apple-touch-icon.png`, `priv/static/favicon-96.png`, `priv/static/favicon-32.png`; overwrite `priv/static/favicon.ico`
- Modify: `assets/package.json` (devDependencies), `.gitignore` (the fetched TTF)

- [ ] **Step 1: Add dev dependencies**

```bash
cd assets && pnpm add -D fontkit sharp png-to-ico
```

- [ ] **Step 2: Gitignore the fetched font**

Append to `.gitignore`:
```
# Source font fetched by the favicon generator (output SVG/PNGs are committed)
/assets/favicon/Lora.ttf
```

- [ ] **Step 3: Write the generator**

Create `assets/favicon/generate.mjs`:

```js
// Regenerates the favicon assets in priv/static from the Lora font.
// Run: `node assets/favicon/generate.mjs` (from the repo root or assets/).
import fontkit from "fontkit"
import sharp from "sharp"
import pngToIco from "png-to-ico"
import {readFileSync, writeFileSync, existsSync, mkdirSync} from "node:fs"
import {fileURLToPath} from "node:url"
import {dirname, join} from "node:path"

const here = dirname(fileURLToPath(import.meta.url))
const staticDir = join(here, "..", "..", "priv", "static")
const ttfPath = join(here, "Lora.ttf")
const LORA_URL = "https://github.com/google/fonts/raw/main/ofl/lora/Lora%5Bwght%5D.ttf"

const SIZE = 64
const RADIUS = 13 // ~20% rounded square
const LIGHT = {bg: "#aa4040", fg: "#ffe8d6"}
const DARK = {bg: "#151311", fg: "#eed3ba"}
const CAP_FRACTION = 0.52 // cap height as a fraction of the box

if (!existsSync(ttfPath)) {
  const res = await fetch(LORA_URL)
  if (!res.ok) throw new Error(`Lora download failed: ${res.status}`)
  writeFileSync(ttfPath, Buffer.from(await res.arrayBuffer()))
}

const font = fontkit.openSync(ttfPath).getVariation({wght: 600})
const run = font.layout("JN")

// Scale so the cap height fills CAP_FRACTION of the box; flip Y for SVG coords.
const scale = (SIZE * CAP_FRACTION) / font.capHeight
let penX = 0
const glyphPaths = run.glyphs.map((g, i) => {
  const p = g.path.scale(scale, -scale).translate(penX, 0)
  penX += run.positions[i].xAdvance * scale
  return p
})

// Center the combined glyph bbox in the box.
const boxes = glyphPaths.map((p) => p.bbox)
const minX = Math.min(...boxes.map((b) => b.minX))
const maxX = Math.max(...boxes.map((b) => b.maxX))
const minY = Math.min(...boxes.map((b) => b.minY))
const maxY = Math.max(...boxes.map((b) => b.maxY))
const dx = (SIZE - (maxX - minX)) / 2 - minX
const dy = (SIZE - (maxY - minY)) / 2 - minY
const d = glyphPaths.map((p) => p.translate(dx, dy).toSVG()).join(" ")

const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${SIZE} ${SIZE}">
  <style>
    :root { --bg: ${LIGHT.bg}; --fg: ${LIGHT.fg}; }
    @media (prefers-color-scheme: dark) { :root { --bg: ${DARK.bg}; --fg: ${DARK.fg}; } }
    .bg { fill: var(--bg); }
    .fg { fill: var(--fg); }
  </style>
  <rect class="bg" width="${SIZE}" height="${SIZE}" rx="${RADIUS}" ry="${RADIUS}"/>
  <path class="fg" d="${d}"/>
</svg>
`
mkdirSync(staticDir, {recursive: true})
writeFileSync(join(staticDir, "favicon.svg"), svg)

// Rasterize the LIGHT variant (opaque, with bg) for the PNG/ico/apple fallbacks.
const lightSvg = svg
  .replace("var(--bg)", LIGHT.bg)
  .replace("var(--fg)", LIGHT.fg)
const raster = (size) => sharp(Buffer.from(lightSvg)).resize(size, size).png().toBuffer()

writeFileSync(join(staticDir, "apple-touch-icon.png"), await raster(180))
writeFileSync(join(staticDir, "favicon-96.png"), await raster(96))
writeFileSync(join(staticDir, "favicon-32.png"), await raster(32))
writeFileSync(join(staticDir, "favicon.ico"), await pngToIco([await raster(32), await raster(16)]))

console.log("favicon assets written to priv/static/")
```

Note: the `.replace` calls only swap the first occurrence — since `--bg`/`--fg` each appear once as the value definition in `:root`, and the class rules use `var(...)`, the light raster needs both vars resolved. Use a more robust substitution if needed: replace the whole `<style>…</style>` block with literal `.bg{fill:LIGHT.bg}.fg{fill:LIGHT.fg}` for the raster pass. Verify the rasters are not transparent/!black; adjust the substitution until the PNGs show cream JN on red.

- [ ] **Step 4: Run the generator**

Run: `node assets/favicon/generate.mjs`
Expected: prints "favicon assets written…"; the five files exist in `priv/static/`.

- [ ] **Step 5: Visually verify + tune (inline judgment)**

Create a throwaway `assets/favicon/preview.mjs` (or reuse Playwright) that renders `priv/static/favicon.svg` on a page in BOTH `colorScheme: "light"` and `"dark"`, displayed at 16px, 32px, and 64px, and screenshots it. Confirm:
- the "JN" reads as Lora (serif, the J descends, the N has the right contrast),
- it's legible at 16px,
- light = cream on red, dark = cream on near-black (the bg + text both swap correctly).

If the glyphs are too small/large/off-center or the weight looks wrong, adjust `CAP_FRACTION`/`RADIUS`/the centering in `generate.mjs`, re-run Step 4, re-screenshot. Also open the PNG rasters (`favicon-32.png`, `apple-touch-icon.png`) and confirm they're cream-JN-on-red (not transparent/black). Remove `preview.mjs` when satisfied.

- [ ] **Step 6: Commit**

```bash
git add assets/favicon/generate.mjs assets/package.json assets/pnpm-lock.yaml .gitignore \
  priv/static/favicon.svg priv/static/apple-touch-icon.png priv/static/favicon-96.png \
  priv/static/favicon-32.png priv/static/favicon.ico
git commit -m "$(cat <<'EOF'
Generate a theme-aware JN favicon from Lora

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Wire the favicon into the layouts

**Files:**
- Modify: `lib/newton_web.ex` (`static_paths/0`)
- Modify: `lib/newton_web/components/layouts/root.html.heex`, `lib/newton_web/components/layouts/admin_root.html.heex`
- Test: `test/newton_web/controllers/page_controller_test.exs` (or a layout test)

- [ ] **Step 1: Write the failing test**

In `test/newton_web/controllers/page_controller_test.exs`, add (behavior: the home page head references the theme-aware icon):

```elixir
  test "the page head references the theme-aware favicon", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)
    assert html =~ ~s(rel="icon")
    assert html =~ "/favicon.svg"
    assert html =~ ~s(rel="apple-touch-icon")
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/newton_web/controllers/page_controller_test.exs`
Expected: FAIL — no favicon links in the head yet.

- [ ] **Step 3: Serve the new static files**

In `lib/newton_web.ex`, extend `static_paths/0`:

```elixir
  def static_paths,
    do:
      ~w(assets fonts images favicon.ico favicon.svg favicon-32.png favicon-96.png apple-touch-icon.png robots.txt)
```

- [ ] **Step 4: Add the link tags to both layouts**

In `lib/newton_web/components/layouts/root.html.heex` and
`lib/newton_web/components/layouts/admin_root.html.heex`, add inside `<head>`
(e.g. just after the `theme-color` metas):

```heex
    <link rel="icon" href={~p"/favicon.svg"} type="image/svg+xml" />
    <link rel="icon" href={~p"/favicon-32.png"} sizes="32x32" />
    <link rel="apple-touch-icon" href={~p"/apple-touch-icon.png"} />
```

- [ ] **Step 5: Run the test + precommit**

Run: `mix test test/newton_web/controllers/page_controller_test.exs` → PASS.
Run: `mix precommit` → all green.

- [ ] **Step 6: (Optional) confirm the browser tab in dev**

Build assets, start `PORT=4001 mix phx.server`, load the site, and confirm the
tab shows the JN favicon and that toggling the OS appearance flips its colors.
Stop the server.

- [ ] **Step 7: Commit**

```bash
git add lib/newton_web.ex lib/newton_web/components/layouts/root.html.heex \
  lib/newton_web/components/layouts/admin_root.html.heex \
  test/newton_web/controllers/page_controller_test.exs
git commit -m "$(cat <<'EOF'
Wire the JN favicon into the layouts

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Self-review notes

- **Spec coverage:** Lora-600 JN as SVG paths + `prefers-color-scheme` swap (Task 1, generate.mjs); rounded square, light/dark token colors (Task 1 constants); PNG/ico/apple fallbacks (Task 1 rasters); reproducible generator with dev-only deps (Task 1); `<link>` wiring + `static_paths` (Task 2); no CSP change (favicon is a separate resource — nothing to do); visual + controller-wiring tests (Task 1 Step 5, Task 2). All spec sections covered.
- **Risk note:** the one execution-uncertain spot is the light-variant raster substitution (Step 3 note) and the glyph centering — both are caught by the visual check in Task 1 Step 5 and tuned there. `fontkit.getVariation({wght: 600})` handles the variable Lora correctly; if `font.capHeight` is unavailable, fall back to `font.ascent * 0.7` for the scale target.
- **Consistency:** filenames (`favicon.svg`, `favicon-32.png`, `favicon-96.png`, `apple-touch-icon.png`, `favicon.ico`) are identical across the generator, `static_paths`, and the `<link>` tags.
