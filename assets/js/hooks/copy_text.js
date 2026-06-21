// Copies the value of `data-clipboard-text` to the clipboard on click, and
// briefly marks the element via `data-copied` so CSS can show a "Copied" state.
export const CopyText = {
  mounted() {
    this.el.addEventListener("click", () => {
      const text = this.el.dataset.clipboardText
      if (!text) return
      navigator.clipboard.writeText(text).then(() => {
        this.el.setAttribute("data-copied", "true")
        clearTimeout(this._t)
        this._t = setTimeout(() => this.el.removeAttribute("data-copied"), 1500)
      })
    })
  },

  destroyed() {
    clearTimeout(this._t)
  },
}
