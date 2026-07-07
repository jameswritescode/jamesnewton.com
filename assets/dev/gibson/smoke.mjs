// End-to-end smoke of the parked ending: fast-forward the flight, verify the
// hotspot overlay (labels + hrefs), hover a row, click home, assert a full
// navigation tore the scene down.
//
//   node assets/dev/gibson/smoke.mjs
import {chromium} from "playwright"

const b = await chromium.launch({
  args: ["--use-angle=metal", "--enable-gpu-rasterization", "--ignore-gpu-blocklist"],
})
const p = await b.newPage({viewport: {width: 1372, height: 597}, deviceScaleFactor: 2})
p.on("pageerror", (e) => console.log("[pageerror]", e.message))
await p.goto("http://localhost:4000/links?intro", {waitUntil: "domcontentloaded"})
await p.waitForTimeout(3500)
await p.keyboard.press(" ") // fast-forward to park
await p.waitForTimeout(900)
const spots = await p.evaluate(() => {
  const nav = document.querySelector('nav[aria-label="Links"]')
  return nav
    ? Array.from(nav.children).map((a) => ({
        label: a.getAttribute("aria-label"),
        href: a.getAttribute("href"),
      }))
    : null
})
console.log("hotspots:", JSON.stringify(spots))
const nav = await p.$('nav[aria-label="Links"]')
if (nav) {
  const rows = await nav.$$("a")
  if (rows[1]) await rows[1].hover()
  await p.waitForTimeout(300)
  const home = await p.$('nav[aria-label="Links"] a[aria-label="JN.SYS"]')
  if (home) {
    await Promise.all([p.waitForNavigation({waitUntil: "domcontentloaded"}), home.click()])
    await p.waitForTimeout(400)
    console.log(
      "after click:",
      JSON.stringify(
        await p.evaluate(() => ({
          url: location.pathname,
          sceneGone: !document.querySelector(".gibson-canvas"),
        })),
      ),
    )
  }
}
await b.close()
