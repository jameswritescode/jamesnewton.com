# Post Editor Image Upload (Drag-Drop + Paste) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a post author drag-drop or paste an image into the markdown editor; the file uploads to the media volume and a `![](/media/<key>)` image is inserted at the cursor with the caret parked inside `![]`.

**Architecture:** Reuse the gallery upload pipeline. `PostLive.Editor` gains an `auto_upload` `:inline_images` upload whose per-entry `progress` callback consumes the file via `Newton.Gallery.Storage.store/2` and `push_event`s the resulting `/media/<key>` URL back to the client. The existing `MarkdownEditor` CodeMirror hook gains drop/paste handlers that call `this.upload("inline_images", files)` and an `insert_image` handler that dispatches a CodeMirror change at the current selection. Images are untracked (no DB row).

**Tech Stack:** Phoenix LiveView uploads (`allow_upload`/`consume_uploaded_entry`/`push_event`), CodeMirror 6 (`EditorView.dispatch`), vitest (JS units), `Phoenix.LiveViewTest` (`file_input`/`render_upload`/`assert_push_event`), Playwright (e2e on PORT=4001).

**Reference spec:** `docs/superpowers/specs/2026-06-17-editor-image-upload-design.md`

**Session constraints:** Commit with `--no-gpg-sign`. Every commit message ends with the trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`. Any test server runs on `PORT=4001` — never touch port 4000.

---

### Task 1: JS pure helpers (`imageFiles`, `imageMarkdown`)

**Files:**
- Modify: `assets/js/hooks/markdown_editor.js` (export two new pure functions)
- Test: `assets/js/hooks/markdown_editor.test.js`

- [ ] **Step 1: Write the failing tests**

Add to `assets/js/hooks/markdown_editor.test.js`. Update the import on line 2 to also pull in the new helpers, and append the two describe blocks:

```js
import {syncMarkdown, imageFiles, imageMarkdown} from "./markdown_editor"
```

```js
describe("imageFiles", () => {
  const file = (type) => ({type, name: `f.${type.split("/")[1] || "bin"}`})

  it("keeps only entries whose type starts with image/", () => {
    const list = [file("image/png"), file("text/plain"), file("image/jpeg")]
    expect(imageFiles(list).map((f) => f.type)).toEqual(["image/png", "image/jpeg"])
  })

  it("returns an empty array when nothing is an image", () => {
    expect(imageFiles([file("application/pdf")])).toEqual([])
  })

  it("handles a FileList-like (array-like) argument", () => {
    const list = {0: file("image/png"), 1: file("text/plain"), length: 2}
    expect(imageFiles(list).map((f) => f.type)).toEqual(["image/png"])
  })
})

describe("imageMarkdown", () => {
  it("builds an empty-alt image and parks the caret just after ![", () => {
    expect(imageMarkdown("/media/abc.png")).toEqual({
      text: "![](/media/abc.png)",
      caretOffset: 2,
    })
  })
})
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd assets && pnpm vitest run js/hooks/markdown_editor.test.js`
Expected: FAIL — `imageFiles`/`imageMarkdown` are not exported (import is undefined).

- [ ] **Step 3: Implement the helpers**

In `assets/js/hooks/markdown_editor.js`, add below the existing `syncMarkdown` export (before `PLACEHOLDER_TEXT`):

```js
// Filter a FileList/array to the entries that are images.
export function imageFiles(list) {
  return Array.from(list || []).filter((f) => f.type && f.type.startsWith("image/"))
}

// Markdown for an inline image with an empty alt. caretOffset parks the cursor
// just after the `![` so the author can type the alt text immediately.
export function imageMarkdown(url) {
  return {text: `![](${url})`, caretOffset: 2}
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd assets && pnpm vitest run js/hooks/markdown_editor.test.js`
Expected: PASS (all `syncMarkdown` + `imageFiles` + `imageMarkdown` tests green).

- [ ] **Step 5: Commit**

```bash
git add assets/js/hooks/markdown_editor.js assets/js/hooks/markdown_editor.test.js
git commit --no-gpg-sign -m "$(cat <<'EOF'
Add imageFiles/imageMarkdown helpers for editor image upload

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Wire drop/paste/insert into the `MarkdownEditor` hook

**Files:**
- Modify: `assets/js/hooks/markdown_editor.js:121-145` (the `this.view = new EditorView(...)` mount tail, `destroyed/3`)

This is DOM + CodeMirror wiring driven by the dynamically-imported `EditorView`, so it is **not** unit-tested here — it is covered by the Playwright e2e in Task 4. Keep the pure helpers (Task 1) doing the testable logic.

- [ ] **Step 1: Add the drop/paste/insert wiring after the EditorView is created**

In `assets/js/hooks/markdown_editor.js`, immediately after the `this.view = new EditorView({...})` assignment closes (after line 140's `})`), inside `mounted()`, add:

```js
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
```

- [ ] **Step 2: Remove the listeners in `destroyed()`**

Replace the existing `destroyed()` (lines 143-145):

```js
  destroyed() {
    if (this.onDragOver) this.el.removeEventListener("dragover", this.onDragOver)
    if (this.onDrop) this.el.removeEventListener("drop", this.onDrop)
    if (this.onPaste) this.el.removeEventListener("paste", this.onPaste)
    this.view?.destroy()
  },
```

- [ ] **Step 3: Verify the existing JS suite still passes (no regressions)**

Run: `cd assets && pnpm vitest run`
Expected: PASS — the full vitest suite is green (the hook's new wiring isn't unit-tested, but nothing it touched should break existing tests).

- [ ] **Step 4: Commit**

```bash
git add assets/js/hooks/markdown_editor.js
git commit --no-gpg-sign -m "$(cat <<'EOF'
Wire drag-drop/paste image upload into the markdown editor hook

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Server-side `:inline_images` upload in `PostLive.Editor`

**Files:**
- Modify: `lib/newton_web/live/admin/post_live/editor.ex` (`mount/3` ~line 13-20; add `handle_inline_upload/3`; template ~line 359 add hidden `live_file_input`)
- Test: `test/newton_web/live/admin/post_editor_live_test.exs`

- [ ] **Step 1: Write the failing test**

Add to `test/newton_web/live/admin/post_editor_live_test.exs` (a 1×1 PNG is the smallest valid image; mirrors the gallery upload test's use of the test `media_root`):

```elixir
  @png_1x1 <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1,
             0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 10, 73, 68, 65, 84,
             120, 156, 99, 0, 1, 0, 0, 5, 0, 1, 13, 10, 45, 180, 0, 0, 0, 0, 73, 69,
             78, 68, 174, 66, 96, 130>>

  test "dropping an image uploads it and pushes insert_image with a /media URL", %{conn: conn} do
    {view, _post} = open_draft(conn)

    image =
      file_input(view, "#post-form", :inline_images, [
        %{name: "shot.png", content: @png_1x1, type: "image/png"}
      ])

    assert render_upload(image, "shot.png") =~ "post-form"
    assert_push_event(view, "insert_image", %{url: "/media/" <> _})
  end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `mix test test/newton_web/live/admin/post_editor_live_test.exs --only line:<line-of-new-test>` (or just the file)
Expected: FAIL — `:inline_images` upload is not allowed/registered (`file_input` raises or no `insert_image` event is pushed).

- [ ] **Step 3: Allow the upload in `mount/3`**

In `lib/newton_web/live/admin/post_live/editor.ex`, extend the `mount/3` pipeline (after `assign(:autosave_timer, nil)`):

```elixir
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:drawer_open, false)
     |> assign(:save_state, :saved)
     |> assign(:autosave_params, nil)
     |> assign(:autosave_timer, nil)
     |> allow_upload(:inline_images,
       accept: ~w(.jpg .jpeg .png .webp .gif),
       max_entries: 10,
       max_file_size: 10_000_000,
       auto_upload: true,
       progress: &handle_inline_upload/3
     )}
  end
```

- [ ] **Step 4: Add the `handle_inline_upload/3` callback**

Add a private function in the same module (place it near the other `handle_*` callbacks):

```elixir
  # Auto-upload progress callback: when an entry finishes, store it on the media
  # volume (untracked) and push the URL back to the editor hook to insert.
  defp handle_inline_upload(:inline_images, entry, socket) do
    if entry.done? do
      url =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          {:ok, key} = Newton.Gallery.Storage.store(path, entry.client_name)
          {:ok, Newton.Gallery.image_url(key)}
        end)

      {:noreply, push_event(socket, "insert_image", %{url: url, alt: ""})}
    else
      {:noreply, socket}
    end
  end
```

- [ ] **Step 5: Add the hidden `live_file_input` to the template**

In the same file, immediately after the `#body-editor` `</div>` (line 359, outside the `phx-update="ignore"` block, still inside `<.form id="post-form">`), add:

```heex
        <.live_file_input upload={@uploads.inline_images} class="sr-only" />
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `mix test test/newton_web/live/admin/post_editor_live_test.exs`
Expected: PASS — the upload stores a file and `insert_image` is pushed with a `/media/...` URL.

- [ ] **Step 7: Commit**

```bash
git add lib/newton_web/live/admin/post_live/editor.ex test/newton_web/live/admin/post_editor_live_test.exs
git commit --no-gpg-sign -m "$(cat <<'EOF'
Add inline image upload to the post editor

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Full verification + Playwright e2e

**Files:**
- Possibly add: an e2e spec under the existing Playwright test dir (match the repo's existing e2e layout/naming).

- [ ] **Step 1: Run the full precommit suite**

Run: `mix precommit`
Expected: PASS — formatting, compile (warnings-as-errors), full `mix test`, and the JS suite all green. Fix any findings (do not disable linters).

- [ ] **Step 2: Add a Playwright e2e that drops a PNG onto the editor**

Locate the existing Playwright config/specs (e.g. `assets/test/e2e` or repo `e2e/` — match what's already there). Add a spec that: logs in as `hello@jamesnewton.com` / `password1234`, opens a draft post editor, drops (or uses Playwright's `setInputFiles` on the hidden `input[type=file]` for `:inline_images`) a small PNG, and asserts the hidden `#post_body_markdown` textarea value gains `![](/media/`. If the inserted URL is fetched, it resolves 200.

- [ ] **Step 3: Run the e2e against a test server on PORT=4001**

Run the project's e2e command with the server bound to `PORT=4001` (never 4000). Example shape (use the repo's actual scripts):

```bash
PORT=4001 MIX_ENV=test mix phx.server &   # or the repo's e2e harness
# then run the playwright spec pointed at http://localhost:4001
```

Expected: the e2e passes — the dropped image appears as `![](/media/<key>)` in the editor body and the media URL resolves.

- [ ] **Step 4: Commit the e2e**

```bash
git add <e2e-spec-path>
git commit --no-gpg-sign -m "$(cat <<'EOF'
Add e2e for dropping an image into the post editor

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Self-review notes

- **Spec coverage:** drop + paste (Task 2), untracked `Storage.store` + `/media/<key>` (Task 3 callback), empty-alt insert with caret at offset 2 (Tasks 1+2), hidden `live_file_input` for registration/tests (Task 3), vitest for helpers (Task 1), LiveView `file_input`/`render_upload`/`assert_push_event` (Task 3), Playwright e2e (Task 4). Error cases (non-image filtered by `imageFiles`; oversize/wrong-type rejected by `allow_upload` constraints) are covered by the constraints + helper. `upload_errors` surfacing is a thin follow-up if the author needs the rejection message — noted, not blocking.
- **Type consistency:** `imageMarkdown` returns `{text, caretOffset}` and the hook destructures exactly those names; `insert_image` payload is `%{url, alt}` and the client reads `{url}`; upload name `:inline_images` / `"inline_images"` matches across server `allow_upload`, the hook's `this.upload`, and the test's `file_input`.
- **Out of scope (unchanged):** gallery-image picker, orphan cleanup, alt prompting, resizing, toolbar button.
