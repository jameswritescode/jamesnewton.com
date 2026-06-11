import {describe, it, expect, vi} from "vitest"
import {syncMarkdown} from "./milkdown_editor"

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
