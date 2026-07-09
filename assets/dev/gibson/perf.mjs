// Per-second frame-cost profile of the flight: launches with vsync and the
// frame-rate limiter disabled so rAF cadence = actual render cost, samples
// every frame, and bins avg/p95/max frame ms by flight second.
//
//   node assets/dev/gibson/perf.mjs            # dpr=2 (retina), seed 7
//   DPR=1 node assets/dev/gibson/perf.mjs      # fill-rate diagnosis pass
//   W=1512 H=945 node assets/dev/gibson/perf.mjs   # other viewports
//   SEED=n node assets/dev/gibson/perf.mjs     # a different route
//
// ">8.3" counts frames over the 120Hz budget — each one is a visible hitch
// on a ProMotion display.
//
// GOTCHA: same GPU flags as record.mjs — without them headless WebGL is
// software-rendered and every number is garbage.
import {chromium} from "playwright"

const BASE = process.env.BASE_URL ?? "http://localhost:4000"
const DPR = Number(process.env.DPR ?? 2)
const SEED = process.env.SEED ?? "7"
const W = Number(process.env.W ?? 1372)
const H = Number(process.env.H ?? 800)
const DURATION_S = 14

const b = await chromium.launch({
  args: [
    "--use-angle=metal",
    "--enable-gpu-rasterization",
    "--ignore-gpu-blocklist",
    "--disable-gpu-vsync",
    "--disable-frame-rate-limit",
  ],
})
const ctx = await b.newContext({viewport: {width: W, height: H}, deviceScaleFactor: DPR})
const p = await ctx.newPage()
p.on("pageerror", (e) => console.log("[pageerror]", e.message))
await p.addInitScript(() => {
  window.__frames = []
  window.__longtasks = []
  new PerformanceObserver((list) => {
    for (const e of list.getEntries()) {
      window.__longtasks.push({start: e.startTime, dur: e.duration, name: e.name})
    }
  }).observe({entryTypes: ["longtask"]})
  const loop = (now) => {
    window.__frames.push(now)
    requestAnimationFrame(loop)
  }
  requestAnimationFrame(loop)
  let val
  Object.defineProperty(window, "__gibsonRun", {
    configurable: true,
    get() {
      return val
    },
    set(fn) {
      val = function (canvas, opts) {
        const ctrl = fn(canvas, opts)
        const s = ctrl.start
        ctrl.start = function () {
          window.__flightStart = performance.now()
          return s.apply(this, arguments)
        }
        return ctrl
      }
    },
  })
})
await p.goto(`${BASE}/links?intro&seed=${SEED}`, {waitUntil: "domcontentloaded"})
await p.waitForTimeout((DURATION_S + 4) * 1000)

const {frames, flightStart, longtasks} = await p.evaluate(() => ({
  frames: window.__frames,
  flightStart: window.__flightStart,
  longtasks: window.__longtasks,
}))
await b.close()

if (!flightStart) {
  console.error("flight never started")
  process.exit(1)
}

// Bin frame deltas by flight second (plus a parked bin at the end).
const bins = Array.from({length: DURATION_S + 1}, () => [])
for (let i = 1; i < frames.length; i++) {
  const t = (frames[i] - flightStart) / 1000
  if (t < 0) continue
  const bin = Math.min(DURATION_S, Math.floor(t))
  bins[bin].push(frames[i] - frames[i - 1])
}

// Worst frames with their exact flight time, for correlating spikes with
// flight events (cycling start, arrival, etc).
const worst = []
for (let i = 1; i < frames.length; i++) {
  const t = (frames[i] - flightStart) / 1000
  if (t < 0) continue
  worst.push({t, ms: frames[i] - frames[i - 1]})
}
worst.sort((a, b) => b.ms - a.ms)
console.log(
  "longtasks (main-thread >50ms):",
  longtasks.map((l) => `${l.dur.toFixed(0)}ms@${((l.start - flightStart) / 1000).toFixed(2)}s ${l.name}`).join("  ") || "none"
)
console.log(
  "worst frames:",
  worst
    .slice(0, 8)
    .map((w) => `${w.ms.toFixed(0)}ms@${w.t.toFixed(2)}s`)
    .join("  ")
)

const pct = (a, q) => a[Math.min(a.length - 1, Math.floor(a.length * q))]
console.log(`dpr=${DPR} seed=${SEED} viewport=${W}x${H} (uncapped: frame ms = render cost)`)
console.log("flight-s  frames  avg-ms  p95-ms  max-ms  >8.3  ~fps")
bins.forEach((d, s) => {
  if (!d.length) return
  const sorted = [...d].sort((x, y) => x - y)
  const avg = d.reduce((x, y) => x + y, 0) / d.length
  const slow = d.filter((x) => x > 8.3).length
  const label = s === DURATION_S ? "parked" : `${s}-${s + 1}`
  console.log(
    `${label.padEnd(9)} ${String(d.length).padStart(6)} ${avg.toFixed(1).padStart(7)} ${pct(sorted, 0.95).toFixed(1).padStart(7)} ${sorted[sorted.length - 1].toFixed(1).padStart(7)} ${String(slow).padStart(5)} ${String(Math.round(1000 / avg)).padStart(5)}`
  )
})
