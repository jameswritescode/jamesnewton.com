import {describe, it, expect, afterEach} from "vitest"
import {initPhotos, teardownPhotos} from "./photos"

function setup() {
  document.body.innerHTML = `
    <div class="photo-grid">
      <button class="photo-button" aria-label="Enlarge: A"><img src="a.jpg" alt="A" /></button>
    </div>
    <div class="photo-overlay" id="photoOverlay" inert>
      <button type="button" class="photo-overlay-close" aria-label="Close">&times;</button>
      <img class="photo-overlay-img" id="photoOverlayImg" alt="" />
    </div>`
}

const click = (el) => el.dispatchEvent(new MouseEvent("click", {bubbles: true}))
const press = (key) =>
  document.dispatchEvent(new KeyboardEvent("keydown", {key, bubbles: true, cancelable: true}))

describe("photo lightbox", () => {
  afterEach(() => {
    teardownPhotos()
    document.body.innerHTML = ""
    document.body.style.overflow = ""
  })

  it("opens on photo click and moves focus to the close button", () => {
    setup()
    initPhotos()

    click(document.querySelector(".photo-button"))

    const overlay = document.getElementById("photoOverlay")
    expect(overlay.classList.contains("is-open")).toBe(true)
    expect(overlay.hasAttribute("inert")).toBe(false)
    expect(document.activeElement).toBe(document.querySelector(".photo-overlay-close"))
  })

  it("traps Tab on the close button while open", () => {
    setup()
    initPhotos()
    click(document.querySelector(".photo-button"))

    press("Tab")

    expect(document.activeElement).toBe(document.querySelector(".photo-overlay-close"))
  })

  it("closes on the close button and restores focus to the trigger", () => {
    setup()
    initPhotos()
    const trigger = document.querySelector(".photo-button")
    trigger.focus()
    click(trigger)

    click(document.querySelector(".photo-overlay-close"))

    const overlay = document.getElementById("photoOverlay")
    expect(overlay.classList.contains("is-open")).toBe(false)
    expect(overlay.hasAttribute("inert")).toBe(true)
    expect(document.activeElement).toBe(trigger)
  })

  it("closes on Escape", () => {
    setup()
    initPhotos()
    click(document.querySelector(".photo-button"))

    press("Escape")

    expect(document.getElementById("photoOverlay").classList.contains("is-open")).toBe(false)
  })
})
