// Live frame-pacing readout from window.__gibsonFps mid-flight (GPU headless).
// SOFTWARE=1 drops the GPU flags to simulate software-rendered WebGL.
//
//   node assets/dev/gibson/fps.mjs
import {chromium} from "playwright"

const args =
  process.env.SOFTWARE === "1"
    ? []
    : ["--use-angle=metal", "--enable-gpu-rasterization", "--ignore-gpu-blocklist"]
const b = await chromium.launch({args})
const p = await b.newPage({viewport: {width: 1372, height: 597}, deviceScaleFactor: 2})
await p.goto("http://localhost:4000/links?intro", {waitUntil: "domcontentloaded"})
await p.waitForTimeout(8000)
const samples = []
for (let i = 0; i < 6; i++) {
  samples.push(await p.evaluate(() => window.__gibsonFps))
  await p.waitForTimeout(500)
}
console.log(JSON.stringify(samples))
await b.close()
