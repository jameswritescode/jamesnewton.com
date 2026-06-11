// Mirror markdown into the hidden form input and notify LiveView, but only when
// it actually changed (so we don't spam phx-change or loop on our own writes).
// Exported separately so it can be unit-tested without loading Milkdown (which
// needs a real browser/ProseMirror and won't run under jsdom).
export function syncMarkdown(input, markdown) {
  if (input.value === markdown) return
  input.value = markdown
  input.dispatchEvent(new Event("input", {bubbles: true}))
}

const PLACEHOLDER_TEXT = "Write your post in markdown…"

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
    const [
      {Editor, rootCtx, defaultValueCtx},
      {commonmark},
      {gfm},
      {listener, listenerCtx},
      {history},
      {$prose},
      {Plugin, PluginKey, TextSelection},
      {Decoration, DecorationSet},
      {keymap},
      {prism, prismConfig},
      languages,
    ] = await Promise.all([
      import("@milkdown/kit/core"),
      import("@milkdown/kit/preset/commonmark"),
      import("@milkdown/kit/preset/gfm"),
      import("@milkdown/kit/plugin/listener"),
      import("@milkdown/kit/plugin/history"),
      import("@milkdown/kit/utils"),
      import("@milkdown/kit/prose/state"),
      import("@milkdown/kit/prose/view"),
      import("@milkdown/kit/prose/keymap"),
      import("@milkdown/plugin-prism"),
      // Refractor languages, in dependency order (base langs before dependents).
      Promise.all([
        import("refractor/markup"),
        import("refractor/css"),
        import("refractor/javascript"),
        import("refractor/json"),
        import("refractor/bash"),
        import("refractor/python"),
        import("refractor/ruby"),
        import("refractor/elixir"),
        import("refractor/sql"),
        import("refractor/markdown"),
        import("refractor/typescript"),
        import("refractor/jsx"),
        import("refractor/tsx"),
      ]),
    ])

    // Show a placeholder while the document is a single empty block.
    const placeholder = $prose(
      () =>
        new Plugin({
          key: new PluginKey("MILKDOWN_PLACEHOLDER"),
          props: {
            decorations(state) {
              const {doc} = state
              const empty =
                doc.childCount === 1 &&
                doc.firstChild?.isTextblock &&
                doc.firstChild.content.size === 0

              if (!empty) return null

              return DecorationSet.create(doc, [
                Decoration.node(0, doc.firstChild.nodeSize, {
                  class: "is-empty",
                  "data-placeholder": PLACEHOLDER_TEXT,
                }),
              ])
            },
          },
        })
    )

    // At the start of a code block, Backspace escapes the block instead of
    // joining it backward (which flattens the code and loses its line breaks).
    const codeBlockBackspace = $prose(() =>
      keymap({
        Backspace: (state, dispatch) => {
          const {selection} = state
          if (!selection.empty) return false

          const {$from} = selection
          if ($from.parent.type.name !== "code_block" || $from.parentOffset !== 0) return false

          const start = $from.before()

          // Empty code block: remove it entirely.
          if ($from.parent.content.size === 0) {
            if (dispatch) dispatch(state.tr.delete(start, $from.after()).scrollIntoView())
            return true
          }

          // Non-empty: move the cursor out (above) without merging.
          if (start === 0) {
            if (dispatch) {
              const tr = state.tr.insert(0, state.schema.nodes.paragraph.create())
              tr.setSelection(TextSelection.create(tr.doc, 1))
              dispatch(tr.scrollIntoView())
            }
            return true
          }

          if (dispatch) {
            const sel = TextSelection.near(state.doc.resolve(start), -1)
            dispatch(state.tr.setSelection(sel).scrollIntoView())
          }
          return true
        },
      })
    )

    const input = document.getElementById(this.el.dataset.inputId)
    const initial = input ? input.value : ""

    this.editor = await Editor.make()
      .config((ctx) => {
        ctx.set(rootCtx, this.el)
        ctx.set(defaultValueCtx, initial)
        ctx.get(listenerCtx).markdownUpdated((_ctx, markdown) => {
          if (input) syncMarkdown(input, markdown)
        })
        ctx.set(prismConfig.key, {
          configureRefractor: (refractor) => {
            languages.forEach((mod) => refractor.register(mod.default))
          },
        })
      })
      .use(listener)
      .use(commonmark)
      .use(gfm)
      .use(history)
      .use(placeholder)
      .use(codeBlockBackspace)
      .use(prism)
      .create()
  },

  destroyed() {
    this.editor?.destroy()
  },
}
