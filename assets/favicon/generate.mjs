// Regenerates the favicon assets in priv/static from the Lora font.
// Run: `node assets/favicon/generate.mjs`
import * as fontkit from "fontkit"
import sharp from "sharp"
import pngToIco from "png-to-ico"
import {writeFileSync, existsSync, mkdirSync} from "node:fs"
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

const opened = fontkit.openSync(ttfPath)
const font = (opened.getVariation ? opened.getVariation({wght: 600}) : opened)
const capHeight = font.capHeight || font.ascent * 0.7

const run = font.layout("JN")
const scale = (SIZE * CAP_FRACTION) / capHeight

// Flip Y for SVG coords and lay the glyphs out along the advance.
let penX = 0
const glyphPaths = run.glyphs.map((g, i) => {
  const p = g.path.scale(scale, -scale).translate(penX, 0)
  penX += run.positions[i].xAdvance * scale
  return p
})

// Center the combined bbox in the SIZE×SIZE box.
const boxes = glyphPaths.map((p) => p.bbox)
const minX = Math.min(...boxes.map((b) => b.minX))
const maxX = Math.max(...boxes.map((b) => b.maxX))
const minY = Math.min(...boxes.map((b) => b.minY))
const maxY = Math.max(...boxes.map((b) => b.maxY))
const dx = (SIZE - (maxX - minX)) / 2 - minX
const dy = (SIZE - (maxY - minY)) / 2 - minY
const d = glyphPaths.map((p) => p.translate(dx, dy).toSVG()).join(" ")

// themed: a <style> with a prefers-color-scheme swap.
// literal: hard-coded LIGHT colors, used for the opaque PNG/ico rasters.
function buildSvg({themed}) {
  const fills = themed
    ? `<style>
    :root { --bg: ${LIGHT.bg}; --fg: ${LIGHT.fg}; }
    @media (prefers-color-scheme: dark) { :root { --bg: ${DARK.bg}; --fg: ${DARK.fg}; } }
    .bg { fill: var(--bg); } .fg { fill: var(--fg); }
  </style>`
    : `<style>.bg { fill: ${LIGHT.bg}; } .fg { fill: ${LIGHT.fg}; }</style>`
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${SIZE} ${SIZE}">
  ${fills}
  <rect class="bg" width="${SIZE}" height="${SIZE}" rx="${RADIUS}" ry="${RADIUS}"/>
  <path class="fg" d="${d}"/>
</svg>
`
}

mkdirSync(staticDir, {recursive: true})
writeFileSync(join(staticDir, "favicon.svg"), buildSvg({themed: true}))

const lightSvg = buildSvg({themed: false})
const raster = (size) => sharp(Buffer.from(lightSvg)).resize(size, size).png().toBuffer()

writeFileSync(join(staticDir, "apple-touch-icon.png"), await raster(180))
writeFileSync(join(staticDir, "favicon-96.png"), await raster(96))
writeFileSync(join(staticDir, "favicon-32.png"), await raster(32))
writeFileSync(join(staticDir, "favicon.ico"), await pngToIco([await raster(32), await raster(16)]))

console.log("favicon assets written to priv/static/")
