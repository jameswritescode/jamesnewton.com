import {describe, it, expect, vi} from "vitest"
import {
  syncMarkdown,
  imageFiles,
  imageMarkdown,
  uploadToken,
  uploadPlaceholder,
  findPlaceholder,
  classifyFiles,
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

describe("uploadToken", () => {
  it("is six hex characters, zero-padded", () => {
    expect(uploadToken(() => 0)).toBe("000000")
    expect(uploadToken(() => 0.9999999)).toMatch(/^[0-9a-f]{6}$/)
  })
})

describe("uploadPlaceholder", () => {
  it("builds an uploading marker from the filename and token", () => {
    expect(uploadPlaceholder("shot.png", "a1b2c3")).toBe("![Uploading shot.png (a1b2c3)…]()")
  })

  it("works without a token", () => {
    expect(uploadPlaceholder("shot.png")).toBe("![Uploading shot.png…]()")
  })

  it("strips characters that would break the markdown image syntax", () => {
    expect(uploadPlaceholder("we[ird](x)`\nname.png", "a1b2c3")).toBe(
      "![Uploading weirdxname.png (a1b2c3)…]()"
    )
  })
})

describe("findPlaceholder", () => {
  it("locates the placeholder's range in the document", () => {
    const doc = "intro\n![Uploading shot.png (a1b2c3)…]()\noutro"
    expect(findPlaceholder(doc, "shot.png", "a1b2c3")).toEqual({from: 6, to: 39})
  })

  it("distinguishes two same-named uploads by token", () => {
    const first = uploadPlaceholder("image.png", "aaaaaa")
    const second = uploadPlaceholder("image.png", "bbbbbb")
    const doc = `${first}\n${second}`
    expect(findPlaceholder(doc, "image.png", "bbbbbb")).toEqual({
      from: first.length + 1,
      to: first.length + 1 + second.length,
    })
  })

  it("returns null when the author deleted the placeholder", () => {
    expect(findPlaceholder("no placeholders here", "shot.png", "a1b2c3")).toBeNull()
  })
})

describe("classifyFiles", () => {
  const cfg = {exts: [".png", ".jpg"], maxEntries: 2, maxFileSize: 100}
  const f = (name, size) => ({name, size, type: "image/png"})

  it("accepts files within every limit", () => {
    const {ok, rejected} = classifyFiles([f("a.png", 10), f("b.JPG", 99)], cfg)
    expect(ok.map((x) => x.name)).toEqual(["a.png", "b.JPG"])
    expect(rejected).toEqual([])
  })

  it("rejects extensions outside the accept list", () => {
    const {ok, rejected} = classifyFiles([f("a.svg", 10)], cfg)
    expect(ok).toEqual([])
    expect(rejected).toEqual([{name: "a.svg", reason: "type"}])
  })

  it("rejects oversize files", () => {
    expect(classifyFiles([f("a.png", 101)], cfg).rejected).toEqual([
      {name: "a.png", reason: "size"},
    ])
  })

  it("rejects files beyond the entry cap", () => {
    const {ok, rejected} = classifyFiles([f("a.png", 1), f("b.png", 1), f("c.png", 1)], cfg)
    expect(ok.map((x) => x.name)).toEqual(["a.png", "b.png"])
    expect(rejected).toEqual([{name: "c.png", reason: "count"}])
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
