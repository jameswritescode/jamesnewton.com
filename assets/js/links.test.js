import {describe, it, expect, beforeEach} from "vitest"
import {readoutFor, initLinks} from "./links"

function mountLinks() {
  document.body.innerHTML = `
    <main class="links">
      <ul class="links-menu">
        <li><a class="links-item" id="a1" href="https://github.com/jameswritescode"
               data-name="GITHUB" data-url="https://github.com/jameswritescode"
               data-desc="Code and source.">GITHUB</a></li>
        <li><a class="links-item" id="a2" href="https://markos.ai"
               data-name="MARK OS" data-url="https://markos.ai"
               data-desc="Where I work.">MARK OS</a></li>
      </ul>
      <aside class="links-readout">
        <div class="links-readout-name" data-readout="name">GITHUB</div>
        <div class="links-readout-url" data-readout="url">https://github.com/jameswritescode</div>
        <div class="links-readout-desc" data-readout="desc">Code and source.</div>
      </aside>
    </main>
  `
}

describe("links readout", () => {
  beforeEach(() => (document.body.innerHTML = ""))

  it("readoutFor reads the link's data attributes", () => {
    mountLinks()
    const r = readoutFor(document.getElementById("a2"))
    expect(r).toEqual({name: "MARK OS", url: "https://markos.ai", desc: "Where I work."})
  })

  it("updates the readout panel when an item is hovered", () => {
    mountLinks()
    initLinks()
    document.getElementById("a2").dispatchEvent(new Event("mouseenter"))
    expect(document.querySelector('[data-readout="name"]').textContent).toBe("MARK OS")
    expect(document.querySelector('[data-readout="url"]').textContent).toBe("https://markos.ai")
    expect(document.querySelector('[data-readout="desc"]').textContent).toBe("Where I work.")
  })

  it("updates the readout panel when an item receives focus", () => {
    mountLinks()
    initLinks()
    document.getElementById("a2").dispatchEvent(new Event("focus"))
    expect(document.querySelector('[data-readout="name"]').textContent).toBe("MARK OS")
  })

  it("reflects the latest item when hovering from one to another", () => {
    mountLinks()
    initLinks()
    document.getElementById("a1").dispatchEvent(new Event("mouseenter"))
    document.getElementById("a2").dispatchEvent(new Event("mouseenter"))
    expect(document.querySelector('[data-readout="name"]').textContent).toBe("MARK OS")
    expect(document.querySelector('[data-readout="url"]').textContent).toBe("https://markos.ai")
  })

  it("no-ops when there is no links page", () => {
    document.body.innerHTML = `<main id="main"></main>`
    expect(() => initLinks()).not.toThrow()
  })
})
