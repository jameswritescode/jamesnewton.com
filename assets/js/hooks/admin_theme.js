// Admin light/dark theme. Follows the OS preference by default and lets the
// user override it with a remembered manual choice (localStorage "admin-theme").
// The chosen theme is reflected as `data-admin-theme` on <html>, which drives
// the token palette in assets/css/admin.css. A matching inline script in the
// admin root layout applies the theme before first paint to avoid a flash.

const STORAGE_KEY = "admin-theme"

function systemTheme() {
  return matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light"
}

function storedTheme() {
  try {
    return localStorage.getItem(STORAGE_KEY)
  } catch (_) {
    return null
  }
}

function effectiveTheme() {
  return storedTheme() || systemTheme()
}

// The swap must not animate: hover styles use transition-colors, which would
// otherwise tween every themed property when the palette attribute flips. The
// guard attribute disables transitions (see admin.css), the forced reflow
// applies the new palette while they're off, and the next frame re-enables.
function applyTheme(theme) {
  const root = document.documentElement
  root.setAttribute("data-admin-theme-switching", "")
  root.setAttribute("data-admin-theme", theme)
  void root.offsetWidth
  requestAnimationFrame(() => root.removeAttribute("data-admin-theme-switching"))
}

export const AdminTheme = {
  mounted() {
    applyTheme(effectiveTheme())

    this.onClick = () => {
      const next = document.documentElement.getAttribute("data-admin-theme") === "dark" ? "light" : "dark"
      try {
        localStorage.setItem(STORAGE_KEY, next)
      } catch (_) {
        // ignore storage failures; theme still applies for this session
      }
      applyTheme(next)
    }
    this.el.addEventListener("click", this.onClick)

    // Track the OS preference while the user hasn't made a manual choice.
    this.mq = matchMedia("(prefers-color-scheme: dark)")
    this.onSystemChange = () => {
      if (!storedTheme()) applyTheme(systemTheme())
    }
    this.mq.addEventListener("change", this.onSystemChange)
  },

  destroyed() {
    this.el.removeEventListener("click", this.onClick)
    this.mq.removeEventListener("change", this.onSystemChange)
  },
}
