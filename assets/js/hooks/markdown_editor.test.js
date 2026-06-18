import {describe, it, expect, vi} from "vitest"
import {syncMarkdown, imageFiles, imageMarkdown} from "./markdown_editor"

// The body field is a hidden <textarea> (not <input>) because an <input>
// strips newlines from its value, which would corrupt multi-line markdown.
describe("syncMarkdown", () => {
  it("writes the markdown to the field and dispatches an input event", () => {
    const field = document.createElement("textarea")
    const handler = vi.fn()
    field.addEventListener("input", handler)

    syncMarkdown(field, "# Hello\n\nbody")

    expect(field.value).toBe("# Hello\n\nbody")
    expect(handler).toHaveBeenCalledTimes(1)
  })

  it("does not dispatch when the value is unchanged", () => {
    const field = document.createElement("textarea")
    field.value = "same"
    const handler = vi.fn()
    field.addEventListener("input", handler)

    syncMarkdown(field, "same")

    expect(handler).not.toHaveBeenCalled()
  })
})

describe("imageFiles", () => {
  const file = (type) => ({type, name: `f.${type.split("/")[1] || "bin"}`})

  it("keeps only entries whose type starts with image/", () => {
    const list = [file("image/png"), file("text/plain"), file("image/jpeg")]
    expect(imageFiles(list).map((f) => f.type)).toEqual(["image/png", "image/jpeg"])
  })

  it("returns an empty array when nothing is an image", () => {
    expect(imageFiles([file("application/pdf")])).toEqual([])
  })

  it("handles a FileList-like (array-like) argument", () => {
    const list = {0: file("image/png"), 1: file("text/plain"), length: 2}
    expect(imageFiles(list).map((f) => f.type)).toEqual(["image/png"])
  })
})

describe("imageMarkdown", () => {
  it("builds an empty-alt image and parks the caret just after ![", () => {
    expect(imageMarkdown("/media/abc.png")).toEqual({
      text: "![](/media/abc.png)",
      caretOffset: 2,
    })
  })
})
