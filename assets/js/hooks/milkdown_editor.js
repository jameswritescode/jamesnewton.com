// Mirror markdown into the hidden form input and notify LiveView, but only when
// it actually changed (so we don't spam phx-change or loop on our own writes).
// Exported separately so it can be unit-tested without loading Milkdown (which
// needs a real browser/ProseMirror and won't run under jsdom).
export function syncMarkdown(input, markdown) {
  if (input.value === markdown) return
  input.value = markdown
  input.dispatchEvent(new Event("input", {bubbles: true}))
}

// phx-hook on a container that also holds a hidden `post[body_markdown]`
// textarea. The container is wrapped in phx-update="ignore" so LiveView never
// patches the editor's DOM after mount.
//
// We build a plain Milkdown editor (commonmark + gfm) rather than Crepe: code
// blocks are native ProseMirror nodes (no CodeMirror), so Backspace/undo behave
// normally and the bundle stays small. Milkdown is loaded via dynamic import so
// this module is safe to import in tests.
export const MilkdownEditor = {
  async mounted() {
    const [{Editor, rootCtx, defaultValueCtx}, {commonmark}, {gfm}, {listener, listenerCtx}, {history}] =
      await Promise.all([
        import("@milkdown/kit/core"),
        import("@milkdown/kit/preset/commonmark"),
        import("@milkdown/kit/preset/gfm"),
        import("@milkdown/kit/plugin/listener"),
        import("@milkdown/kit/plugin/history"),
      ])

    const input = document.getElementById(this.el.dataset.inputId)
    const initial = input ? input.value : ""

    this.editor = await Editor.make()
      .config((ctx) => {
        ctx.set(rootCtx, this.el)
        ctx.set(defaultValueCtx, initial)
        ctx.get(listenerCtx).markdownUpdated((_ctx, markdown) => {
          if (input) syncMarkdown(input, markdown)
        })
      })
      .use(listener)
      .use(commonmark)
      .use(gfm)
      .use(history)
      .create()
  },

  destroyed() {
    this.editor?.destroy()
  },
}
