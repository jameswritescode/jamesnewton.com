import {describe, it, expect, beforeEach} from "vitest"
import {AdminNav} from "./admin_nav"

function setup() {
  document.body.innerHTML = `
    <button id="admin-nav-toggle">menu</button>
    <aside id="admin-sidebar" class="-translate-x-full"></aside>
    <div id="admin-sidebar-backdrop" class="hidden"></div>
  `
  const toggle = document.getElementById("admin-nav-toggle")
  const hook = Object.create(AdminNav)
  hook.el = toggle
  hook.mounted()
  return {
    hook,
    toggle,
    sidebar: document.getElementById("admin-sidebar"),
    backdrop: document.getElementById("admin-sidebar-backdrop")
  }
}

const isOpen = (sidebar, backdrop) =>
  sidebar.classList.contains("translate-x-0") &&
  !sidebar.classList.contains("-translate-x-full") &&
  !backdrop.classList.contains("hidden")

describe("AdminNav hook", () => {
  beforeEach(() => (document.body.innerHTML = ""))

  it("opens the drawer when the toggle is clicked", () => {
    const {toggle, sidebar, backdrop} = setup()
    toggle.dispatchEvent(new MouseEvent("click", {bubbles: true}))
    expect(isOpen(sidebar, backdrop)).toBe(true)
  })

  it("closes on backdrop click", () => {
    const {toggle, sidebar, backdrop} = setup()
    toggle.dispatchEvent(new MouseEvent("click", {bubbles: true}))
    backdrop.dispatchEvent(new MouseEvent("click", {bubbles: true}))
    expect(isOpen(sidebar, backdrop)).toBe(false)
  })

  it("closes on Escape", () => {
    const {toggle, sidebar, backdrop} = setup()
    toggle.dispatchEvent(new MouseEvent("click", {bubbles: true}))
    document.dispatchEvent(new KeyboardEvent("keydown", {key: "Escape"}))
    expect(isOpen(sidebar, backdrop)).toBe(false)
  })

  it("closes on navigation (phx:page-loading-start)", () => {
    const {toggle, sidebar, backdrop} = setup()
    toggle.dispatchEvent(new MouseEvent("click", {bubbles: true}))
    window.dispatchEvent(new Event("phx:page-loading-start"))
    expect(isOpen(sidebar, backdrop)).toBe(false)
    expect(toggle.getAttribute("aria-expanded")).toBe("false")
  })

  it("sets aria-expanded to true when opened and false when closed", () => {
    const {toggle, backdrop} = setup()
    expect(toggle.getAttribute("aria-expanded")).toBeNull()
    toggle.dispatchEvent(new MouseEvent("click", {bubbles: true}))
    expect(toggle.getAttribute("aria-expanded")).toBe("true")
    backdrop.dispatchEvent(new MouseEvent("click", {bubbles: true}))
    expect(toggle.getAttribute("aria-expanded")).toBe("false")
  })

  it("sets aria-expanded to false when closed via Escape", () => {
    const {toggle} = setup()
    toggle.dispatchEvent(new MouseEvent("click", {bubbles: true}))
    expect(toggle.getAttribute("aria-expanded")).toBe("true")
    document.dispatchEvent(new KeyboardEvent("keydown", {key: "Escape"}))
    expect(toggle.getAttribute("aria-expanded")).toBe("false")
  })

  it("stops responding to events after destroyed()", () => {
    const {hook, toggle, sidebar, backdrop} = setup()
    hook.destroyed()
    // toggle click should not open the drawer
    toggle.dispatchEvent(new MouseEvent("click", {bubbles: true}))
    expect(isOpen(sidebar, backdrop)).toBe(false)
    // Escape should not close (drawer is already closed, but verify no error and no state change)
    document.dispatchEvent(new KeyboardEvent("keydown", {key: "Escape"}))
    expect(isOpen(sidebar, backdrop)).toBe(false)
  })
})
