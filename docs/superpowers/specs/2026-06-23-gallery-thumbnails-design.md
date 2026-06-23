# Photo Gallery Thumbnails — Design Spec

**Date:** 2026-06-23
**Status:** Approved (pending written review)
**Branch context:** `phoenix-migration`

## Overview

The public photo gallery (`/photos`) currently serves each photo's **full-resolution original** as the grid image — CSS-scaled and `loading="lazy"`, but still the multi-MB file. On slow connections the grid is sluggish because every tile downloads a full export. This feature generates a small **WebP thumbnail** per photo for the grid; clicking a photo still opens the **full original** in the lightbox.

## Decisions (locked)

- **Lightbox = the literal full-resolution original** (not a web-optimized "large"). Two tiers only: thumbnail (grid) + original (click).
- **Thumbnails are WebP** (~25–35% smaller than equivalent JPEG; universally supported).
- **Pre-generated on upload, stored as static files** (chosen over on-demand): gallery thumbnails are requested on every grid view, so paying the resize cost once at upload and serving a plain static file is the right trade. Served at `/media/<thumb_key>` like originals.
- **Size:** the thumbnail's **longest edge** (the longer of width/height) is capped at **1000px**, downscale-only (never upscaling; aspect ratio preserved); WebP **quality 75**. Both are named, tunable constants. e.g. a `4000×3000` original → `1000×750`; a `3000×4000` → `750×1000`. The grid's actual display widths peak around ~432px (single-column on small screens), so 1000px stays crisp at 2× across the 1-to-3-column masonry while landing well under the multi-MB originals (and the true original is one click away).
- **Engine:** libvips via the `image` library already in the app (added for the OG cards).

## Section 1 — Data model

- **Migration:** add `thumb_key :string` (nullable) to `photos`.
- **`Photo` schema:** `field :thumb_key, :string`. Set programmatically by the upload/backfill paths, **not** user-cast — same handling as `image_key`.
- Nullable is the **fallback signal**: a photo with `thumb_key: nil` (not yet backfilled, or a generation failure) serves its original in the grid, so nothing ever breaks.

## Section 2 — Thumbnail generation (`Newton.Gallery.Thumbnail`)

A small, single-purpose module:

- `generate(source_path) :: {:ok, String.t()} | {:error, term()}` — returns a temp `.webp` file path.
- Uses libvips' `thumbnail` operation (shrink-on-load, so it's fast even on large JPEGs), **downscale only** so the longest edge ≤ `@max_edge` (1000; never upscales), and encodes WebP at `@quality` (75) via `Image.write`.
- Pure image transform; persistence is `Storage`'s job. The exact `image`-lib call names (`Image.thumbnail/2`, `Image.write/3`) are confirmed during implementation — the library is already proven in this app.

## Section 3 — Storage

Reuse `Newton.Gallery.Storage.store/2`: `Storage.store(thumb_temp_path, "thumb.webp")` returns a `.webp` key (Storage derives the key + extension from the filename). Flat keys under `media_root`, identical scheme to originals. No new storage code beyond what `store/2`/`delete/1` already provide.

## Section 4 — Upload flow (`GalleryLive.Show.save_upload`)

Within `consume_uploaded_entries`, after `Storage.store(path, entry.client_name)` for the original:

- `Thumbnail.generate(path)` from the **same** temp file → `Storage.store(thumb_path, "thumb.webp")` → `thumb_key`.
- Return `{key, thumb_key, w, h}`; pass `thumb_key` into `Gallery.add_photo/2`.
- **Failure handling:** if `Thumbnail.generate/1` errors, log and proceed with `thumb_key: nil`. The upload still succeeds; that tile falls back to its original.

## Section 5 — Public grid + lightbox

- **Helper:** `Gallery.thumb_url(photo)` = `image_url(photo.thumb_key || photo.image_key)` (delegated into `photo_html`, alongside the existing `image_url`).
- **Grid template** (`photo_html/index.html.heex`): `<img src={thumb_url(photo)} …>` keeps `width={photo.width} height={photo.height}` (original dimensions — same aspect ratio, so layout reservation is unchanged). The enclosing `<button>` gains `data-full={image_url(photo.image_key)}`.
- **Lightbox** (`photos.js`): `show(btn)` sets `full.src = btn.dataset.full || img.src` (and keeps `full.alt = img.alt`). Clicking loads the true original; the `|| img.src` keeps it working for any tile without a `data-full`.

## Section 6 — Backfilling existing photos

`Gallery.backfill_thumbnails/0`:

- Query photos where `thumb_key` is `nil`.
- For each: read the original from `media_root/<image_key>`, `Thumbnail.generate/1` → `Storage.store/2` → update `thumb_key`.
- **Idempotent** (skips photos that already have a `thumb_key`), logs and continues past per-photo failures, returns a count summary.

**Run automatically as part of the release**, then remove. The release already runs `Newton.Release.migrate` via Fly's `release_command` on every deploy. We add a one-time `Newton.Release.migrate/0` follow-on (inside a `with_repo(Repo, …)` so the repo is started, since `eval` doesn't boot the full app) that calls `Gallery.backfill_thumbnails/0` after migrations. This backfills existing photos on the **first** deploy with no console.

After that first deploy succeeds and the gallery is confirmed backfilled, **remove the backfill call from the release step** (new uploads already generate their own thumbnail, so nothing left would need it). `Gallery.backfill_thumbnails/0` stays in the codebase as a public, manually-runnable function. (The implementation plan's final task is this removal.)

## Error handling / edge cases

- **Generation failure** (upload or backfill): the photo keeps `thumb_key: nil`; the grid falls back to the original; no crash.
- **Corrupt / non-image original:** `generate/1` returns `{:error, _}`; logged; fallback.
- **Re-running backfill:** safe — only touches `thumb_key: nil` rows.
- **Deleting a photo:** both delete paths must also remove the thumbnail file — `delete_photo/1` (`Storage.delete(photo.image_key)`) and `delete_group/1` (which deletes each photo's `image_key`) — so no orphaned thumbs are left on disk.

## Testing

- **`Thumbnail.generate/1`:** returns a valid WebP, downscaled within the cap (assert format + dimensions via `Image`), and smaller than the source.
- **`backfill_thumbnails/0`:** sets keys for `nil`-thumb photos; is idempotent; tolerates a missing/broken source (counts it as a failure, doesn't crash).
- **`Gallery.add_photo/2`:** persists `thumb_key`.
- **Upload (LiveView):** an uploaded photo ends up with a non-nil `thumb_key`.
- **`photos.test.js`:** clicking a tile sets the overlay `src` to the tile's `data-full` (the original), not the grid thumbnail.

## Out of scope

- On-demand resizing, multiple thumbnail tiers / `srcset`, AVIF.
- Re-encoding or optimizing the **originals** themselves.
- A separate "download original" affordance (the lightbox already shows the original).

## Unit breakdown (files)

- `priv/repo/migrations/*_add_thumb_key_to_photos.exs` — the column.
- `lib/newton/gallery/photo.ex` — `thumb_key` field.
- `lib/newton/gallery/thumbnail.ex` — **new**, the resize.
- `lib/newton/gallery.ex` — `add_photo/2` (`thumb_key`), `thumb_url/1`, `backfill_thumbnails/0`, and both delete paths (`delete_photo/1`, `delete_group/1`) also removing the thumb.
- `lib/newton/release.ex` — `migrate/0` also calls `Gallery.backfill_thumbnails/0` after migrations (temporary; removed in the plan's final task after the first deploy).
- `lib/newton_web/live/admin/gallery_live/show.ex` — upload flow.
- `lib/newton_web/controllers/photo_html.ex` + `photo_html/index.html.heex` — grid `src` + `data-full`.
- `assets/js/photos.js` (+ `assets/js/photos.test.js`) — lightbox uses `data-full`.
