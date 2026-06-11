import {describe, it, expect, vi, beforeEach, afterEach} from "vitest"
import {AdminTheme} from "./admin_theme"

// Mount the hook against a fake button element with a controllable matchMedia.
// Returns the element and a `setSystem` helper that flips the OS preference and
// fires the media "change" listener the hook registered.
function mount({system = "light", stored = null} = {}) {
  if (stored) localStorage.setItem("admin-theme", stored)

  let matches = system === "dark"
  let changeHandler = null
  const mql = {
    get matches() {
      return matches
    },
    addEventListener: (_event, cb) => {
      changeHandler = cb
    },
    removeEventListener: vi.fn()
  }
  window.matchMedia = vi.fn(() => mql)

  const el = document.createElement("button")
  const hook = Object.create(AdminTheme)
  hook.el = el
  hook.mounted()

  const setSystem = (next) => {
    matches = next === "dark"
    changeHandler && changeHandler()
  }

  return {el, setSystem}
}

const theme = () => document.documentElement.getAttribute("data-admin-theme")
const click = (el) => el.dispatchEvent(new MouseEvent("click", {bubbles: true}))

describe("AdminTheme hook", () => {
  beforeEach(() => {
    // jsdom's default opaque origin disables localStorage, so stub a simple
    // in-memory implementation that both the test and the hook share.
    const store = {}
    vi.stubGlobal("localStorage", {
      getItem: (key) => (key in store ? store[key] : null),
      setItem: (key, value) => {
        store[key] = String(value)
      },
      removeItem: (key) => {
        delete store[key]
      },
      clear: () => {
        for (const key in store) delete store[key]
      }
    })
    document.documentElement.removeAttribute("data-admin-theme")
  })

  afterEach(() => vi.unstubAllGlobals())

  it("applies the system theme on mount when there is no stored choice", () => {
    mount({system: "dark"})
    expect(theme()).toBe("dark")
  })

  it("prefers a stored choice over the system theme", () => {
    mount({system: "dark", stored: "light"})
    expect(theme()).toBe("light")
  })

  it("toggles and persists the choice on click", () => {
    const {el} = mount({system: "light"})
    expect(theme()).toBe("light")

    click(el)
    expect(theme()).toBe("dark")
    expect(localStorage.getItem("admin-theme")).toBe("dark")

    click(el)
    expect(theme()).toBe("light")
    expect(localStorage.getItem("admin-theme")).toBe("light")
  })

  it("follows later system changes only while no manual choice is stored", () => {
    const {setSystem} = mount({system: "light"})
    setSystem("dark")
    expect(theme()).toBe("dark")

    // A manual choice pins the theme; system changes no longer apply.
    localStorage.setItem("admin-theme", "light")
    document.documentElement.setAttribute("data-admin-theme", "light")
    setSystem("light")
    setSystem("dark")
    expect(theme()).toBe("light")
  })
})
