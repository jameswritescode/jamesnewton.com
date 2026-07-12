# Post Inline Images — Tracking & Lifecycle Design

**Date:** 2026-07-09
**Status:** Approved direction; not yet implemented

## Problem

Images dropped/pasted into the markdown editor are stored on the media volume
(`Storage.store/2`, UUID key) and referenced only as `![](/media/<key>)` text
inside the post body. Nothing else records they exist:

- Orphans accumulate silently (deleted image lines, abandoned uploads).
- Deleting a post leaves its images on the volume forever.
- The admin has no way to see or manage a post's images.
- The volume holds writes no record owns (gallery photos are tracked via the
  `photos` schema; inline post images are the only untracked media).

## Decisions (made during brainstorming)

1. **Ownership: upload-origin.** An image belongs to the post whose editor
   uploaded it (`belongs_to :post`). Cross-post image reuse is out of scope —
   acceptable for a single-author blog, revisit if needed.
2. **Cleanup: manual, with visibility.** Nothing is auto-deleted while a post
   lives. The admin surfaces attached-but-unreferenced images; deletion is a
   human decision. Deleting a post deletes its images.
3. **Usage is derived, never stored.** Whether a post still *shows* an image
   is computed live from its markdown (`String.contains?(post.body_markdown, key)`).
   The markdown stays the single source of truth for usage; the table is only
   a ledger of what exists and who uploaded it. No flag to drift on autosave.

## Design

### 1. Data model

Table `post_images`:

| column | type | notes |
|---|---|---|
| `post_id` | FK → `posts` | `on_delete: :delete_all`, indexed |
| `key` | string | unique; the storage filename (`<uuid>.<ext>`) |
| `original_filename` | string | for humans in the admin |
| timestamps | | |

Schema `Newton.Blog.PostImage`; `Post` gains `has_many :images`.

### 2. Context API (`Newton.Blog`, `@spec` on all — domain layer)

- `attach_image(post, key, original_filename)` → `{:ok, %PostImage{}} | {:error, changeset}`
- `list_images(post)` → `[%PostImage{}]`
- `image_referenced?(post, image)` → boolean; live body scan for the key
- `delete_image(image)` → deletes file via `Storage.delete/1` then the row;
  **returns an error and does nothing if the owning post still references the
  key** (server-side guard against breaking a live post)
- `delete_post/1` deletes owned files (`Storage.delete/1` per image) before
  deleting the post; rows cascade at the DB level

`Newton.Gallery.Storage` remains the shared file owner for both galleries and
post images; no move/rename.

### 3. Upload flow (editor LiveView)

`handle_inline_upload/3` becomes:

1. Ensure a post exists: on `/admin/posts/new` the post is `%Post{id: nil}`
   until the first contentful autosave, and uploads complete before their
   markdown lands. Create the draft through the same path autosave uses
   (`Blog.create_post(backfill_new(...))`) and `push_patch` to the edit URL,
   mirroring `persist_autosave/3`.
2. `Storage.store(path, client_name)` → key (unchanged).
3. `Blog.attach_image(post, key, entry.client_name)`.
4. `push_event(socket, "insert_image", %{url: Gallery.image_url(key)})` (unchanged).

Failure posture: if draft creation or `attach_image` fails, the upload still
stores the file and inserts its markdown — degraded to today's untracked
behavior rather than blocking the author mid-write.

### 4. Admin visibility & manual cleanup

An "Images" section on the editor page listing each owned image:

- thumbnail (the image itself, small), `original_filename`
- a "not referenced" badge when `image_referenced?/2` is false
- a delete button on unreferenced images only; the server re-checks
  referenced-ness in the event handler (the guard in `delete_image/1` is the
  real gate — the UI is a convenience)

No global orphans page: the per-post strip plus the audit task below cover
visibility at this scale.

### 5. Backfill & audit (mix task)

One idempotent task (e.g. `mix newton.post_images.backfill`):

- **Adopt:** scan every post body for `/media/<key>` URLs; for each key that
  exists on the volume and has no `post_images` row, insert one
  (`original_filename` unknown → store the key).
- **Report, never delete:** keys referenced by posts but missing from the
  volume; volume files owned by neither `photos` nor `post_images`.

Runnable in production via the release console; rerunnable any time as an
audit of volume/ledger drift.

## Testing (behaviors)

- **Context:** attach/list; `delete_image` removes the file and row for an
  unreferenced image and refuses for a referenced one; `delete_post` removes
  owned files from a tmp media root; `image_referenced?` against real bodies.
- **Editor LiveView:** drive an upload through `Phoenix.LiveViewTest`'s
  upload support → ledger row exists and `insert_image` fires; the new-post
  path creates a draft on first upload; the Images section delete flow
  deletes an unreferenced image and refuses a referenced one.
- **Backfill:** fixture posts + tmp files → rows adopted, idempotent on
  second run, anomalies reported.

## Out of scope

- Cross-post image reuse / reference counting (revisit if wanted).
- Automatic grace-period sweeps.
- Byte sizes, dimensions, or other metadata on the ledger.
- A global orphans admin page.
