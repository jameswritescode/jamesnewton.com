// Dismiss an admin toast on click WITHOUT the click reaching LiveView's
// window-level click handler. That handler runs phx-click-away for open drawers
// in the same pass, so an unguarded toast click is treated as "outside" the
// drawer and closes it. We stop propagation and replay the toast's own phx-click
// (clear-flash + hide) directly, so the toast still dismisses but no drawer does.

export const FlashDismiss = {
  mounted() {
    this.onClick = (e) => {
      e.stopPropagation()
      this.liveSocket.execJS(this.el, this.el.getAttribute("phx-click"))
    }
    this.el.addEventListener("click", this.onClick)
  },

  destroyed() {
    this.el.removeEventListener("click", this.onClick)
  }
}
