// Warns before leaving the post editor with unsaved changes on a published post.
// Driven by data-unsaved on this.el (the server sets it true only when published
// AND dirty). Guards browser tab close/refresh via the native beforeunload prompt
// and in-app LiveView navigation via a capture-phase click intercept on nav links.

export const UnsavedGuard = {
  mounted() {
    this.dirty = () => this.el.isConnected && this.el.dataset.unsaved === "true"

    this.onBeforeUnload = (e) => {
      if (this.dirty()) {
        e.preventDefault()
        e.returnValue = ""
      }
    }
    window.addEventListener("beforeunload", this.onBeforeUnload)

    this.onClick = (e) => {
      if (!this.dirty()) return
      if (!e.target.closest("a[data-phx-link]")) return
      if (!window.confirm("You have unsaved changes. Leave without saving?")) {
        // LiveView's window-level nav handler navigates without checking
        // defaultPrevented, so stopPropagation (from this capture-phase listener)
        // is what cancels the live nav; preventDefault stops the native href.
        e.preventDefault()
        e.stopPropagation()
      }
    }
    // Capture phase so we intercept before LiveView's bubble-phase handler.
    document.addEventListener("click", this.onClick, true)
  },

  destroyed() {
    window.removeEventListener("beforeunload", this.onBeforeUnload)
    document.removeEventListener("click", this.onClick, true)
  }
}
