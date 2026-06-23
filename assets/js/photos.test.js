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

function setupGallery() {
  document.body.innerHTML = `
    <div class="photo-grid">
      <button class="photo-button" data-index="0"><img src="a.jpg" alt="A" /></button>
      <button class="photo-button" data-index="1"><img src="b.jpg" alt="B" /></button>
      <button class="photo-button" data-index="2"><img src="c.jpg" alt="C" /></button>
    </div>
    <div class="photo-grid">
      <button class="photo-button" data-index="0"><img src="x.jpg" alt="X" /></button>
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

  it("ArrowRight/ArrowLeft move through the current gallery and wrap", () => {
    setupGallery()
    initPhotos()
    const img = document.querySelector(".photo-overlay-img")
    const buttons = document.querySelectorAll(".photo-grid")[0].querySelectorAll(".photo-button")

    click(buttons[0])
    expect(img.src).toContain("a.jpg")

    press("ArrowRight")
    expect(img.src).toContain("b.jpg")
    expect(img.alt).toBe("B")

    press("ArrowRight")
    expect(img.src).toContain("c.jpg")

    press("ArrowRight") // wraps to first
    expect(img.src).toContain("a.jpg")

    press("ArrowLeft") // wraps to last
    expect(img.src).toContain("c.jpg")
  })

  it("keeps navigation within the gallery the photo was opened from", () => {
    setupGallery()
    initPhotos()
    const img = document.querySelector(".photo-overlay-img")
    const otherGalleryButton =
      document.querySelectorAll(".photo-grid")[1].querySelector(".photo-button")

    click(otherGalleryButton) // a one-photo gallery
    press("ArrowRight")

    expect(img.src).toContain("x.jpg") // stays on the only photo, never crosses into gallery 1
  })

  it("loads the original from data-full, not the grid thumbnail", () => {
    document.body.innerHTML = `
      <div class="photo-grid" id="grid-a">
        <button class="photo-button" data-index="0" data-full="orig.jpg">
          <img src="thumb.webp" alt="A" />
        </button>
      </div>
      <div class="photo-overlay" id="photoOverlay" inert>
        <button type="button" class="photo-overlay-close" aria-label="Close">&times;</button>
        <img class="photo-overlay-img" id="photoOverlayImg" alt="" />
      </div>`
    initPhotos()

    click(document.querySelector(".photo-button"))

    const full = document.getElementById("photoOverlayImg")
    expect(full.getAttribute("src")).toBe("orig.jpg")
    expect(full.alt).toBe("A")
  })
})
