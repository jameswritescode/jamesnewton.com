// Mirror the editor's markdown into the hidden form field and notify LiveView,
// but only when it actually changed. Exported separately so it can be
// unit-tested without loading CodeMirror.
export function syncMarkdown(field, markdown) {
  if (field.value === markdown) return
  field.value = markdown
  field.dispatchEvent(new Event("input", {bubbles: true}))
}

const PLACEHOLDER_TEXT = "Write your post in markdown…"

// An Obsidian-style "styled source" editor: the markdown stays visible (##, **,
// backticks, [text](url)) but is styled in place, and everything is directly
// editable as text. Built on CodeMirror 6 + markdown — the editor's content IS
// the markdown, so there's no rendering/serialization layer. Loaded via dynamic
// import so this module is safe to import in tests.
export const MarkdownEditor = {
  async mounted() {
    const [
      {EditorView, keymap, placeholder, lineNumbers},
      {EditorState},
      {markdown, markdownLanguage},
      {languages},
      {HighlightStyle, syntaxHighlighting, indentOnInput},
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

    // Style markdown tokens in place (markers dimmed, content emphasized), plus
    // the common code tokens inside fenced blocks. Colors reference admin tokens
    // so the editor follows light/dark.
    const highlight = HighlightStyle.define([
      {tag: t.heading1, fontSize: "1.6em", fontWeight: "600"},
      {tag: t.heading2, fontSize: "1.35em", fontWeight: "600"},
      {tag: t.heading3, fontSize: "1.15em", fontWeight: "600"},
      {tag: [t.heading4, t.heading5, t.heading6], fontWeight: "600"},
      {tag: t.strong, fontWeight: "600"},
      {tag: t.emphasis, fontStyle: "italic"},
      {tag: t.strikethrough, textDecoration: "line-through"},
      {tag: t.link, color: "var(--admin-accent)"},
      {tag: t.url, color: "var(--admin-text-subtle)"},
      {tag: t.monospace, color: "var(--admin-accent)"},
      {tag: t.quote, color: "var(--admin-text-muted)", fontStyle: "italic"},
      {tag: t.list, color: "var(--admin-text-muted)"},
      // Markdown markers (#, *, `, fences, >): dimmed but visible.
      {tag: t.processingInstruction, color: "var(--admin-text-subtle)"},
      // Code tokens inside fenced blocks.
      {tag: t.keyword, color: "var(--ed-syntax-keyword)"},
      {tag: [t.string, t.special(t.string)], color: "var(--ed-syntax-string)"},
      {tag: t.comment, color: "var(--admin-text-subtle)", fontStyle: "italic"},
      {tag: t.number, color: "var(--ed-syntax-number)"},
      {tag: [t.function(t.variableName), t.definition(t.variableName)], color: "var(--ed-syntax-function)"},
      {tag: [t.typeName, t.className], color: "var(--ed-syntax-function)"},
      {tag: [t.bool, t.null, t.atom], color: "var(--ed-syntax-keyword)"},
    ])

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
      ".cm-monospace, .cm-line .ͼ1, .tok-monospace": {fontFamily: "ui-monospace, monospace"},
    })

    this.view = new EditorView({
      parent: this.el,
      state: EditorState.create({
        doc: initial,
        extensions: [
          history(),
          indentOnInput(),
          keymap.of([...defaultKeymap, ...historyKeymap, indentWithTab]),
          EditorView.lineWrapping,
          markdown({base: markdownLanguage, codeLanguages: languages}),
          syntaxHighlighting(highlight),
          theme,
          placeholder(PLACEHOLDER_TEXT),
          EditorView.updateListener.of((update) => {
            if (update.docChanged && field) syncMarkdown(field, update.state.doc.toString())
          }),
        ],
      }),
    })
  },

  destroyed() {
    this.view?.destroy()
  },
}
