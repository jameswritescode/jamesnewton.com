// Procedural Canvas2D textures for the Gibson. dataFaceTexture draws a tower
// "screen": dense rows of tiny glowing characters, small framed readout boxes,
// and bar patterns, in `hex` on near-black. Reused across towers (a few
// variants, not one per tower).
import * as THREE from "three"

const CHARS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ:/.-=+*#<>[]"

function hexStr(hex) {
  return "#" + hex.toString(16).padStart(6, "0")
}

// Row pitch divides every canvas height exactly (2048/16, 512/16), and rows
// are drawn over the FULL canvas — so the y-wrap seam under UV scrolling is
// just another inter-row gap, not a bare black band parading around the face.
const FACE_LINE_H = 16
const BASELINE = 12 // glyphs occupy [row+3, row+14] within each 16px band

// One row of screen furniture: glyph runs, framed readout boxes, little bars.
// Shared by faces, rooftops, and the live character-cycling. `dim` scales all
// alphas (rooftops run slightly dimmer so the aerial view doesn't blow out).
function drawFaceRow(ctx, w, y, col, rand, dim = 1) {
  ctx.font = "10px monospace"
  ctx.textBaseline = "alphabetic"
  let x = 6
  while (x < w - 6) {
    const roll = rand()
    if (roll < 0.1) {
      // a framed readout box
      const bw = Math.min(w - 12 - x, 18 + ((rand() * 40) | 0))
      ctx.globalAlpha = 0.45 * dim
      ctx.strokeStyle = col
      ctx.lineWidth = 1
      ctx.strokeRect(x, y - 9, bw, 11)
      x += bw + 6
    } else if (roll < 0.16) {
      // a little bar
      const bw = 8 + ((rand() * 22) | 0)
      ctx.globalAlpha = (0.3 + rand() * 0.5) * dim
      ctx.fillStyle = col
      ctx.fillRect(x, y - 7, bw, 7)
      x += bw + 6
    } else {
      const n = 2 + ((rand() * 7) | 0)
      let s = ""
      for (let i = 0; i < n; i++) s += CHARS[(rand() * CHARS.length) | 0]
      ctx.globalAlpha = (0.55 + rand() * 0.4) * dim
      ctx.fillStyle = col
      ctx.fillText(s, x, y)
      x += ctx.measureText(s).width + 6
    }
  }
}

// Bright VERTICAL edge lines only: the texture scrolls in y at runtime, so a
// horizontal frame line would visibly ride up the face. The rooftop rim glow
// comes from roofTexture instead.
function drawFaceEdges(ctx, w, h, col) {
  ctx.globalAlpha = 1
  ctx.strokeStyle = col
  ctx.lineWidth = 4
  ctx.beginPath()
  ctx.moveTo(2, 0)
  ctx.lineTo(2, h)
  ctx.moveTo(w - 2, 0)
  ctx.lineTo(w - 2, h)
  ctx.stroke()
}

export function dataFaceTexture(hex, rand = Math.random, w = 256) {
  const h = w * 4 // slabs are tall
  const cv = document.createElement("canvas")
  cv.width = w
  cv.height = h
  const ctx = cv.getContext("2d")
  ctx.fillStyle = "#02030a"
  ctx.fillRect(0, 0, w, h)

  const col = hexStr(hex)
  for (let k = 0; k < h / FACE_LINE_H; k++) {
    drawFaceRow(ctx, w, k * FACE_LINE_H + BASELINE, col, rand)
  }
  drawFaceEdges(ctx, w, h, col)

  const tex = new THREE.CanvasTexture(cv)
  tex.colorSpace = THREE.SRGBColorSpace
  tex.anisotropy = 4
  tex.wrapT = THREE.RepeatWrapping // runtime y-scroll (data streaming up the face)
  return tex
}

// Redraw a random band of rows on a face/roof texture (the "cycling characters"
// animation): a few lines of glyphs change, the rest stay put. Cheap enough to
// round-robin one texture at a time from the render loop. The band is drawn
// under a clip so the edge/rim glow is never disturbed, then the edges are
// re-stroked.
export function cycleFaceRows(tex, hex, rand = Math.random, {rim = false, dim = 1} = {}) {
  const cv = tex.image
  const ctx = cv.getContext("2d")
  const col = hexStr(hex)
  const rows = 3 + ((rand() * 4) | 0)
  const k0 = (rand() * (cv.height / FACE_LINE_H - rows)) | 0
  ctx.save()
  ctx.beginPath()
  ctx.rect(0, k0 * FACE_LINE_H, cv.width, rows * FACE_LINE_H)
  ctx.clip()
  ctx.fillStyle = "#02030a"
  ctx.fillRect(0, k0 * FACE_LINE_H, cv.width, rows * FACE_LINE_H)
  for (let r = 0; r < rows; r++) {
    drawFaceRow(ctx, cv.width, (k0 + r) * FACE_LINE_H + BASELINE, col, rand, dim)
  }
  ctx.restore()
  if (rim) {
    ctx.globalAlpha = 1
    ctx.strokeStyle = col
    ctx.lineWidth = 6
    ctx.strokeRect(3, 3, cv.width - 6, cv.height - 6)
  } else {
    drawFaceEdges(ctx, cv.width, cv.height, col)
  }
  tex.needsUpdate = true
}

// Rooftop cap: the same dense data-screen language as the faces (shared row
// painter, slightly dimmed), square, framed by a bright rim so tower tops glow
// at their edges from above.
export const ROOF_DIM = 0.75

export function roofTexture(hex, rand = Math.random, size = 512) {
  const cv = document.createElement("canvas")
  cv.width = cv.height = size
  const ctx = cv.getContext("2d")
  ctx.fillStyle = "#02030a"
  ctx.fillRect(0, 0, size, size)

  const col = hexStr(hex)
  for (let k = 0; k < size / FACE_LINE_H; k++) {
    drawFaceRow(ctx, size, k * FACE_LINE_H + BASELINE, col, rand, ROOF_DIM)
  }

  // glowing rim — the tower's top edges
  ctx.globalAlpha = 1
  ctx.strokeStyle = col
  ctx.lineWidth = 6
  ctx.strokeRect(3, 3, size - 6, size - 6)

  const tex = new THREE.CanvasTexture(cv)
  tex.colorSpace = THREE.SRGBColorSpace
  tex.anisotropy = 4
  return tex
}

// The landing tower's street-facing screen: the actual site links rendered as
// big glowing menu rows (the movie's Gibson tower menu), over a dimmed field
// of the standard data-screen furniture. The camera's final look target sits
// at ~72% of tower height, so the menu block is centred there. This face
// neither scrolls nor cycles, but it IS interactive after the flight parks:
// `draw(hoverIndex)` re-renders the rows with one highlighted. The dimmed
// background field is painted once and cached, so redraws never re-randomise.
export const MENU_CENTER_V = 0.28 // texture-v of the camera's landing look target
export const MENU_TEX_W = 1024 // hi-res: the parked camera sits close to this face

// `items` is [{name, desc, url}] read from the DOM menu. The menu is drawn as
// the tower's SYSTEM ACCESS PANEL: a framed block with a header, numbered link
// rows (index · name · dot leaders · destination host) and a status footer —
// hierarchy and full-width structure instead of a floating text list. The
// hovered row inverts and reveals its description. `blockPx` is the total
// vertical budget (what the parked camera can see); the panel divides it.
export function menuFaceTexture(hex, rand = Math.random, items = [], w = MENU_TEX_W, blockPx = 600) {
  const h = w * 4
  const col = hexStr(hex)
  const SILK = "#9fd8ff"

  // static background field, drawn once
  const base = document.createElement("canvas")
  base.width = w
  base.height = h
  {
    const bctx = base.getContext("2d")
    bctx.fillStyle = "#02030a"
    bctx.fillRect(0, 0, w, h)
    // FULL standard brightness: before the panel opens this face must be
    // indistinguishable from every other tower — no spoilers.
    for (let k = 0; k < h / FACE_LINE_H; k++) {
      drawFaceRow(bctx, w, k * FACE_LINE_H + BASELINE, col, rand)
    }
    drawFaceEdges(bctx, w, h, col)
  }

  const cv = document.createElement("canvas")
  cv.width = w
  cv.height = h
  const ctx = cv.getContext("2d")
  const tex = new THREE.CanvasTexture(cv)
  tex.colorSpace = THREE.SRGBColorSpace
  tex.anisotropy = 4

  // panel geometry within the visible budget
  const headerH = blockPx * 0.14
  const footerH = blockPx * 0.09
  const rowH = (blockPx - headerH - footerH) / Math.max(1, items.length)
  const top = h * MENU_CENTER_V - blockPx / 2
  const y0 = top + headerH + rowH / 2 // centre of the first row
  const X0 = 64
  const X1 = w - 64

  // decorative strings are rolled ONCE — hover redraws must not reshuffle them
  const glyphs = (n) => {
    let s = ""
    for (let i = 0; i < n; i++) s += CHARS[(rand() * CHARS.length) | 0]
    return s
  }
  const nodeTag = `NODE ${glyphs(2)}.${glyphs(2)}`
  const footerTag = `SECTOR ${glyphs(4)} ▮ UPLINK ${(88 + rand() * 11).toFixed(1)}% ▮ ${glyphs(6)}`

  const hostOf = (u) => {
    if (!u || u === "/") return "jamesnewton.com"
    return u
      .replace(/^https?:\/\//, "")
      .replace(/^mailto:/, "")
      .replace(/^www\./, "")
      .replace(/\/$/, "")
  }

  // draw(hover, openK): openK ∈ [0,1] is how far the panel window has opened —
  // 0 = not there (bare data field), 0..0.35 = a bright centre line expanding
  // horizontally, 0.35..1 = the window opening vertically from the centre.
  // Both args are sticky, so hover redraws keep the current openness and the
  // opening animation keeps the current hover.
  let lastHover = -1
  let lastK = 1
  function draw(hover = lastHover, openK = lastK) {
    lastHover = hover
    lastK = openK
    ctx.globalAlpha = 1
    ctx.drawImage(base, 0, 0)
    if (openK <= 0) {
      tex.needsUpdate = true
      return
    }
    // Phase one of the opening: the face dims down (as if the tower cuts its
    // display over to the access panel), synced with the centre line expanding.
    ctx.globalAlpha = 0.7 * Math.min(1, openK / 0.35)
    ctx.fillStyle = "#02030a"
    ctx.fillRect(0, 0, w, h)
    ctx.globalAlpha = 1
    drawFaceEdges(ctx, w, h, col) // the tower's edge glow never dims
    const panelX = X0 - 26
    const panelW = X1 - X0 + 52
    const cx = panelX + panelW / 2
    const cy = top + blockPx / 2
    const clipping = openK < 1
    if (clipping) {
      const wk = Math.min(1, openK / 0.35)
      const hk = Math.max(0, (openK - 0.35) / 0.65)
      const halfW = (panelW / 2) * wk
      const halfH = Math.max(2, (blockPx / 2) * hk)
      // bright shutter edges while opening
      ctx.globalAlpha = 0.95
      ctx.strokeStyle = col
      ctx.shadowColor = col
      ctx.shadowBlur = 14
      ctx.lineWidth = 3
      ctx.beginPath()
      ctx.moveTo(cx - halfW, cy - halfH)
      ctx.lineTo(cx + halfW, cy - halfH)
      ctx.moveTo(cx - halfW, cy + halfH)
      ctx.lineTo(cx + halfW, cy + halfH)
      ctx.stroke()
      ctx.shadowBlur = 0
      ctx.save()
      ctx.beginPath()
      ctx.rect(cx - halfW, cy - halfH, halfW * 2, halfH * 2)
      ctx.clip()
    }
    ctx.textBaseline = "middle"

    // panel plate + frame
    ctx.globalAlpha = 0.88
    ctx.fillStyle = "#02030a"
    ctx.fillRect(X0 - 26, top, X1 - X0 + 52, blockPx)
    ctx.globalAlpha = 0.55
    ctx.strokeStyle = col
    ctx.lineWidth = 2
    ctx.strokeRect(X0 - 26, top, X1 - X0 + 52, blockPx)

    // header: title left, node tag right, double rule beneath
    const headY = top + headerH * 0.48
    ctx.globalAlpha = 1
    ctx.fillStyle = col
    ctx.shadowColor = col
    ctx.shadowBlur = 8
    ctx.font = `bold ${Math.round(headerH * 0.34)}px monospace`
    ctx.fillText("JN.SYS // ACCESS NODE", X0, headY)
    ctx.shadowBlur = 0
    ctx.globalAlpha = 0.55
    ctx.fillStyle = SILK
    ctx.font = `${Math.round(headerH * 0.22)}px monospace`
    const tagW = ctx.measureText(nodeTag).width
    ctx.fillText(nodeTag, X1 - tagW, headY)
    ctx.globalAlpha = 0.6
    ctx.strokeStyle = col
    ctx.lineWidth = 2
    ctx.beginPath()
    ctx.moveTo(X0 - 10, top + headerH - 8)
    ctx.lineTo(X1 + 10, top + headerH - 8)
    ctx.moveTo(X0 - 10, top + headerH - 3)
    ctx.lineTo(X1 + 10, top + headerH - 3)
    ctx.stroke()

    // link rows
    const nameSize = Math.round(rowH * 0.32)
    const metaSize = Math.round(rowH * 0.2)
    items.forEach((item, i) => {
      const y = y0 + i * rowH
      const hot = i === hover
      if (hot) {
        ctx.globalAlpha = 0.18
        ctx.fillStyle = col
        ctx.fillRect(X0 - 16, y - rowH / 2 + 3, X1 - X0 + 32, rowH - 6)
      }
      // index
      ctx.globalAlpha = hot ? 0.9 : 0.45
      ctx.fillStyle = col
      ctx.font = `${metaSize}px monospace`
      ctx.fillText(`0${i + 1}`, X0, y - rowH * 0.1)
      // name — hover steps brighter than idle without going white-hot:
      // near-white fill punches far above the bloom threshold and flares.
      ctx.globalAlpha = 1
      ctx.fillStyle = hot ? "#7fdfff" : col
      ctx.shadowColor = col
      ctx.shadowBlur = hot ? 8 : 6
      ctx.font = `bold ${nameSize}px monospace`
      ctx.fillText(item.name, X0 + metaSize * 2.6, y - rowH * 0.1)
      ctx.shadowBlur = 0
      const nameEnd = X0 + metaSize * 2.6 + ctx.measureText(item.name).width
      // destination host, right-aligned
      ctx.font = `${metaSize}px monospace`
      let hostText = hostOf(item.url)
      while (ctx.measureText(hostText).width > (X1 - nameEnd) * 0.6 && hostText.length > 8) {
        hostText = hostText.slice(0, -2)
      }
      const hostW = ctx.measureText(hostText).width
      ctx.globalAlpha = hot ? 0.95 : 0.5
      ctx.fillStyle = SILK
      ctx.fillText(hostText, X1 - hostW, y - rowH * 0.1)
      // dot leaders between name and host
      ctx.globalAlpha = 0.22
      ctx.strokeStyle = col
      ctx.lineWidth = 2
      ctx.setLineDash([2, 8])
      ctx.beginPath()
      ctx.moveTo(nameEnd + 24, y - rowH * 0.1)
      ctx.lineTo(X1 - hostW - 24, y - rowH * 0.1)
      ctx.stroke()
      ctx.setLineDash([])
      // description on the hovered row
      if (hot && item.desc) {
        let dsize = metaSize
        ctx.font = `${dsize}px monospace`
        while (ctx.measureText(item.desc).width > X1 - X0 - metaSize * 2.6 && dsize > 11) {
          dsize -= 1
          ctx.font = `${dsize}px monospace`
        }
        ctx.globalAlpha = 0.85
        ctx.fillStyle = SILK
        ctx.fillText(item.desc, X0 + metaSize * 2.6, y + rowH * 0.26)
      }
      // hairline rule between rows
      if (i < items.length - 1) {
        ctx.globalAlpha = 0.14
        ctx.strokeStyle = col
        ctx.lineWidth = 1
        ctx.beginPath()
        ctx.moveTo(X0 - 10, y + rowH / 2)
        ctx.lineTo(X1 + 10, y + rowH / 2)
        ctx.stroke()
      }
    })

    // footer status line
    ctx.globalAlpha = 0.4
    ctx.fillStyle = SILK
    ctx.font = `${Math.round(footerH * 0.34)}px monospace`
    const footY = top + blockPx - footerH * 0.5
    ctx.fillText(hover >= 0 ? `OPEN: ${hostOf(items[hover]?.url)}` : footerTag, X0, footY)

    if (clipping) ctx.restore()
    ctx.textBaseline = "alphabetic"
    tex.needsUpdate = true
  }
  draw()

  return {tex, draw, y0, rowH}
}

// The street floor: one texture BLOCK spans a `cells` x `cells` patch of city
// (default 4x4), aligned so street lines land on cell boundaries. Every street
// inside the block gets its own bus layout — the visible repeat period is the
// whole block, not a single cell — while full-length buses keep neighbouring
// blocks connected by construction. Elements are drawn CHUNKY (wide traces,
// big vias/pads/labels) so the board reads from flight height, not just up
// close. Anything near a block edge is drawn with wrap copies for seamlessness.
export function floorTexture(rand = Math.random, towerFrac = 0.3, cells = 4, cellPx = 512) {
  const T = cells * cellPx
  const cv = document.createElement("canvas")
  cv.width = cv.height = T
  const ctx = cv.getContext("2d")
  // Indigo PCB substrate, not dead black — the board reads as a material and
  // sits better against the neon than a void (and raises the darkest level,
  // which is kinder to local-dimming displays).
  ctx.fillStyle = "#0e0b23"
  ctx.fillRect(0, 0, T, T)
  const PALETTE = ["#ff31d9", "#c94bff", "#3a7bff"]
  const SILK = "#9fd8ff" // silkscreen ink
  const laneHalf = ((1 - towerFrac) / 2) * 0.8 * cellPx // lane band beside each street line
  const pick = (arr) => arr[(rand() * arr.length) | 0]
  const mod = (v) => ((v % T) + T) % T

  // 5x5 wrap copies: routed traces can wander up to ~2 block-widths from their
  // start, so one ring of copies isn't always enough for seamless tiling.
  const wrapped = (draw) => {
    for (const dx of [-2 * T, -T, 0, T, 2 * T]) {
      for (const dz of [-2 * T, -T, 0, T, 2 * T]) {
        ctx.save()
        ctx.translate(dx, dz)
        draw()
        ctx.restore()
      }
    }
  }

  // big soft "copper pour" zones — large tonal patches that break up the
  // substrate the way ground pours patch a real board
  for (let i = 0; i < 9; i++) {
    const px = rand() * T
    const pz = rand() * T
    const w = (0.2 + rand() * 0.5) * cellPx * 2
    const h = (0.2 + rand() * 0.5) * cellPx * 2
    const lighter = rand() < 0.55
    wrapped(() => {
      ctx.globalAlpha = 0.5
      ctx.fillStyle = lighter ? "#151140" : "#0a081c"
      ctx.fillRect(px, pz, w, h)
    })
  }

  // ground-plane dot grid — texture in the "empty" areas
  ctx.fillStyle = SILK
  ctx.globalAlpha = 0.1
  for (let gx = 24; gx < T; gx += 48) {
    for (let gz = 24; gz < T; gz += 48) {
      ctx.fillRect(gx, gz, 3, 3)
    }
  }

  // every tower footprint is a CHIP: dark package, silkscreen part label, a
  // ring of solder pads, and breakout traces running into the lanes
  const pw = towerFrac * cellPx
  for (let cx = 0; cx < cells; cx++) {
    for (let cz = 0; cz < cells; cz++) {
      const x0 = (cx + 0.5) * cellPx - pw / 2
      const z0 = (cz + 0.5) * cellPx - pw / 2
      ctx.globalAlpha = 1
      ctx.fillStyle = "#04030c"
      ctx.fillRect(x0, z0, pw, pw)
      ctx.globalAlpha = 0.55
      ctx.strokeStyle = pick(PALETTE)
      ctx.lineWidth = 4
      ctx.strokeRect(x0, z0, pw, pw)
      ctx.globalAlpha = 0.32
      ctx.fillStyle = SILK
      ctx.font = "24px monospace"
      ctx.fillText("JN-" + ((rand() * 9000 + 1000) | 0), x0 + pw * 0.14, z0 + pw * 0.55)
      const padN = 6
      const padPitch = pw / padN
      for (let i = 0; i < padN; i++) {
        const along = padPitch * (i + 0.5) - 6
        ctx.globalAlpha = 0.6
        ctx.fillStyle = pick(PALETTE)
        ctx.fillRect(x0 + along, z0 - 12, 12, 7)
        ctx.fillRect(x0 + along, z0 + pw + 5, 12, 7)
        ctx.fillRect(x0 - 12, z0 + along, 7, 12)
        ctx.fillRect(x0 + pw + 5, z0 + along, 7, 12)
        if (rand() < 0.3) {
          const len = 40 + rand() * 120
          ctx.globalAlpha = 0.55
          ctx.strokeStyle = ctx.fillStyle
          ctx.lineWidth = 3
          ctx.beginPath()
          const side = (rand() * 4) | 0
          if (side === 0) (ctx.moveTo(x0 + along + 6, z0 - 12), ctx.lineTo(x0 + along + 6, z0 - 12 - len))
          if (side === 1) (ctx.moveTo(x0 + along + 6, z0 + pw + 12), ctx.lineTo(x0 + along + 6, z0 + pw + 12 + len))
          if (side === 2) (ctx.moveTo(x0 - 12, z0 + along + 6), ctx.lineTo(x0 - 12 - len, z0 + along + 6))
          if (side === 3) (ctx.moveTo(x0 + pw + 12, z0 + along + 6), ctx.lineTo(x0 + pw + 12 + len, z0 + along + 6))
          ctx.stroke()
        }
      }
    }
  }

  // Arterial through-buses: 1-2 per street. These are the only full-length
  // straight runs (they carry continuity across block boundaries); everything
  // else is routed with turns.
  const vias = []
  for (const axis of ["v", "h"]) {
    for (let k = 0; k < cells; k++) {
      const line = k * cellPx
      const nBundles = 1 + ((rand() * 2) | 0)
      for (let b = 0; b < nBundles; b++) {
        const nTraces = 2 + ((rand() * 3) | 0)
        const pitch = 13
        const base = (rand() * 2 - 1) * (laneHalf - nTraces * pitch)
        const bundleColor = pick(PALETTE)
        for (let i = 0; i < nTraces; i++) {
          const off = mod(line + base + i * pitch)
          const width = rand() < 0.25 ? 9 : rand() < 0.5 ? 7 : 5
          const alpha = 0.75 + rand() * 0.25
          const dodge = rand() < 0.4
          const s0 = (0.1 + rand() * 0.7) * T
          const d = (rand() < 0.5 ? -1 : 1) * (16 + rand() * 18)
          const L = (0.03 + rand() * 0.08) * T
          // colour rolled OUTSIDE wrapped — inside, each wrap copy would roll
          // its own, letting an edge-crossing trace change colour mid-line
          const traceColor = rand() < 0.85 ? bundleColor : pick(PALETTE)
          wrapped(() => {
            ctx.strokeStyle = traceColor
            ctx.lineJoin = "round"
            ctx.beginPath()
            const pts = dodge
              ? [[off, 0], [off, s0], [off + d, s0 + Math.abs(d)], [off + d, s0 + Math.abs(d) + L], [off, s0 + 2 * Math.abs(d) + L], [off, T]]
              : [[off, 0], [off, T]]
            pts.forEach(([a, s], j) => {
              const [x, z] = axis === "v" ? [a, s] : [s, a]
              j === 0 ? ctx.moveTo(x, z) : ctx.lineTo(x, z)
            })
            // neon: soft halo under a bright core (dimmer than the tower rims)
            ctx.globalAlpha = 0.2
            ctx.lineWidth = width * 2.8
            ctx.stroke()
            ctx.globalAlpha = alpha
            ctx.lineWidth = width
            ctx.stroke()
          })
          const nVias = 2 + ((rand() * 3) | 0)
          for (let v = 0; v < nVias; v++) {
            const s = rand() * T
            vias.push(axis === "v" ? [off, s] : [s, off])
          }
        }
      }
    }
  }
  for (const [vx, vz] of vias) {
    const color = pick(PALETTE)
    wrapped(() => {
      ctx.globalAlpha = 0.85
      ctx.fillStyle = color
      ctx.beginPath()
      ctx.arc(vx, vz, 8, 0, Math.PI * 2)
      ctx.fill()
      ctx.globalAlpha = 1
      ctx.fillStyle = "#020207"
      ctx.beginPath()
      ctx.arc(vx, vz, 3.5, 0, Math.PI * 2)
      ctx.fill()
    })
  }

  // ROUTED traces: the bulk of the board. Each starts on a street, runs along
  // it, TURNS at an intersection with a 45° chamfer onto the cross street
  // (possibly turning again), and terminates in a via or a pad — real PCB
  // routing instead of endless straight lanes. Paths may cross block edges;
  // the wrap copies keep them seamless.
  for (let i = 0; i < 44; i++) {
    const color = pick(PALETTE)
    const width = rand() < 0.3 ? 7 : rand() < 0.5 ? 5 : 3.5
    const alpha = 0.5 + rand() * 0.4
    const ch = 16 + rand() * 12 // 45° chamfer size

    // absolute-coordinate walk on the street lattice
    let axis = rand() < 0.5 ? "v" : "h" // v: travelling in z, h: travelling in x
    const startLine = ((rand() * cells) | 0) * cellPx
    const startOff = (rand() * 2 - 1) * laneHalf * 0.9
    let x = axis === "v" ? startLine + startOff : rand() * T
    let z = axis === "v" ? rand() * T : startLine + startOff
    const pts = [[x, z]]
    const legs = 1 + ((rand() * 3) | 0)
    for (let leg = 0; leg < legs; leg++) {
      // pick a cross-street 1-2 cells ahead and a lane offset on it
      const along = axis === "v" ? z : x
      const dir = rand() < 0.5 ? -1 : 1
      const crossLine = (Math.round(along / cellPx) + dir * (1 + ((rand() * 2) | 0))) * cellPx
      const crossLane = crossLine + (rand() * 2 - 1) * laneHalf * 0.9
      const turnDir = rand() < 0.5 ? -1 : 1 // travel direction on the new street
      const dirA = Math.sign(crossLane - along) || 1 // approach direction
      if (axis === "v") {
        pts.push([x, crossLane - dirA * ch]) // straight to the chamfer
        pts.push([x + turnDir * ch, crossLane]) // 45° corner
        z = crossLane
        x = x + turnDir * ch
      } else {
        pts.push([crossLane - dirA * ch, z])
        pts.push([crossLane, z + turnDir * ch])
        x = crossLane
        z = z + turnDir * ch
      }
      axis = axis === "v" ? "h" : "v"
    }
    // final straight run, then terminate
    const runOut = (0.2 + rand() * 0.5) * cellPx
    const dirEnd = rand() < 0.5 ? -1 : 1
    if (axis === "v") z += dirEnd * runOut
    else x += dirEnd * runOut
    pts.push([x, z])

    const endsInVia = rand() < 0.6
    wrapped(() => {
      ctx.strokeStyle = color
      ctx.lineJoin = "round"
      ctx.beginPath()
      pts.forEach(([px, pz], j) => (j === 0 ? ctx.moveTo(px, pz) : ctx.lineTo(px, pz)))
      // neon: soft halo under a bright core (dimmer than the tower rims)
      ctx.globalAlpha = 0.2
      ctx.lineWidth = width * 2.8
      ctx.stroke()
      ctx.globalAlpha = Math.min(1, alpha + 0.3)
      ctx.lineWidth = width
      ctx.stroke()
      ctx.globalAlpha = 0.85
      ctx.fillStyle = color
      if (endsInVia) {
        ctx.beginPath()
        ctx.arc(x, z, 8, 0, Math.PI * 2)
        ctx.fill()
        ctx.fillStyle = "#0e0b23"
        ctx.beginPath()
        ctx.arc(x, z, 3.5, 0, Math.PI * 2)
        ctx.fill()
      } else {
        ctx.fillRect(x - 7, z - 7, 14, 14)
      }
    })
  }

  // BIG silkscreen labels along the lanes — the towers' glyph DNA on the board
  for (let i = 0; i < 14; i++) {
    const along = rand() < 0.5 ? "v" : "h"
    const line = ((rand() * cells) | 0) * cellPx
    const lane = mod(line + (rand() * 2 - 1) * laneHalf * 0.9)
    const s0 = rand() * T
    let s = ""
    const n = 3 + ((rand() * 5) | 0)
    for (let c = 0; c < n; c++) s += CHARS[(rand() * CHARS.length) | 0]
    wrapped(() => {
      ctx.save()
      ctx.globalAlpha = 0.3 + rand() * 0.2
      ctx.fillStyle = SILK
      ctx.font = "22px monospace"
      if (along === "v") {
        ctx.translate(lane, s0)
        ctx.rotate(-Math.PI / 2)
        ctx.fillText(s, 0, 0)
      } else {
        ctx.fillText(s, s0, lane)
      }
      ctx.restore()
    })
  }

  // pad arrays scattered near intersections
  for (let i = 0; i < 12; i++) {
    const ix = ((rand() * cells) | 0) * cellPx
    const iz = ((rand() * cells) | 0) * cellPx
    const cx = mod(ix + (rand() * 2 - 1) * laneHalf * 0.6)
    const cz = mod(iz + (rand() * 2 - 1) * laneHalf * 0.6)
    const color = pick(PALETTE)
    wrapped(() => {
      ctx.globalAlpha = 0.85
      ctx.fillStyle = color
      for (let px = 0; px < 3; px++) {
        for (let pz = 0; pz < 2; pz++) {
          ctx.fillRect(cx + px * 14, cz + pz * 14, 9, 9)
        }
      }
    })
  }

  const tex = new THREE.CanvasTexture(cv)
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping
  tex.colorSpace = THREE.SRGBColorSpace
  return tex
}
