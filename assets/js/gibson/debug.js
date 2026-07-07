// Development-only scene furniture. Everything here is inert during a normal
// visitor flight: the path ribbon is invisible until pause toggles it, and the
// overview rig only activates behind ?gibsonView=over.
import * as THREE from "three"

// The flight path as a glowing tube, colour-graded cyan (start) to magenta
// (end). Hidden in normal playback; toggled while paused so the route can be
// inspected in-world. Sits slightly below the camera line so the view is never
// from inside the tube.
export function createPathRibbon(scene, curve, disposables) {
  const pathGeo = new THREE.TubeGeometry(curve, 300, 0.3, 6, false)
  {
    const cnt = pathGeo.attributes.position.count
    const cols = new Float32Array(cnt * 3)
    const cA = new THREE.Color(0x19c9ff)
    const cB = new THREE.Color(0xff31d9)
    const cT = new THREE.Color()
    for (let i = 0; i < cnt; i++) {
      cT.copy(cA).lerp(cB, i / cnt)
      cols.set([cT.r, cT.g, cT.b], i * 3)
    }
    pathGeo.setAttribute("color", new THREE.BufferAttribute(cols, 3))
  }
  const pathMat = new THREE.MeshBasicMaterial({
    vertexColors: true,
    transparent: true,
    opacity: 0.55,
    blending: THREE.AdditiveBlending,
    depthWrite: false,
  })
  const pathMesh = new THREE.Mesh(pathGeo, pathMat)
  pathMesh.position.y = -4.5
  pathMesh.visible = false
  pathMesh.frustumCulled = false
  scene.add(pathMesh)
  disposables.push(pathGeo, pathMat)
  return pathMesh
}

// ?gibsonView=over: an external overhead camera with the route drawn as a
// white line, plus a red marker + forward ray at the ?gibsonFrame position.
// Returns true when active — render() then uses the overview camera placement.
export function setupOverview(scene, win, GRID, curve, disposables) {
  if (new URLSearchParams(win.location.search).get("gibsonView") !== "over") return false
  scene.fog = null
  const pts = curve.getPoints(160)
  const lineGeo = new THREE.BufferGeometry().setFromPoints(pts)
  const lineMat = new THREE.LineBasicMaterial({color: 0xffffff})
  scene.add(new THREE.Line(lineGeo, lineMat))
  disposables.push(lineGeo, lineMat)
  const fp = new URLSearchParams(win.location.search).get("gibsonFrame")
  if (fp !== null) {
    const f = Math.max(0, Math.min(0.999, parseFloat(fp) || 0))
    const cp = curve.getPointAt(f)
    const fwd = curve.getTangentAt(f)
    const sphGeo = new THREE.SphereGeometry(GRID.spacing * 0.4, 12, 12)
    const sphMat = new THREE.MeshBasicMaterial({color: 0xff0000})
    const sph = new THREE.Mesh(sphGeo, sphMat)
    sph.position.copy(cp)
    scene.add(sph)
    const ray = new THREE.BufferGeometry().setFromPoints([
      cp,
      cp.clone().addScaledVector(fwd, GRID.spacing * 4),
    ])
    const rayLine = new THREE.Line(ray, new THREE.LineBasicMaterial({color: 0xff0000}))
    scene.add(rayLine)
    disposables.push(sphGeo, sphMat, ray)
  }
  return true
}
