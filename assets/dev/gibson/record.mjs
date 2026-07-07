// Record the real /links?intro flight with a hardware-GPU headless browser and
// report the exact wall-clock second the flight started (bundle load time
// varies per run), so frame extraction can be anchored to flight time.
//
//   node assets/dev/gibson/record.mjs [width] [height]
//
// Then e.g.:  ffmpeg -ss <FLIGHTSTART_S + t> -i <VIDEO> -frames:v 1 frame.png
// GOTCHA: without the --use-angle flags, headless WebGL is software-rendered
// at 2-4fps and every capture is a slideshow. See docs/gibson.md.
import {chromium} from "playwright"
import {mkdirSync} from "node:fs"

const BASE = process.env.BASE_URL ?? "http://localhost:4000"
const out = new URL("../../../tmp/gibson/", import.meta.url).pathname
mkdirSync(out, {recursive: true})
const W = Number(process.argv[2] ?? 1372)
const H = Number(process.argv[3] ?? 597)

const b = await chromium.launch({
  args: ["--use-angle=metal", "--enable-gpu-rasterization", "--ignore-gpu-blocklist"],
})
const ctx = await b.newContext({
  viewport: {width: W, height: H},
  deviceScaleFactor: 2,
  recordVideo: {dir: out, size: {width: W, height: H}},
})
const p = await ctx.newPage()
p.on("pageerror", (e) => console.log("[pageerror]", e.message))
await p.addInitScript(() => {
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
await p.goto(`${BASE}/links?intro`, {waitUntil: "domcontentloaded"})
await p.waitForTimeout(17800)
const fs = await p.evaluate(() => window.__flightStart)
const video = p.video()
await ctx.close()
console.log("FLIGHTSTART_S:", ((fs ?? 0) / 1000).toFixed(2))
console.log("VIDEO:", await video.path())
await b.close()
