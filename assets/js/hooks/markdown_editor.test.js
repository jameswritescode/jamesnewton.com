import {describe, it, expect, vi} from "vitest"
import {
  syncMarkdown,
  imageFiles,
  imageMarkdown,
  toggleMarker,
  wrapLink,
} from "./markdown_editor"

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

describe("toggleMarker", () => {
  it("wraps an empty selection and parks the caret between the markers", () => {
    expect(toggleMarker("", 0, 0, "**")).toEqual({
      from: 0,
      to: 0,
      insert: "****",
      anchor: 2,
      head: 2,
    })
  })

  it("wraps a selection and keeps the original text selected", () => {
    expect(toggleMarker("hello", 0, 5, "**")).toEqual({
      from: 0,
      to: 5,
      insert: "**hello**",
      anchor: 2,
      head: 7,
    })
  })

  it("unwraps when the markers are inside the selection", () => {
    expect(toggleMarker("**hi**", 0, 6, "**")).toEqual({
      from: 0,
      to: 6,
      insert: "hi",
      anchor: 0,
      head: 2,
    })
  })

  it("unwraps when the markers sit just outside the selection", () => {
    // Selecting only "hi" inside **hi** (e.g. a double-click) still toggles off.
    expect(toggleMarker("**hi**", 2, 4, "**")).toEqual({
      from: 0,
      to: 6,
      insert: "hi",
      anchor: 0,
      head: 2,
    })
  })

  it("uses single-char markers for italic and code", () => {
    expect(toggleMarker("word", 0, 4, "_")).toEqual({
      from: 0,
      to: 4,
      insert: "_word_",
      anchor: 1,
      head: 5,
    })
    expect(toggleMarker("code", 0, 4, "`")).toEqual({
      from: 0,
      to: 4,
      insert: "`code`",
      anchor: 1,
      head: 5,
    })
  })

  it("does not read past the start of the document when checking for markers", () => {
    expect(toggleMarker("x", 0, 1, "**")).toEqual({
      from: 0,
      to: 1,
      insert: "**x**",
      anchor: 2,
      head: 3,
    })
  })
})

describe("wrapLink", () => {
  it("wraps a selection as a link and selects the url placeholder", () => {
    const {insert, anchor, head} = wrapLink("text")
    expect(insert).toBe("[text](url)")
    expect(insert.slice(anchor, head)).toBe("url")
  })

  it("parks the caret inside the brackets for an empty selection", () => {
    expect(wrapLink("")).toEqual({insert: "[](url)", anchor: 1, head: 1})
  })
})
