// Deterministic still frames of the flight via ?gibsonFrame static holds
// (seed 7 city; exposes window.__cam/__route for probing).
//
//   node assets/dev/gibson/stills.mjs 0.12 0.6 1
import {chromium} from "playwright"
import {mkdirSync} from "node:fs"

const BASE = process.env.BASE_URL ?? "http://localhost:4000"
const out = new URL("../../../tmp/gibson/", import.meta.url).pathname
mkdirSync(out, {recursive: true})
const frames = process.argv.slice(2)
if (!frames.length) frames.push("0.12", "0.6", "1")

const b = await chromium.launch({
  args: ["--use-angle=metal", "--enable-gpu-rasterization", "--ignore-gpu-blocklist"],
})
const p = await b.newPage({viewport: {width: 1372, height: 597}, deviceScaleFactor: 2})
p.on("pageerror", (e) => console.log("[pageerror]", e.message))
for (const f of frames) {
  await p.goto(`${BASE}/links?intro&seed=7&gibsonFrame=${f}`, {waitUntil: "domcontentloaded"})
  await p.waitForFunction(() => window.__cam, null, {timeout: 8000})
  await p.waitForTimeout(1600) // let the mosaic clear fully
  const path = `${out}still_f${f}.png`
  await p.screenshot({path})
  console.log(path)
}
await b.close()
