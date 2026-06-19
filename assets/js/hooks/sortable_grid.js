// Minimal HTML5 drag-and-drop reordering for the photo grid. On drop it reads
// the new child order and pushes the photo-id list to the server. Reorders the
// DOM optimistically; the server persists positions. No external library.
//
// Two affordances make the drag legible: the grabbed tile dims into a
// placeholder "hole" (so it's clear what you're holding while the native drag
// image follows the cursor), and neighbours FLIP-slide into their new spots
// rather than snapping, so the reorder reads as smooth and immediate.
export const SortableGrid = {
  mounted() {
    this.dragEl = null
    // Per-tile timers that restore hit-testing once a FLIP slide settles.
    this.flipTimers = new Map()

    this.el.addEventListener("dragstart", (e) => {
      this.dragEl = e.target.closest("[data-id]")
      if (!this.dragEl) return
      e.dataTransfer.effectAllowed = "move"
      // Defer one tick: the browser snapshots the drag image synchronously at
      // dragstart, so dimming now would fade that image too. A tick later only
      // the in-place source dims, leaving the cursor-following image crisp.
      this.dimTimer = setTimeout(() => this.dragEl?.classList.add("is-dragging"), 0)
    })

    this.el.addEventListener("dragover", (e) => {
      e.preventDefault()
      const over = e.target.closest("[data-id]")
      if (!over || over === this.dragEl || !this.dragEl) return
      // Swap the instant the pointer enters a neighbour — no half-way threshold.
      // The side is chosen from the current order so the move follows the drag
      // direction, and the `over === this.dragEl` guard above means the cursor
      // lands on the moved tile afterwards, so it won't flicker back.
      const tiles = [...this.el.querySelectorAll("[data-id]")]
      const draggedBefore = tiles.indexOf(this.dragEl) < tiles.indexOf(over)
      this.flip(() =>
        this.el.insertBefore(this.dragEl, draggedBefore ? over.nextSibling : over)
      )
    })

    this.endDrag = () => {
      clearTimeout(this.dimTimer)
      this.dragEl?.classList.remove("is-dragging")
      this.dragEl = null
      // Settle any in-flight slides so no tile is left untargetable or shifted.
      for (const [el, timer] of this.flipTimers) {
        clearTimeout(timer)
        el.style.pointerEvents = ""
        el.style.transition = ""
        el.style.transform = ""
      }
      this.flipTimers.clear()
    }

    this.el.addEventListener("dragend", this.endDrag)

    this.el.addEventListener("drop", (e) => {
      e.preventDefault()
      const ids = [...this.el.querySelectorAll("[data-id]")].map((el) => el.dataset.id)
      this.endDrag()
      this.pushEvent("reorder", {ids})
    })
  },

  // FLIP: capture each tile's position, mutate the DOM, then animate the moved
  // tiles from their old position to the new one. The grabbed tile is skipped —
  // the native drag image already represents it.
  flip(mutate) {
    const items = [...this.el.querySelectorAll("[data-id]")]
    const before = new Map(items.map((el) => [el, el.getBoundingClientRect()]))
    mutate()
    for (const el of items) {
      if (el === this.dragEl) continue
      const old = before.get(el)
      const now = el.getBoundingClientRect()
      const dx = old.left - now.left
      const dy = old.top - now.top
      if (!dx && !dy) continue
      // While this tile slides, take it out of hit-testing: a mid-slide tile is
      // transformed across the cursor, and if the drag could "land" on it the
      // grid would oscillate. Only settled tiles and the dragged tile remain
      // targetable. Restored once the slide finishes (just after the 150ms).
      el.style.pointerEvents = "none"
      el.style.transition = "none"
      el.style.transform = `translate(${dx}px, ${dy}px)`
      requestAnimationFrame(() => {
        el.style.transition = "transform 150ms ease"
        el.style.transform = ""
      })
      clearTimeout(this.flipTimers.get(el))
      this.flipTimers.set(
        el,
        setTimeout(() => {
          el.style.pointerEvents = ""
          el.style.transition = ""
        }, 160)
      )
    }
  },
}
