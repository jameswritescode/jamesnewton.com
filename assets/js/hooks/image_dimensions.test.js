import {describe, it, expect, vi, beforeEach} from "vitest"
import {ImageDimensions} from "./image_dimensions"

describe("ImageDimensions", () => {
  beforeEach(() => {
    global.URL.createObjectURL = vi.fn(() => "blob:x")
    global.URL.revokeObjectURL = vi.fn()
    // Make Image load synchronously with fixed natural dimensions.
    global.Image = class {
      set src(_v) {
        this.naturalWidth = 640
        this.naturalHeight = 480
        this.onload()
      }
    }
  })

  it("pushes width/height for each picked file", () => {
    const input = document.createElement("input")
    input.type = "file"
    const pushEvent = vi.fn()
    const hook = {el: input, pushEvent}
    Object.setPrototypeOf(hook, ImageDimensions)
    hook.mounted()

    const file = new File(["x"], "shot.jpg", {type: "image/jpeg"})
    Object.defineProperty(input, "files", {value: [file]})
    input.dispatchEvent(new Event("input", {bubbles: true}))

    expect(pushEvent).toHaveBeenCalledWith("set_dimensions", {
      name: "shot.jpg",
      width: 640,
      height: 480,
    })
  })
})
