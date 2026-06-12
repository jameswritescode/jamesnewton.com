# Admin Photos Section — Design Spec

**Date:** 2026-06-11
**Status:** Approved (pending written review)
**Branch context:** `phoenix-migration`

## Overview

The third and final admin section: managing **photo galleries** and the photos
within them. It completes the admin alongside Posts and Reading, reusing the
established admin patterns — the token-driven theme, the shared
`NewtonWeb.Admin.Components` drawer/field, URL-backed drawers, LiveView streams,
and the stretched-link list rows. Two levels: a **galleries list** and an
**in-gallery photo manager** with drag-drop upload and drag-to-reorder.

The public `/photos` page (read-only grid + lightbox) is unchanged; this section
only adds the admin surface that feeds it.

### Goals

- Create, edit, and delete photo galleries (title, slug, caption, taken-on).
- Upload photos into a gallery via drag-drop, with progress and validation.
- Reorder photos by dragging; edit alt text; delete photos.
- Flag photos missing alt text so accessibility gaps stay visible.
- Keep the public photos page and its image serving untouched.

### Non-goals (out of scope for this spec)

- Server-side image processing, resizing, or responsive derivatives.
- Replacing a photo's image in place (delete + re-upload instead).
- Cropping/rotating/EXIF editing.
- Reordering galleries (they order by `taken_on`).

## Decisions (locked during brainstorming)

- **Dimensions captured client-side at upload.** A JS hook reads each file's
  `naturalWidth`/`naturalHeight` in the browser and sends them with the upload;
  no native image library (no libvips/`image` dep). The public `<img>` uses these
  to avoid layout shift.
- **Drag-and-drop reordering** of the photo grid (custom sortable JS hook, no
  external library per the asset rules).
- **Photo drawer = alt text + delete.** No in-place image replacement.
- **`max_file_size` 50MB** to accommodate full-quality JPEG exports (A7IV →
  Lightroom Classic → site); `accept` jpg/jpeg/png/webp; `max_entries` 20.

## Architecture

### Surfaces and boundaries

Two LiveViews plus a storage seam, under the existing `live_session :admin`:

| Unit | Responsibility |
| --- | --- |
| `NewtonWeb.Admin.GalleryLive.Index` | Galleries list + URL-backed create/edit/delete drawer (gallery settings) |
| `NewtonWeb.Admin.GalleryLive.Show` | In-gallery manager: upload, thumbnail grid, drag-reorder, per-photo drawer |
| `Newton.Gallery.Storage` | The only module that touches the filesystem: store/delete image files under `media_root` |

This mirrors the two-level structure (galleries → photos) and reuses the Reading
list/drawer shape for `Index`. `Show` holds the only genuinely new behavior
(uploads + reordering). Isolating filesystem I/O in `Storage` keeps the context
testable and the upload logic in one place.

### Routes

Added inside the existing `live_session :admin` block (`scope "/admin",
NewtonWeb.Admin`):

```elixir
live "/photos", GalleryLive.Index, :index
live "/photos/new", GalleryLive.Index, :new
live "/photos/:id/edit", GalleryLive.Index, :edit
live "/photos/:id", GalleryLive.Show, :show
live "/photos/:id/photo/:photo_id", GalleryLive.Show, :photo
```

`:photos` is added to the admin layout's `@built` list so the sidebar nav item
becomes an active link instead of an inert placeholder.

### Storage and serving (already in place)

- DB stores an `image_key`; `Newton.Gallery.image_url/1` maps it to `/media/<key>`.
- `Plug.Static` already serves `/media` from `media_root` (`priv/media` in dev,
  `/data/images` on the Fly volume in prod). **No serving changes** — uploaded
  photos render on the public page immediately.

## Schema

No migration. One schema change to `Newton.Gallery.Photo`:

- `field :alt, :string, default: ""` and **remove `validate_required(:alt)`**.
  Uploads succeed with blank alt; the "needs alt" badge nags. `image_key` and
  `position` remain required. The DB column stays `NOT NULL`; the `""` default
  satisfies it.

Existing schema (unchanged otherwise):

- `photo_groups`: `slug`, `title`, `caption`, `taken_on`, `has_many :photos`
  (`preload_order: [asc: :position]`). `changeset` requires `slug`+`title`,
  `unique_constraint(:slug)`.
- `photos`: `image_key`, `alt`, `position`, `width`, `height`,
  `belongs_to :photo_group` (FK `on_delete: :delete_all`).

## Context: `Newton.Gallery` additions

Fills the admin CRUD gap (same shape as `Blog`/`Reading`):

- **Groups:** `get_group!/1`, `get_group_by_slug!/1`, `update_group/2`,
  `delete_group/1`, `change_group/2`.
- **Photos:** `get_photo!/1`, `update_photo/2`, `delete_photo/1`,
  `change_photo/2`.
- **Reorder:** `reorder_photos/2` — takes a gallery (or group_id) and an ordered
  list of photo IDs; updates each member photo's `position` in a single
  transaction. Ignores IDs that don't belong to the gallery (a malformed client
  payload can't corrupt another gallery).
- **File-aware deletes:** `delete_photo/1` removes the file via `Storage.delete/1`
  then the row; `delete_group/1` removes all member files then the row (FK
  cascade removes the photo rows).
- **Next position** helper for appending uploads (max existing position + 1).

## `Newton.Gallery.Storage`

The only filesystem touchpoint.

- `store(source_path, original_filename) :: {:ok, image_key} | {:error, reason}`
  — copies the temp upload into `media_root`, generating a collision-proof key
  (`"#{Ecto.UUID.generate()}#{ext}"`, preserving the original extension).
- `delete(image_key) :: :ok` — removes the file; idempotent (a missing file is
  not an error, so partial-failure deletes can't wedge).
- Reads `media_root` from config, so it works in dev and prod. Tests point it at
  a temp dir.

## Sections

### Galleries list (`GalleryLive.Index`)

- A **stream of galleries**, newest by `taken_on`. Each row: a small **cover
  thumbnail** (first photo by position, or a neutral placeholder when the gallery
  is empty), title, photo count, and `taken_on`. The whole row is a stretched
  link to `GalleryLive.Show` (`/admin/photos/:id`); a **Delete** control sits
  above the stretch (`relative z-10`) with a `data-confirm` warning that it
  removes all photos.
- **Create/edit drawer:** shared `Components.drawer` + `Components.field`,
  URL-backed (`/new`, `/:id/edit`). Fields: **title**, **slug**, **caption**,
  **taken-on**. Editing offers **Delete**. Closes on button/Escape/click-away
  with the slide animation.
- **Slug auto-derive:** slug follows the title until the author edits the slug
  field (the same lock pattern as the post editor). This logic is **extracted
  into a small shared helper** (`Newton.Slug` or an admin form helper) and used
  by both the post editor and gallery settings rather than duplicated.
- Header: "Photos" + "Add gallery". Empty state: "No galleries yet."

### In-gallery manager (`GalleryLive.Show`)

Route `/admin/photos/:id` (+ `/photo/:photo_id` for the per-photo drawer).

- **Header:** gallery title, "← Photos" back link, a "Settings" link that patches
  to the Index edit drawer for this gallery, and the photo count.
- **Upload:** `allow_upload(:photos, accept: ~w(.jpg .jpeg .png .webp),
  max_entries: 20, max_file_size: 50_000_000)`.
  - A drag-drop **dropzone** (`phx-drop-target`) plus click-to-pick. Per-entry
    **progress bars** and inline validation errors (too big / wrong type); an
    entry can be canceled while others proceed.
  - A JS hook reads each file's `naturalWidth`/`naturalHeight` client-side and
    pushes them to the server keyed by the upload entry ref, so dimensions are
    known at consume time.
  - On submit, `consume_uploaded_entries` hands each temp file to
    `Storage.store/2`, then `Gallery.add_photo/2` with the returned `image_key`,
    captured `width`/`height`, blank `alt`, and the next `position`.
- **Thumbnail grid:** a stream of photos. Each tile shows the image, a **"needs
  alt" badge** when `alt == ""`, and opens the **photo drawer** on click. The grid
  is wrapped in a **drag-to-reorder** sortable JS hook; on drop it pushes the new
  ID order to a `"reorder"` handler → `Gallery.reorder_photos/2`.
- **Photo drawer:** shared `Components.drawer`, URL-backed — edit **alt** (live
  validate/save) and **Delete** (removes row + file).
- Empty state: "No photos yet — drag images here to start."

Two small, isolated JS hooks (own hooks in `assets/js/`, no external libs):
an **upload dimension-reader** and a **sortable grid**.

## Error handling

- **Upload rejects** (wrong type / over 50MB): surfaced inline per-entry via
  `upload_errors/2`; the entry can be canceled and the rest still submit.
- **Storage failure:** `Storage.store/2` returns `{:error, reason}`; that entry is
  skipped with a flash error rather than persisting a row pointing at a missing
  file — the DB never references a file that isn't there.
- **Dimensions missing** (hook didn't report / JS disabled): the photo still
  saves with `width`/`height` nil; the public `<img>` omits those attributes and
  renders fine. Not fatal.
- **Orphaned files:** `delete_photo/1` removes file then row; `delete_group/1`
  removes all member files then the row. `Storage.delete/1` is idempotent, so a
  partial failure can't wedge a delete.
- **Reorder with stale/foreign IDs:** `reorder_photos/2` only updates positions
  for IDs belonging to that gallery, in a transaction — a malformed payload can't
  corrupt another gallery.
- **Validation:** slug uniqueness and required title surface inline in the drawer
  via `to_form/2` + `<.input>`.

## Testing approach

Behaviors, not structure. TDD (failing test first).

- **Context (`Newton.GalleryTest`):** group CRUD; `reorder_photos/2` persists the
  new order and ignores foreign IDs; `delete_photo`/`delete_group` remove rows
  **and** files (assert the file is gone from a temp `media_root`).
- **Storage (`Newton.Gallery.StorageTest`):** `store/2` writes a file and returns
  a usable key; `delete/1` removes it and is idempotent. Uses a tmp dir.
- **`GalleryLive.Index`:** list renders galleries; drawer create/edit
  round-trips; delete removes the gallery; slug auto-derives until edited.
- **`GalleryLive.Show`:** upload happy-path (`file_input` + `render_upload`)
  creates a photo with captured dimensions; "needs alt" badge shows for blank alt
  and clears once set; photo drawer edits alt and deletes; reorder event persists
  order.
- **JS (Vitest):** the dimension-reader maps a file to width/height; the sortable
  hook emits the expected ID order on drop.

## Unit breakdown

- `Newton.Gallery.Photo` — schema tweak (blank-alt default).
- `Newton.Gallery` — admin CRUD + `reorder_photos/2` + file-aware deletes.
- `Newton.Gallery.Storage` — filesystem store/delete.
- `NewtonWeb.Admin.GalleryLive.Index` — galleries list + settings drawer.
- `NewtonWeb.Admin.GalleryLive.Show` — upload, grid, reorder, photo drawer.
- Shared slug auto-derive helper (extracted from the post editor).
- `assets/js/hooks/` — image dimension-reader hook + sortable grid hook.
- `NewtonWeb.Admin.Layouts` — `@built` adds `:photos`; reuse `Components.drawer`/
  `field`.

## Future (explicitly deferred)

- Server-side image processing / responsive derivatives (would reintroduce the
  `image`/libvips dependency).
- In-place image replacement in the photo drawer.
- Gallery reordering / manual ordering.
