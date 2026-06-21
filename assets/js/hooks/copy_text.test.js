import {describe, it, expect, vi, afterEach} from "vitest"
import {CopyText} from "./copy_text"

function mount(el) {
  const hook = {el}
  Object.setPrototypeOf(hook, CopyText)
  hook.mounted()
  return hook
}

afterEach(() => {
  vi.restoreAllMocks()
  vi.unstubAllGlobals()
})

describe("CopyText", () => {
  it("writes the data-clipboard-text value to the clipboard on click", async () => {
    const writeText = vi.fn().mockResolvedValue()
    vi.stubGlobal("navigator", {clipboard: {writeText}})

    const btn = document.createElement("button")
    btn.dataset.clipboardText = "https://example.com/posts/x?p=tok"
    mount(btn)

    btn.dispatchEvent(new MouseEvent("click", {bubbles: true}))

    expect(writeText).toHaveBeenCalledWith("https://example.com/posts/x?p=tok")
  })

  it("does nothing when there is no text to copy", () => {
    const writeText = vi.fn().mockResolvedValue()
    vi.stubGlobal("navigator", {clipboard: {writeText}})

    const btn = document.createElement("button")
    mount(btn)

    btn.dispatchEvent(new MouseEvent("click", {bubbles: true}))

    expect(writeText).not.toHaveBeenCalled()
  })
})
