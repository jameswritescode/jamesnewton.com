// Mirror markdown into the hidden form input and notify LiveView, but only when
// it actually changed (so we don't spam phx-change or loop on our own writes).
// Exported separately so it can be unit-tested without loading Milkdown (which
// needs a real browser/ProseMirror and won't run under jsdom).
export function syncMarkdown(input, markdown) {
  if (input.value === markdown) return
  input.value = markdown
  input.dispatchEvent(new Event("input", {bubbles: true}))
}

// phx-hook on a container that also holds a hidden `post[body_markdown]` input.
// The container is wrapped in phx-update="ignore" so LiveView never patches the
// editor's DOM after mount. Crepe is loaded via dynamic import so this module is
// safe to import in tests.
export const MilkdownEditor = {
  async mounted() {
    const [{Crepe}, {listener, listenerCtx}] = await Promise.all([
      import("@milkdown/crepe"),
      import("@milkdown/plugin-listener"),
    ])

    const input = document.getElementById(this.el.dataset.inputId)
    const initial = input ? input.value : ""

    this.crepe = new Crepe({
      root: this.el,
      defaultValue: initial,
      // Disable the block handle (the ⠿ drag grip + "+" add-block button).
      // Code blocks keep the CodeMirror feature (it provides the code-block
      // node), but its chrome is simplified via CSS in admin.css.
      features: {"block-edit": false},
    })
    this.crepe.editor.use(listener)
    this.crepe.editor.config((ctx) => {
      ctx.get(listenerCtx).markdownUpdated((_ctx, markdown) => {
        if (input) syncMarkdown(input, markdown)
      })
    })

    await this.crepe.create()
  },

  destroyed() {
    this.crepe?.destroy()
  },
}
