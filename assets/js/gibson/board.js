// The "motherboard" the city stands on: the circuit-trace floor plane and the
// live activity that plays over it (data pulses streaming the street lanes,
// junction pads breathing at intersections). Split from scene.js by
// responsibility; both factories consume the shared city RNG, so their call
// order in scene.js is part of the scene's deterministic output.
import * as THREE from "three"
import {floorTexture} from "./textures.js"

const PULSE_PALETTE = [0xff31d9, 0xc94bff, 0x3a7bff, 0x8ff6ff]

// Data pulses + breathing pads. Pure geometry — no texture uploads — so the
// per-frame cost is a couple of small buffer writes. `still` (reduced motion)
// hides both and turns the animator into a no-op.
export function createBoardActivity(scene, GRID, rand, disposables, still) {
  // Pulses: bright packets streaming along the street buses, confined to the
  // central region the route flies through; fog swallows the rest anyway.
  const PULSE_N = 220
  const PULSE_REGION = GRID.spacing * 9
  const pulseData = []
  const pulsePos = new Float32Array(PULSE_N * 3)
  const pulseCol = new Float32Array(PULSE_N * 3)
  for (let i = 0; i < PULSE_N; i++) {
    const lane = Math.round(rand() * 18 - 9) * GRID.spacing + (rand() * 2 - 1) * GRID.spacing * 0.3
    pulseData.push({
      axis: rand() < 0.5 ? "x" : "z",
      lane,
      s: (rand() * 2 - 1) * PULSE_REGION,
      speed: (rand() < 0.5 ? -1 : 1) * (25 + rand() * 65),
    })
    const c = new THREE.Color(PULSE_PALETTE[(rand() * PULSE_PALETTE.length) | 0])
    pulseCol.set([c.r, c.g, c.b], i * 3)
  }
  const pulseGeo = new THREE.BufferGeometry()
  pulseGeo.setAttribute("position", new THREE.BufferAttribute(pulsePos, 3))
  pulseGeo.setAttribute("color", new THREE.BufferAttribute(pulseCol, 3))
  const pulseMat = new THREE.PointsMaterial({
    size: 3,
    vertexColors: true,
    transparent: true,
    opacity: 0.9,
    blending: THREE.AdditiveBlending,
    depthWrite: false,
    fog: true,
  })
  const pulses = new THREE.Points(pulseGeo, pulseMat)
  pulses.frustumCulled = false
  scene.add(pulses)
  disposables.push(pulseGeo, pulseMat)

  // Pads: small additive quads at intersections breathing via per-instance
  // colour (each with its own phase/rate).
  const PAD_N = 36
  const padGeo = new THREE.PlaneGeometry(GRID.spacing * 0.14, GRID.spacing * 0.14)
  const padMat = new THREE.MeshBasicMaterial({
    transparent: true,
    blending: THREE.AdditiveBlending,
    depthWrite: false,
    fog: true,
  })
  const pads = new THREE.InstancedMesh(padGeo, padMat, PAD_N)
  const padData = []
  {
    const dummy = new THREE.Object3D()
    for (let i = 0; i < PAD_N; i++) {
      dummy.position.set(
        Math.round(rand() * 18 - 9) * GRID.spacing + (rand() * 2 - 1) * GRID.spacing * 0.25,
        0.4,
        Math.round(rand() * 18 - 9) * GRID.spacing + (rand() * 2 - 1) * GRID.spacing * 0.25,
      )
      dummy.rotation.x = -Math.PI / 2
      dummy.updateMatrix()
      pads.setMatrixAt(i, dummy.matrix)
      pads.setColorAt(i, new THREE.Color(0x000000))
      padData.push({
        base: new THREE.Color(PULSE_PALETTE[(rand() * PULSE_PALETTE.length) | 0]),
        phase: rand() * Math.PI * 2,
        rate: 1.5 + rand() * 3,
      })
    }
  }
  pads.frustumCulled = false
  scene.add(pads)
  disposables.push(padGeo, padMat, pads)

  if (still) {
    // reduced motion: no streaming packets, no breathing pads
    pulses.visible = false
    pads.visible = false
  }

  const padColor = new THREE.Color()
  let lastNow = null
  function animateBoard(now) {
    if (still) return
    const dt = lastNow === null ? 0 : Math.min(0.1, (now - lastNow) / 1000)
    lastNow = now
    for (let i = 0; i < PULSE_N; i++) {
      const p = pulseData[i]
      p.s += p.speed * dt
      if (p.s > PULSE_REGION) p.s -= PULSE_REGION * 2
      if (p.s < -PULSE_REGION) p.s += PULSE_REGION * 2
      const x = p.axis === "x" ? p.s : p.lane
      const z = p.axis === "x" ? p.lane : p.s
      pulsePos.set([x, 0.6, z], i * 3)
    }
    pulseGeo.attributes.position.needsUpdate = true
    const sec = now / 1000
    for (let i = 0; i < PAD_N; i++) {
      const d = padData[i]
      const k = 0.25 + 0.75 * (0.5 + 0.5 * Math.sin(d.phase + sec * d.rate))
      padColor.copy(d.base).multiplyScalar(k)
      pads.setColorAt(i, padColor)
    }
    pads.instanceColor.needsUpdate = true
  }

  return {animateBoard}
}

// The floor plane. One texture BLOCK spans 4x4 city cells; the plane spans an
// even multiple of blocks and is centred on the grid, so block boundaries land
// exactly on the street lattice — buses run down the real streets and each
// tower stands on its cell's chip plate, with the visible pattern repeating
// only every 4 cells.
export function createFloor(scene, GRID, rand, disposables) {
  const FLOOR_BLOCK = GRID.spacing * 4
  const floorTex = floorTexture(rand, GRID.towerFrac)
  const floorW = GRID.cols * GRID.spacing * 4
  const floorD = GRID.rows * GRID.spacing * 4
  floorTex.repeat.set(floorW / FLOOR_BLOCK, floorD / FLOOR_BLOCK)
  const floorGeo = new THREE.PlaneGeometry(floorW, floorD)
  const floorMat = new THREE.MeshBasicMaterial({map: floorTex, fog: true})
  const floor = new THREE.Mesh(floorGeo, floorMat)
  floor.rotation.x = -Math.PI / 2
  scene.add(floor)
  disposables.push(floorGeo, floorMat, floorTex)
  return {floorTex}
}
