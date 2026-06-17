import {describe, it, expect, vi, beforeEach} from "vitest"
import {FlashDismiss} from "./flash_dismiss"

function mount() {
  document.body.innerHTML = `<div id="wrap"><div id="toast" phx-click="ENCODED-JS"></div></div>`
  const el = document.getElementById("toast")
  const execJS = vi.fn()
  const hook = Object.create(FlashDismiss)
  hook.el = el
  hook.liveSocket = {execJS}
  hook.mounted()
  return {el, execJS, hook}
}

const click = (el) => el.dispatchEvent(new MouseEvent("click", {bubbles: true}))

describe("FlashDismiss hook", () => {
  beforeEach(() => (document.body.innerHTML = ""))

  it("replays the toast's own phx-click on click", () => {
    const {el, execJS} = mount()
    click(el)
    expect(execJS).toHaveBeenCalledWith(el, "ENCODED-JS")
  })

  it("stops the click from propagating so a drawer's click-away won't fire", () => {
    const {el} = mount()
    const ancestorHandler = vi.fn()
    document.getElementById("wrap").addEventListener("click", ancestorHandler)
    click(el)
    expect(ancestorHandler).not.toHaveBeenCalled()
  })

  it("stops responding after destroyed()", () => {
    const {el, execJS, hook} = mount()
    hook.destroyed()
    click(el)
    expect(execJS).not.toHaveBeenCalled()
  })
})
