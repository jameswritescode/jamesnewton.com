# Post Editor Image Upload (Drag-Drop + Paste) — Design Spec

**Date:** 2026-06-17
**Status:** Approved (pending written review)
**Branch context:** `phoenix-migration`

## Overview

Let an author add images to a post by **dragging a file onto the editor** or
**pasting an image** (e.g. a screenshot). The file uploads to the media volume and
a `![](/media/<key>)` markdown image is inserted at the cursor. Images are
**untracked** — just stored files referenced by URL, no DB record. Referencing
existing **gallery** images is a deferred follow-up, not in this spec.

## Decisions (locked during brainstorming)

- **Input:** drag-and-drop **and** paste-from-clipboard. (No toolbar button.)
- **Storage:** untracked — `Storage.store/2` → `/media/<key>`; no DB row, no
  orphan cleanup yet.
- **Insert format:** `![](/media/<key>)` with an **empty alt**, cursor parked
  inside the `![]` so the author types alt immediately.
- **Scope:** new-file upload only; the gallery-image picker is a later follow-up.

## Current building blocks (reference)

- `Newton.Gallery.Storage.store(source_path, original_filename)` → `{:ok, key}`
  (UUID + ext, written to the media volume). `Gallery.image_url(key)` →
  `/media/<key>`.
- The gallery already does LiveView uploads: `allow_upload`, `phx-drop-target`,
  `live_file_input`, `consume_uploaded_entries` (see `GalleryLive.Show`).
- The editor's `MarkdownEditor` hook (`assets/js/hooks/markdown_editor.js`) owns a
  CodeMirror `EditorView` at `this.view` on `#markdown-editor`, and syncs the doc
  to the hidden `#post_body_markdown` textarea via `syncMarkdown` (dispatches an
  `input` event on `docChanged`, which already triggers `validate`/autosave).

## Section 1 — Server (`PostLive.Editor`)

- **`mount/3`** adds:
  ```elixir
  |> allow_upload(:inline_images,
       accept: ~w(.jpg .jpeg .png .webp .gif),
       max_entries: 10,
       max_file_size: 10_000_000,
       auto_upload: true,
       progress: &handle_inline_upload/3)
  ```
- **`handle_inline_upload(:inline_images, entry, socket)`** — fires per entry as it
  uploads (auto_upload). When `entry.done?`, consume and push the URL back:
  ```elixir
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
  Multiple dropped/pasted files each fire this as they finish, so each pushes its
  own `insert_image`.
- **Template:** a visually-hidden `<.live_file_input upload={@uploads.inline_images} class="sr-only" />` somewhere in the editor (outside the `phx-update="ignore"` body-editor block). It is not the primary path — drop/paste use the hook's `this.upload` — but it registers the upload and gives tests a `file_input` target. The image render in the published post is unchanged (markdown → `<img>`).

## Section 2 — Client (`MarkdownEditor` hook)

Extend the existing hook (it already holds `this.view`):

- **Drop:** on `this.el`, a `dragover` handler `preventDefault`s (to allow drop)
  and a `drop` handler `preventDefault`s, collects image files from
  `e.dataTransfer.files`, and if any, calls `this.upload("inline_images", files)`.
- **Paste:** on the editor, a `paste` handler collects image files from
  `e.clipboardData` (items/files with `type` starting `image/`); if any,
  `preventDefault` and `this.upload("inline_images", files)` (so CodeMirror
  doesn't also paste a blob URL or filename).
- **Insert:** `this.handleEvent("insert_image", ({url, alt}) => …)` inserts the
  image markdown at the cursor:
  - Build `![${alt}](${url})`.
  - `this.view.dispatch({changes: {from, to, insert}, selection: {anchor: from + 2}})`
    where `from`/`to` is the current selection — the `+ 2` parks the cursor inside
    `![|]`. The existing `updateListener` syncs the textarea (→ autosave).
- **Pure helpers (for unit tests):**
  - `imageFiles(list)` — filter a `FileList`/array to entries whose `type`
    starts with `image/`.
  - `imageMarkdown(url)` — return `{text, caretOffset}` =
    `{ "![](" + url + ")", 2 }` (empty alt; caret parked just after `![`).
- **Cleanup:** `destroyed()` removes the drop/paste listeners alongside the
  existing `this.view?.destroy()`.

## Section 3 — Storage (untracked)

Inline images are stored on the volume by `Storage.store/2` and referenced by
`/media/<key>` in the post body. No DB row. Removing an `![]` or deleting a post
can orphan the file — acceptable for a single-admin blog; a sweep is a future
follow-up (out of scope).

## Error handling / edge cases

- **Non-image drop/paste:** `imageFiles` yields nothing → no upload; the editor
  behaves normally (text paste still works).
- **Too-large / wrong-type:** rejected by `allow_upload` constraints; surface via
  `upload_errors(@uploads.inline_images)` in the admin flash so the author sees
  why nothing inserted.
- **Multiple files:** each consumed entry pushes its own `insert_image`; they
  insert sequentially at the advancing cursor.
- **Autosave/dirty:** an inserted image is a body change → flows through the
  existing draft autosave and the published "unsaved changes" guard unchanged.
- **New (unsaved) post:** the editor works on an in-memory `%Post{}`; an image
  upload + insert is body content, so the first autosave persists the post as
  usual.

## Testing approach

- **vitest (`markdown_editor.test.js`, new or extended):** `imageFiles` filters to
  `image/*`; `imageMarkdown(url)` returns `"![](url)"` with the caret offset at 2. (The CodeMirror `dispatch` + DOM drop/paste wiring is covered by the e2e
  pass, since CodeMirror is dynamically imported out of the test bundle.)
- **LiveView (`post_editor_live_test.exs`):** using `file_input(view,
  "#…", :inline_images, [%{name, content, type}])` + `render_upload`, assert the
  file is stored (a `/media/...` URL) and an `insert_image` push-event is sent
  (`assert_push_event "insert_image", %{url: "/media/" <> _}`). Mirrors the
  gallery upload test's use of the test `media_root`.
- **Playwright e2e:** drop a small PNG onto `#markdown-editor` → the body shows
  `![](/media/…)` and the inserted URL resolves (200). Paste path verified
  similarly if feasible.

## Unit breakdown

- `lib/newton_web/live/admin/post_live/editor.ex` — `allow_upload(:inline_images)`,
  `handle_inline_upload/3`, hidden `live_file_input`.
- `assets/js/hooks/markdown_editor.js` — drop/paste → `this.upload`;
  `insert_image` handler; `imageFiles/1` + `imageMarkdown/2` helpers.
- (Reused, unchanged) `Newton.Gallery.Storage`, `Gallery.image_url/1`.

## Out of scope (future follow-ups)

- Referencing existing **gallery** images via a picker.
- Orphaned-file **cleanup** (deleting unreferenced inline images).
- Alt-text prompting, image resizing/optimization, captions, or a toolbar button.
