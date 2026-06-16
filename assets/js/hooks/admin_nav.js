// Mobile admin navigation drawer. Below the `md` breakpoint the sidebar is an
// off-canvas drawer; this hook (attached to the hamburger button) toggles it,
// with a backdrop, Escape, and auto-close on LiveView navigation. Desktop is
// unaffected — md: classes keep the sidebar visible regardless of these toggles.

function setOpen(open) {
  const sidebar = document.getElementById("admin-sidebar")
  const backdrop = document.getElementById("admin-sidebar-backdrop")
  if (!sidebar || !backdrop) return
  sidebar.classList.toggle("translate-x-0", open)
  sidebar.classList.toggle("-translate-x-full", !open)
  backdrop.classList.toggle("hidden", !open)
}

export const AdminNav = {
  mounted() {
    this.open = () => setOpen(true)
    this.close = () => setOpen(false)

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
