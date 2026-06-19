export function syncMarkdown(field, markdown) {
  if (field.value === markdown) return
  field.value = markdown
  field.dispatchEvent(new Event("input", {bubbles: true}))
}

// Filter a FileList/array to the entries that are images.
export function imageFiles(list) {
  return Array.from(list || []).filter((f) => f.type && f.type.startsWith("image/"))
}

// Markdown for an inline image with an empty alt. caretOffset parks the cursor
// just after the `![` so the author can type the alt text immediately.
export function imageMarkdown(url) {
  return {text: `![](${url})`, caretOffset: 2}
}

// Toggle a symmetric inline marker (e.g. "**" for bold) around the selection
// [from, to) of `doc`. Returns the document change plus the selection to keep:
// {from, to, insert, anchor, head} with all offsets in document coordinates.
//
//   - empty selection  → insert the pair, caret parked between them
//   - plain selection  → wrap it
//   - already wrapped  → unwrap (markers inside the selection *or* just outside
//                        it, so double-clicking a word inside **bold** toggles)
export function toggleMarker(doc, from, to, marker) {
  const len = marker.length
  let f = from
  let t = to
  let sel = doc.slice(from, to)

  const before = from >= len ? doc.slice(from - len, from) : ""
  const after = doc.slice(to, to + len)
  if (before === marker && after === marker) {
    f = from - len
    t = to + len
    sel = marker + sel + marker
  }

  const wrapped = sel.length >= 2 * len && sel.startsWith(marker) && sel.endsWith(marker)
  if (wrapped) {
    const inner = sel.slice(len, sel.length - len)
    return {from: f, to: t, insert: inner, anchor: f, head: f + inner.length}
  }

  const insert = marker + sel + marker
  return {from: f, to: t, insert, anchor: f + len, head: f + len + sel.length}
}

// Link markdown for the selection. anchor/head are offsets within `insert`:
// a selection puts the `url` placeholder under the selection so it's ready to
// type/paste; an empty selection parks the caret inside the `[]`.
export function wrapLink(selected) {
  if (selected) {
    const insert = `[${selected}](url)`
    const anchor = insert.length - 4
    return {insert, anchor, head: anchor + 3}
  }
  return {insert: "[](url)", anchor: 1, head: 1}
}

const PLACEHOLDER_TEXT = "Write your post in markdown…"

// Dynamic import keeps CodeMirror out of the test bundle.
export const MarkdownEditor = {
  async mounted() {
    const [
      {EditorView, keymap, placeholder, Decoration, ViewPlugin},
      {EditorState, EditorSelection, RangeSetBuilder},
      {markdown, markdownLanguage},
      {languages},
      {HighlightStyle, syntaxHighlighting, indentOnInput, syntaxTree},
      {tags: t},
      {history, defaultKeymap, historyKeymap, indentWithTab},
    ] = await Promise.all([
      import("@codemirror/view"),
      import("@codemirror/state"),
      import("@codemirror/lang-markdown"),
      import("@codemirror/language-data"),
      import("@codemirror/language"),
      import("@lezer/highlight"),
      import("@codemirror/commands"),
    ])

    const field = document.getElementById(this.el.dataset.inputId)
    const initial = field ? field.value : ""

    const highlight = HighlightStyle.define([
      {tag: t.heading1, fontSize: "1.7em", fontWeight: "400"},
      {tag: t.heading2, fontSize: "1.4em", fontWeight: "400"},
      {tag: t.heading3, fontSize: "1.2em", fontWeight: "400"},
      {tag: [t.heading4, t.heading5, t.heading6], fontWeight: "400"},
      {tag: t.strong, fontWeight: "600"},
      {tag: t.emphasis, fontStyle: "italic"},
      {tag: t.strikethrough, textDecoration: "line-through"},
      {tag: t.link, color: "var(--admin-accent)"},
      {tag: t.url, color: "var(--admin-text-subtle)"},
      {tag: t.monospace, color: "var(--admin-accent)", fontFamily: "ui-monospace, monospace"},
      {tag: t.quote, color: "var(--admin-text-muted)", fontStyle: "italic"},
      {tag: t.list, color: "var(--admin-text-muted)"},
      {tag: t.processingInstruction, color: "var(--admin-text-subtle)"},
      {tag: t.keyword, color: "var(--ed-syntax-keyword)"},
      {tag: [t.string, t.special(t.string)], color: "var(--ed-syntax-string)"},
      {tag: t.comment, color: "var(--admin-text-subtle)", fontStyle: "italic"},
      {tag: t.number, color: "var(--ed-syntax-number)"},
      {tag: [t.function(t.variableName), t.definition(t.variableName)], color: "var(--ed-syntax-function)"},
      {tag: [t.typeName, t.className], color: "var(--ed-syntax-function)"},
      {tag: [t.bool, t.null, t.atom], color: "var(--ed-syntax-keyword)"},
    ])

    // Per-token styling alone leaves untokenized code in the serif body font, so
    // decorate whole fenced/indented lines for a monospace, boxed look.
    const codeLine = Decoration.line({class: "cm-code-line"})
    const codeBlockLines = ViewPlugin.fromClass(
      class {
        constructor(view) {
          this.decorations = this.build(view)
        }

        update(update) {
          if (update.docChanged || update.viewportChanged) {
            this.decorations = this.build(update.view)
          }
        }

        build(view) {
          const builder = new RangeSetBuilder()
          for (const {from, to} of view.visibleRanges) {
            syntaxTree(view.state).iterate({
              from,
              to,
              enter: (node) => {
                if (node.name !== "FencedCode" && node.name !== "CodeBlock") return
                let pos = node.from
                while (pos <= node.to) {
                  const line = view.state.doc.lineAt(pos)
                  builder.add(line.from, line.from, codeLine)
                  pos = line.to + 1
                }
              },
            })
          }
          return builder.finish()
        }
      },
      {decorations: (plugin) => plugin.decorations}
    )

    const theme = EditorView.theme({
      "&": {
        backgroundColor: "var(--admin-surface)",
        color: "var(--admin-text)",
        borderRadius: "0.5rem",
      },
      ".cm-content": {
        fontFamily: '"Lora", Georgia, "Times New Roman", serif',
        fontSize: "1rem",
        lineHeight: "1.7",
        padding: "1.5rem 1.75rem",
        caretColor: "var(--admin-accent)",
        minHeight: "24rem",
      },
      "&.cm-focused": {outline: "none"},
      ".cm-cursor, .cm-dropCursor": {borderLeftColor: "var(--admin-accent)"},
      "&.cm-focused .cm-selectionBackground, .cm-selectionBackground": {
        backgroundColor: "var(--admin-accent-soft)",
      },
      ".cm-placeholder": {color: "var(--admin-text-subtle)", fontStyle: "normal"},
      ".cm-code-line": {
        fontFamily: "ui-monospace, monospace",
        fontSize: "0.85em",
        backgroundColor: "var(--admin-bg)",
      },
    })

    // Commands for the markdown formatting shortcuts. Each maps every selection
    // through a pure helper, so multi-cursor edits stay correct.
    const toggle = (marker) => (view) => {
      view.dispatch(
        view.state.changeByRange((range) => {
          const r = toggleMarker(view.state.doc.toString(), range.from, range.to, marker)
          return {
            changes: {from: r.from, to: r.to, insert: r.insert},
            range: EditorSelection.range(r.anchor, r.head),
          }
        })
      )
      return true
    }
    const insertLink = (view) => {
      view.dispatch(
        view.state.changeByRange((range) => {
          const {insert, anchor, head} = wrapLink(view.state.doc.sliceString(range.from, range.to))
          return {
            changes: {from: range.from, to: range.to, insert},
            range: EditorSelection.range(range.from + anchor, range.from + head),
          }
        })
      )
      return true
    }
    const markdownKeymap = keymap.of([
      {key: "Mod-b", run: toggle("**"), preventDefault: true},
      {key: "Mod-i", run: toggle("_"), preventDefault: true},
      {key: "Mod-e", run: toggle("`"), preventDefault: true},
      {key: "Mod-k", run: insertLink, preventDefault: true},
    ])

    this.view = new EditorView({
      parent: this.el,
      state: EditorState.create({
        doc: initial,
        extensions: [
          history(),
          indentOnInput(),
          // Higher precedence than the default keymap so the shortcuts win.
          markdownKeymap,
          keymap.of([...defaultKeymap, ...historyKeymap, indentWithTab]),
          EditorView.lineWrapping,
          markdown({base: markdownLanguage, codeLanguages: languages}),
          syntaxHighlighting(highlight),
          codeBlockLines,
          theme,
          placeholder(PLACEHOLDER_TEXT),
          EditorView.updateListener.of((update) => {
            if (update.docChanged && field) syncMarkdown(field, update.state.doc.toString())
          }),
        ],
      }),
    })

    // Insert image markdown at the current selection when the server reports a
    // finished upload. The updateListener above syncs the textarea → autosave.
    this.handleEvent("insert_image", ({url}) => {
      if (!this.view) return
      const {text, caretOffset} = imageMarkdown(url)
      const {from, to} = this.view.state.selection.main
      this.view.dispatch({
        changes: {from, to, insert: text},
        selection: {anchor: from + caretOffset},
      })
      this.view.focus()
    })

    // Drag a file onto the editor → upload it. dragover must preventDefault so
    // the browser treats the editor as a drop target.
    this.onDragOver = (e) => e.preventDefault()
    this.onDrop = (e) => {
      const files = imageFiles(e.dataTransfer && e.dataTransfer.files)
      if (!files.length) return
      e.preventDefault()
      this.upload("inline_images", files)
    }
    // Paste a screenshot/image → upload it (and preventDefault so CodeMirror
    // doesn't also paste a filename or blob text).
    this.onPaste = (e) => {
      const files = imageFiles(e.clipboardData && e.clipboardData.files)
      if (!files.length) return
      e.preventDefault()
      this.upload("inline_images", files)
    }
    this.el.addEventListener("dragover", this.onDragOver)
    this.el.addEventListener("drop", this.onDrop)
    this.el.addEventListener("paste", this.onPaste)
  },

  destroyed() {
    if (this.onDragOver) this.el.removeEventListener("dragover", this.onDragOver)
    if (this.onDrop) this.el.removeEventListener("drop", this.onDrop)
    if (this.onPaste) this.el.removeEventListener("paste", this.onPaste)
    this.view?.destroy()
  },
}
