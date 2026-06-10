import {describe, it, expect, afterEach} from "vitest"
import {focusAfterNavigation} from "./navigation"

describe("focusAfterNavigation", () => {
  afterEach(() => {
    document.body.innerHTML = ""
    document.title = ""
  })

  it("moves focus to #main when there is no hash", () => {
    document.body.innerHTML = '<main id="main">hi</main><div id="route-announcer"></div>'

    focusAfterNavigation(document, {location: {hash: ""}})

    const main = document.getElementById("main")
    expect(document.activeElement).toBe(main)
    expect(main.getAttribute("tabindex")).toBe("-1")
  })

  it("moves focus to the hash target when present", () => {
    document.body.innerHTML =
      '<main id="main"><section id="sierra">x</section></main><div id="route-announcer"></div>'

    focusAfterNavigation(document, {location: {hash: "#sierra"}})

    expect(document.activeElement).toBe(document.getElementById("sierra"))
  })

  it("announces the document title in the live region", () => {
    document.body.innerHTML = '<main id="main">x</main><div id="route-announcer"></div>'
    document.title = "Reading"

    focusAfterNavigation(document, {location: {hash: ""}})

    expect(document.getElementById("route-announcer").textContent).toBe("Reading")
  })
})
