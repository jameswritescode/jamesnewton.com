// Minimal HTML5 drag-and-drop reordering for the photo grid. On drop it reads
// the new child order and pushes the photo-id list to the server. Reorders the
// DOM optimistically; the server persists positions. No external library.
export const SortableGrid = {
  mounted() {
    this.dragEl = null

    this.el.addEventListener("dragstart", (e) => {
      this.dragEl = e.target.closest("[data-id]")
      if (this.dragEl) e.dataTransfer.effectAllowed = "move"
    })

    this.el.addEventListener("dragover", (e) => {
      e.preventDefault()
      const over = e.target.closest("[data-id]")
      if (!over || over === this.dragEl || !this.dragEl) return
      const rect = over.getBoundingClientRect()
      const after = (e.clientX - rect.left) / rect.width > 0.5
      this.el.insertBefore(this.dragEl, after ? over.nextSibling : over)
    })

    this.el.addEventListener("drop", (e) => {
      e.preventDefault()
      this.dragEl = null
      const ids = [...this.el.querySelectorAll("[data-id]")].map((el) => el.dataset.id)
      this.pushEvent("reorder", {ids})
    })
  },
}
