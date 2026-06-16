// Mobile admin navigation drawer. Below the `md` breakpoint the sidebar is an
// off-canvas drawer; this hook (attached to the hamburger button) toggles it,
// with a backdrop, Escape, and auto-close on LiveView navigation. Desktop is
// unaffected — md: rules keep the sidebar visible regardless of this state.
//
// The open state is a class on <html>, which lives OUTSIDE the LiveView-managed
// DOM, with the visuals driven by CSS (see assets/css/admin.css). Keeping it off
// the sidebar element is deliberate: a LiveView re-render (e.g. closing the
// editor's publish drawer via click-away) re-patches the sidebar's class
// attribute and would otherwise wipe a client-toggled open class mid-interaction.

const OPEN_CLASS = "admin-nav-open"

function setOpen(open) {
  document.documentElement.classList.toggle(OPEN_CLASS, open)
}

export const AdminNav = {
  mounted() {
    this.open = () => {
      setOpen(true)
      this.el.setAttribute("aria-expanded", "true")
    }
    this.close = () => {
      setOpen(false)
      this.el.setAttribute("aria-expanded", "false")
    }

    this.el.addEventListener("click", this.open)

    this.backdrop = document.getElementById("admin-sidebar-backdrop")
    if (this.backdrop) this.backdrop.addEventListener("click", this.close)

    this.onKeydown = (e) => {
      if (e.key === "Escape") this.close()
    }
    document.addEventListener("keydown", this.onKeydown)

    window.addEventListener("phx:page-loading-start", this.close)
  },

  destroyed() {
    this.el.removeEventListener("click", this.open)
    if (this.backdrop) this.backdrop.removeEventListener("click", this.close)
    document.removeEventListener("keydown", this.onKeydown)
    window.removeEventListener("phx:page-loading-start", this.close)
  }
}
