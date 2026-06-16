import {describe, it, expect, beforeEach, vi, afterEach} from "vitest"
import {UnsavedGuard} from "./unsaved_guard"

function mount(unsaved) {
  document.body.innerHTML = `
    <div id="unsaved-guard" data-unsaved="${unsaved}"></div>
    <a id="nav" href="/admin/posts" data-phx-link="redirect">Posts</a>
  `
  const el = document.getElementById("unsaved-guard")
  const hook = Object.create(UnsavedGuard)
  hook.el = el
  hook.mounted()
  return {hook, el, link: document.getElementById("nav")}
}

const fireBeforeUnload = () => {
  const e = new Event("beforeunload", {cancelable: true})
  window.dispatchEvent(e)
  return e
}
const clickLink = (link) => {
  const e = new MouseEvent("click", {bubbles: true, cancelable: true})
  link.dispatchEvent(e)
  return e
}

describe("UnsavedGuard hook", () => {
  beforeEach(() => (document.body.innerHTML = ""))
  afterEach(() => vi.restoreAllMocks())

  it("prevents unload when dirty", () => {
    mount("true")
    expect(fireBeforeUnload().defaultPrevented).toBe(true)
  })

  it("allows unload when not dirty", () => {
    mount("false")
    expect(fireBeforeUnload().defaultPrevented).toBe(false)
  })

  it("blocks a nav-link click when dirty and the user cancels confirm", () => {
    const {link} = mount("true")
    vi.spyOn(window, "confirm").mockReturnValue(false)
    expect(clickLink(link).defaultPrevented).toBe(true)
  })

  it("allows a nav-link click when dirty and the user accepts confirm", () => {
    const {link} = mount("true")
    vi.spyOn(window, "confirm").mockReturnValue(true)
    expect(clickLink(link).defaultPrevented).toBe(false)
  })

  it("allows a nav-link click when not dirty without confirming", () => {
    const {link} = mount("false")
    const confirm = vi.spyOn(window, "confirm")
    expect(clickLink(link).defaultPrevented).toBe(false)
    expect(confirm).not.toHaveBeenCalled()
  })

  it("stops guarding after destroyed()", () => {
    const {hook} = mount("true")
    hook.destroyed()
    expect(fireBeforeUnload().defaultPrevented).toBe(false)
  })
})
