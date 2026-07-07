// Builds the Gibson: the endless data-tower city, the circuit-board floor
// (board.js), the flight camera along the generated route (path.js), and the
// landing tower whose street face is the site's link menu. Returns
// {render(t), dispose, menu, ...} for the flight controller in gibson.js.
//
// Determinism: one seeded RNG drives all procedural city content, so the
// order of rand() consumption below IS the scene's identity — keep creation
// order stable (textures → board activity → tower partition → menu face →
// floor) or every screenshot comparison breaks. The route uses its own RNG
// stream (random per load; see sceneSeeds) so the flight never reshuffles
// the fixed city.
import * as THREE from "three"
import {EffectComposer} from "three/examples/jsm/postprocessing/EffectComposer.js"
import {RenderPass} from "three/examples/jsm/postprocessing/RenderPass.js"
import {UnrealBloomPass} from "three/examples/jsm/postprocessing/UnrealBloomPass.js"
import {generateRoute, makeRng} from "./path.js"
import {sceneSeeds} from "../gibson_gate.js"
import {createBoardActivity, createFloor} from "./board.js"
import {createPathRibbon, setupOverview} from "./debug.js"
import {
  dataFaceTexture,
  cycleFaceRows,
  menuFaceTexture,
  MENU_TEX_W,
  roofTexture,
  ROOF_DIM,
} from "./textures.js"

// Streets are ~2.3x the tower footprint (towerFrac 0.3 → 13.2 wide towers on
// 44-unit cells) so the camera always has breathing room, and rows are porous —
// you see through the gaps into deeper rows. The grid is large and the route
// stays central, so from anywhere on the flight the nearest edge is beyond the
// fog-opaque distance: the city reads as endless.
export const GRID = {cols: 44, rows: 44, spacing: 44, towerFrac: 0.3}

// Aspect-adaptive FOV. A fixed *vertical* FOV fish-eyes badly on wide/short
// viewports (e.g. 1512x397 => ~126° horizontal FOV, which warps geometry and
// makes near towers loom). We instead cap the HORIZONTAL FOV, then also cap the
// vertical FOV so tall windows don't fish-eye the other way. three's camera.fov
// is vertical degrees, so we solve for the vertical FOV that yields HFOV_MAX and
// clamp it to VFOV_MAX. Result: natural, consistent corridor framing everywhere.
const HFOV_MAX = 75 // degrees — horizontal field of view cap
const VFOV_MAX = 58 // degrees — vertical field of view cap
const DEG = Math.PI / 180
function applyCameraFov(camera, aspect) {
  const vFromH = (2 * Math.atan(Math.tan((HFOV_MAX * DEG) / 2) / aspect)) / DEG
  camera.fov = Math.min(VFOV_MAX, vFromH)
  camera.aspect = aspect
  camera.updateProjectionMatrix()
}

export function buildScene(canvas, win, {still = false, mode = "flight"} = {}) {
  const w = win.innerWidth
  const h = win.innerHeight
  // Fixed city, random flight: the skyline is identical every visit while the
  // route through it varies per load (seed policy + overrides live in
  // sceneSeeds). Separate RNG streams so the camera route is independent of
  // how many draws the towers/textures make.
  const seeds = sceneSeeds(win)
  const rand = makeRng(seeds.city)
  const routeRand = makeRng(seeds.route)
  win.console.info(`[gibson] route seed ${seeds.route} — replay with ?routeSeed=${seeds.route}`)

  // antialias:false — all rendering goes through the EffectComposer's
  // (non-MSAA) targets, so canvas MSAA is never applied; requesting it just
  // forces a multisampled default framebuffer that costs resolve time for
  // nothing. Edge quality comes from the devicePixelRatio-scaled buffer.
  const renderer = new THREE.WebGLRenderer({canvas, antialias: false})
  renderer.setPixelRatio(Math.min(win.devicePixelRatio || 1, 2))
  renderer.setSize(w, h, false)

  const scene = new THREE.Scene()
  scene.background = new THREE.Color(0x010108)
  // The "endless city" fade. Light enough that deep rows stay visible from the
  // street; the high opening is the only sightline that clears the rooftops,
  // and the grid edge (~890 away from up there) is still fully swallowed.
  scene.fog = new THREE.FogExp2(0x010108, 0.0022)

  const camera = new THREE.PerspectiveCamera(60, w / h, 0.1, 2000)
  applyCameraFov(camera, w / h)

  // --- tower materials -------------------------------------------------------
  // Data-slab towers: uniform-height slabs whose faces are procedural data
  // screens (a few reused textures; mostly cyan). Sides glow with the data
  // face; tops are dim rooftop screens with a glowing rim; bottoms stay black.
  const PALETTE = [0x19c9ff, 0x19c9ff, 0x8ff6ff, 0xc94bff, 0xff31d9, 0xb6ff00]
  const faceTexes = PALETTE.map((hex) => dataFaceTexture(hex, rand, 512))
  const roofTexes = PALETTE.map((hex) => roofTexture(hex, rand))
  const roofMats = roofTexes.map((tex) => new THREE.MeshBasicMaterial({map: tex, fog: true}))
  const capMat = new THREE.MeshBasicMaterial({color: 0x05060d, fog: true})
  const slabMats = faceTexes.map((tex, i) => {
    const side = new THREE.MeshBasicMaterial({map: tex, fog: true})
    return [side, side, roofMats[i], capMat, side, side] // +x -x +y -y +z -z
  })
  const H = GRID.spacing * 2 // uniform tower height
  const foot = GRID.spacing * GRID.towerFrac
  const slabGeo = new THREE.BoxGeometry(foot, H, foot)
  const disposables = [
    slabGeo,
    capMat,
    ...faceTexes,
    ...roofTexes,
    ...roofMats,
    ...slabMats.map((m) => m[0]),
  ]

  // --- live tower "data" animation -------------------------------------------
  // Per-group personalities: some groups stream their glyphs up or down
  // (wall-clock UV scroll), the non-scrolling HOT groups read as active
  // terminals — several chunks of their faces re-write every tick — and
  // everything else mutates on a slow background rotation.
  const SCROLL_PER_SEC = [0.05, -0.03, 0, 0.06, -0.08, 0] // 0 = static → a HOT group
  const HOT = SCROLL_PER_SEC.flatMap((v, i) => (v === 0 ? [i] : []))
  const bgTargets = [
    ...faceTexes.flatMap((tex, i) =>
      SCROLL_PER_SEC[i] === 0 ? [] : [{tex, hex: PALETTE[i], opts: {}}],
    ),
    ...roofTexes.map((tex, i) => ({tex, hex: PALETTE[i], opts: {rim: true, dim: ROOF_DIM}})),
  ]
  let hotAt = 0
  let bgAt = 0
  let bgIdx = 0
  function animateData(t, now) {
    if (still) return // reduced motion: no scroll, no character cycling
    const sec = now / 1000
    faceTexes.forEach((tex, i) => {
      tex.offset.y = SCROLL_PER_SEC[i] * sec
    })
    // No character-cycling during the aerial opening: a band redraw repaints on
    // EVERY instance of its texture group at once, and with the whole minified
    // city in frame that reads as a faint city-wide flicker. From street level
    // only a few large faces share a texture, so the same update reads as a
    // local text change. UV scroll is sub-pixel smooth, so it always runs.
    if (t < 0.35) return
    if (now - hotAt > 70) {
      hotAt = now
      const gi = HOT[(rand() * HOT.length) | 0]
      const bands = 3 + ((rand() * 4) | 0)
      for (let b = 0; b < bands; b++) cycleFaceRows(faceTexes[gi], PALETTE[gi], rand)
    }
    if (now - bgAt > 450) {
      bgAt = now
      bgIdx = (bgIdx + 1) % bgTargets.length
      const c = bgTargets[bgIdx]
      cycleFaceRows(c.tex, c.hex, rand, c.opts)
    }
  }

  // --- board activity (pulses + pads) ----------------------------------------
  const {animateBoard} = createBoardActivity(scene, GRID, rand, disposables, still)

  // --- route -----------------------------------------------------------------
  // Aspect-aware landing distance: the parked camera must fit the menu panel
  // in its HORIZONTAL view. Wide screens have generous hFov (park close);
  // portrait phones have a narrow one (park further back), clamped so the
  // camera never backs into the opposite tower row.
  const hFovRad = 2 * Math.atan(Math.tan((camera.fov * DEG) / 2) * camera.aspect)
  const panelHalfUnits = foot * 0.47 + 0.6 // panel half-width + margin, world units
  const endDistFrac = Math.min(
    0.56,
    Math.max(0.34, panelHalfUnits / Math.tan(hFovRad / 2) / GRID.spacing),
  )
  const route = generateRoute(GRID, routeRand, endDistFrac)

  let menuApi = null
  let menuOpen = null
  // --- the city -------------------------------------------------------------
  // Partition cells by texture, then one InstancedMesh per texture group.
  // The LANDING tower is excluded — it gets its own mesh below, with the
  // site's links rendered on its street-facing face (the arrival IS the
  // menu). The rand draw still happens for its cell so the partition of
  // every other tower is unaffected.
  const groups = slabMats.map(() => [])
  for (let c = 0; c < GRID.cols; c++) {
    for (let r = 0; r < GRID.rows; r++) {
      const g = (rand() * slabMats.length) | 0
      if (c === route.landing.col && r === route.landing.row) continue
      groups[g].push([c, r])
    }
  }
  // Glowing base skirt + top crown: thin bright bands where each tower meets
  // the board and at the roofline (the roof texture's rim only reads from
  // above — from below the roofline a tower needs its own top border).
  // Geometry, not texture — the face textures scroll in y, so painted
  // horizontal lines would ride up the face.
  const SKIRT_H = 0.6
  const skirtGeo = new THREE.BoxGeometry(foot * 1.06, SKIRT_H, foot * 1.06)
  const skirtMats = PALETTE.map((hex) => new THREE.MeshBasicMaterial({color: hex, fog: true}))
  // Crowns render ONLY their side band: a solid top face would sit exactly on
  // the roof plane and replace the rooftop data-screen when seen from above.
  // And unlike the skirt (whose proud footprint reads as a plinth), the crown
  // must be FLUSH with the tower wall — a proud band overhangs, and looking
  // down past the overhang shows a dark slit that visually disconnects the
  // band from the tower.
  const hiddenMat = new THREE.MeshBasicMaterial({visible: false})
  const crownGeo = new THREE.BoxGeometry(foot * 1.002, SKIRT_H, foot * 1.002)
  const crownMats = skirtMats.map((m) => [m, m, hiddenMat, hiddenMat, m, m])
  disposables.push(skirtGeo, crownGeo, hiddenMat, ...skirtMats)
  const dummy = new THREE.Object3D()
  groups.forEach((cells, gi) => {
    if (!cells.length) return
    const im = new THREE.InstancedMesh(slabGeo, slabMats[gi], cells.length)
    const skirts = new THREE.InstancedMesh(skirtGeo, skirtMats[gi], cells.length)
    const crowns = new THREE.InstancedMesh(crownGeo, crownMats[gi], cells.length)
    cells.forEach(([c, r], i) => {
      const x = (c - GRID.cols / 2 + 0.5) * GRID.spacing
      const z = (r - GRID.rows / 2 + 0.5) * GRID.spacing
      dummy.position.set(x, H / 2, z)
      dummy.updateMatrix()
      im.setMatrixAt(i, dummy.matrix)
      dummy.position.set(x, SKIRT_H / 2, z)
      dummy.updateMatrix()
      skirts.setMatrixAt(i, dummy.matrix)
      dummy.position.set(x, H - SKIRT_H / 2, z)
      dummy.updateMatrix()
      crowns.setMatrixAt(i, dummy.matrix)
    })
    im.frustumCulled = false
    skirts.frustumCulled = false
    crowns.frustumCulled = false
    scene.add(im)
    scene.add(skirts)
    scene.add(crowns)
    disposables.push(im, skirts, crowns)
  })

  // --- the landing tower (the menu) -----------------------------------------
  // The real site links (from the page's #gibson-links JSON island) drawn as
  // the tower's access panel on its street-facing face; the other faces stay
  // in the standard cyan language. The panel neither scrolls nor cycles.
  const items = readManifest(win).map((x) => ({
    name: (x.name || "").toUpperCase(),
    desc: x.desc || "",
    url: x.url || "",
  }))
  // Size the panel to what the end camera can actually SEE: the visible
  // vertical span at the landing distance depends on the (aspect-derived)
  // vertical FOV, so short-wide windows get compact rows and tall windows
  // get grand ones — the whole menu always frames up.
  const endDist = GRID.spacing * endDistFrac // same value the route parks at
  const menuTexH = MENU_TEX_W * 4
  const visiblePx = 2 * endDist * Math.tan((camera.fov * Math.PI) / 360) * (menuTexH / H)
  const blockPx = Math.max(280, visiblePx * 0.88)
  const menuFace = menuFaceTexture(PALETTE[0], rand, items, MENU_TEX_W, blockPx)
  const menuMat = new THREE.MeshBasicMaterial({map: menuFace.tex, fog: true})

  // Interaction surface for the parked ending: screen-space rects of each
  // menu row (projected through the live camera — recompute after resize)
  // and a highlight hook. Consumed by the intro's hotspot overlay.
  menuApi = {
    rects() {
      const ww = win.innerWidth
      const hh = win.innerHeight
      const zHalf = foot / 2 - 1
      return items.map((_, i) => {
        const texY = menuFace.y0 + i * menuFace.rowH
        const yTop = (1 - (texY - menuFace.rowH / 2) / menuTexH) * H
        const yBot = (1 - (texY + menuFace.rowH / 2) / menuTexH) * H
        const corners = []
        for (const y of [yTop, yBot]) {
          for (const z of [route.landing.z - zHalf, route.landing.z + zHalf]) {
            const v = new THREE.Vector3(route.landing.faceX, y, z).project(camera)
            corners.push([((v.x + 1) / 2) * ww, ((1 - v.y) / 2) * hh])
          }
        }
        const xs = corners.map((c) => c[0])
        const ys = corners.map((c) => c[1])
        const left = Math.min(...xs)
        const top = Math.min(...ys)
        return {left, top, width: Math.max(...xs) - left, height: Math.max(...ys) - top}
      })
    },
    highlight(i) {
      menuFace.draw(i)
    },
    forceOpen() {
      menuFace.draw(undefined, 1)
    },
  }
  // The panel "window" starts closed in animated modes and irises open when
  // the camera settles on the tower; still mode shows it open from the start.
  menuFace.draw(-1, still ? 1 : 0)
  menuOpen = {face: menuFace, at: null, delay: mode === "parked" ? 700 : 0, done: still}
  const plainSide = new THREE.MeshBasicMaterial({map: faceTexes[0], fog: true})
  // Box material order: +x, -x, +y, -y, +z, -z. The face fronting the street
  // is -x when the tower sits on the +side of the street, +x otherwise.
  const landMats =
    route.landing.side > 0
      ? [plainSide, menuMat, roofMats[0], capMat, plainSide, plainSide]
      : [menuMat, plainSide, roofMats[0], capMat, plainSide, plainSide]
  const landMesh = new THREE.Mesh(slabGeo, landMats)
  landMesh.position.set(route.landing.x, H / 2, route.landing.z)
  scene.add(landMesh)
  const landSkirt = new THREE.Mesh(skirtGeo, skirtMats[0])
  landSkirt.position.set(route.landing.x, SKIRT_H / 2, route.landing.z)
  scene.add(landSkirt)
  const landCrown = new THREE.Mesh(crownGeo, crownMats[0])
  landCrown.position.set(route.landing.x, H - SKIRT_H / 2, route.landing.z)
  scene.add(landCrown)
  disposables.push(menuFace.tex, menuMat, plainSide)

  // --- the floor --------------------------------------------------------------
  const {floorTex} = createFloor(scene, GRID, rand, disposables)

  // Max anisotropic filtering everywhere: tower faces fly past at grazing
  // angles and the floor is grazing almost by definition — at low anisotropy
  // the dense glyph rows alias into a sparkling shimmer under motion (which
  // bloom then amplifies into popping halos).
  const maxAniso = renderer.capabilities.getMaxAnisotropy()
  ;[...faceTexes, ...roofTexes, floorTex].forEach((tex) => {
    tex.anisotropy = maxAniso
  })

  // --- the flight curve --------------------------------------------------------
  // Densify with collinear points so the CatmullRom keeps the straight streets
  // straight (a sparse polyline overshoots and bows the camera sideways INTO the
  // edge towers); the pre-sampled corner arcs pass through untouched.
  const curve = new THREE.CatmullRomCurve3(densify(route.waypoints, GRID.spacing * 0.7))
  // The default 200-division arc-length table quantises getPointAt: at flight
  // speed the camera's frame-to-frame step ripples ±30% (measured), which
  // reads as visual jitter — worst where the ground is close (the flare).
  // A dense table makes the mapping effectively exact (0.0% ripple); it's a
  // one-time few-ms cost at scene build.
  curve.arcLengthDivisions = 20000
  curve.updateArcLengths()

  const pathMesh = createPathRibbon(scene, curve, disposables)
  const overview = setupOverview(scene, win, GRID, curve, disposables)

  // --- speed profile ----------------------------------------------------------
  // The flight cruises slowly but whips through the corners: time-to-arc is
  // remapped so the corner windows (reported by the route, with smooth ramps
  // in/out so speed never steps) consume less wall time per unit of distance.
  const TURN_SPEED = 2.0 // corners run ~2x the cruise pace
  const RAMP = 0.03 // arc-fraction width of the ease into/out of a corner
  const smooth01 = (a, b, x) => {
    const k = Math.min(1, Math.max(0, (x - a) / (b - a || 1)))
    return k * k * (3 - 2 * k)
  }
  const speedAt = (u) => {
    let m = 1
    for (const tw of route.turns || []) {
      const a = smooth01(tw.start - RAMP, tw.start, u) * (1 - smooth01(tw.end, tw.end + RAMP, u))
      m = Math.max(m, 1 + (TURN_SPEED - 1) * a)
    }
    return m
  }
  const REMAP_N = 800
  const cumTime = new Float64Array(REMAP_N + 1)
  for (let i = 1; i <= REMAP_N; i++) {
    cumTime[i] = cumTime[i - 1] + 1 / speedAt((i - 0.5) / REMAP_N)
  }
  // time fraction (post-easing) -> arc fraction
  function timeToArc(e) {
    if (e <= 0) return 0
    if (e >= 1) return 1
    const target = e * cumTime[REMAP_N]
    let lo = 0
    let hi = REMAP_N
    while (lo < hi) {
      const mid = (lo + hi) >> 1
      if (cumTime[mid] < target) lo = mid + 1
      else hi = mid
    }
    const i = Math.max(1, lo)
    const frac = (target - cumTime[i - 1]) / (cumTime[i] - cumTime[i - 1] || 1)
    return (i - 1 + frac) / REMAP_N
  }

  const composer = new EffectComposer(renderer)
  composer.addPass(new RenderPass(scene, camera))
  // Threshold above the aliasing noise floor so shimmering texture pixels
  // don't pop in and out of the glow; strength unchanged.
  const bloom = new UnrealBloomPass(new THREE.Vector2(w, h), 0.5, 0.5, 0.45)
  composer.addPass(bloom)

  // Keep the scene responsive to window size changes.
  function onResize() {
    const ww = win.innerWidth
    const hh = win.innerHeight
    renderer.setSize(ww, hh, false)
    composer.setSize(ww, hh)
    bloom.setSize(ww, hh)
    applyCameraFov(camera, ww / hh)
  }
  win.addEventListener("resize", onResize)

  // --- per-frame camera + animation ------------------------------------------
  function render(t) {
    const now = win.performance.now()
    animateData(Math.min(1, Math.max(0, t)), now)
    animateBoard(now)
    // Iris the access panel open once the camera settles on the tower (the
    // final ~4% of the flight is the slow squared-up push; parked mode delays
    // so the mosaic reveal happens first).
    if (menuOpen && !menuOpen.done && t >= 0.96) {
      if (menuOpen.at === null) menuOpen.at = now + menuOpen.delay
      if (now >= menuOpen.at) {
        const k = Math.min(1, (now - menuOpen.at) / 450)
        const e = 1 - Math.pow(1 - k, 3) // easeOutCubic
        menuOpen.face.draw(undefined, e)
        if (k >= 1) menuOpen.done = true
      }
    }
    if (overview) {
      const span = GRID.rows * GRID.spacing
      camera.position.set(span * 0.35, span * 0.45, span * 0.62)
      camera.lookAt(0, GRID.spacing, 0)
      composer.render()
      return
    }
    const tt = Math.min(1, Math.max(0, t))
    const pos = curve.getPointAt(tt)
    camera.position.copy(pos)
    // Aim along the curve TANGENT — look exactly where we're moving. On a
    // straight street this stares down the corridor (walls recede to a vanishing
    // point); through a rounded corner the tangent rotates smoothly so the
    // camera pans THROUGH the turn instead of yawing into the corner tower.
    const tan = curve.getTangentAt(tt)
    // Clamp upward pitch (~35°) so the vertical rise at the end never points the
    // tangent near straight up, which would make lookAt roll-unstable.
    const horiz = Math.hypot(tan.x, tan.z)
    if (tan.y > horiz * 0.7) {
      tan.y = horiz * 0.7
      tan.normalize()
    }
    const look = pos.clone().addScaledVector(tan, GRID.spacing * 2)
    // Opening gaze: while above the street, look DOWN across the endless
    // rooftops (the establishing shot — otherwise the shallow glide stares at
    // black sky). Tied to altitude, so the gaze lifts exactly as we descend.
    if (tt < 0.5) {
      const hK = Math.min(1, Math.max(0, (pos.y - route.cruiseY) / (GRID.spacing * 2.6)))
      look.y -= hK * GRID.spacing * 0.65
    }
    // Final approach: as the camera rises up the landing tower, blend the look
    // onto a fixed point high on its face — the camera climbs while facing the
    // building, ending square to the face that becomes the menu. The blend
    // completes early (by ~94%) so the squared-up shot registers rather than
    // flashing for a single frame.
    if (tt > 0.8) {
      const k = Math.min(1, (tt - 0.8) / 0.14)
      look.lerp(new THREE.Vector3(route.landing.faceX, route.landing.lookY, route.landing.z), k)
    }
    camera.lookAt(look)
    composer.render()
  }

  function dispose() {
    win.removeEventListener("resize", onResize)
    disposables.forEach((d) => d.dispose())
    bloom.dispose()
    composer.dispose()
    renderer.dispose()
  }

  function setPathVisible(v) {
    pathMesh.visible = v
  }

  // Adaptive-quality hook: dropping the pixel ratio quadratically cuts fill
  // work (the dominant cost: full-screen render + bloom's blur chain).
  function setPixelRatio(r) {
    renderer.setPixelRatio(r)
    onResize()
  }

  return {scene, camera, render, dispose, route, timeToArc, setPathVisible, setPixelRatio, menu: menuApi}
}

// Insert collinear points along each waypoint segment so a CatmullRom through
// them stays close to the polyline (no overshoot on long straights).
function densify(wps, step) {
  const out = []
  for (let i = 0; i < wps.length - 1; i++) {
    const a = wps[i]
    const b = wps[i + 1]
    out.push(new THREE.Vector3(a.x, a.y, a.z))
    const dx = b.x - a.x
    const dy = b.y - a.y
    const dz = b.z - a.z
    // Only densify LEVEL segments (it exists to stop lateral bowing on long
    // straight streets). Height-changing segments stay sparse so the spline
    // sweeps the whole descent/rise as one smooth arc — linearly-subdivided
    // slope segments put a visible "nod" at every waypoint joint.
    const n = Math.abs(dy) > 0.001 ? 1 : Math.max(1, Math.floor(Math.hypot(dx, dz) / step))
    for (let k = 1; k < n; k++) {
      out.push(new THREE.Vector3(a.x + (dx * k) / n, a.y + (dy * k) / n, a.z + (dz * k) / n))
    }
  }
  const last = wps[wps.length - 1]
  out.push(new THREE.Vector3(last.x, last.y, last.z))
  return out
}

// The #gibson-links JSON island: the page's link manifest, rendered by the
// server independently of the visible fallback markup.
function readManifest(win) {
  try {
    const el = win.document.getElementById("gibson-links")
    const parsed = el ? JSON.parse(el.textContent) : []
    return Array.isArray(parsed) ? parsed.filter((x) => x && x.name && x.url) : []
  } catch {
    return []
  }
}
