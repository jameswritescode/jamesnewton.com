# Media Audit in the Admin — Design

**Date:** 2026-07-10
**Status:** Approved direction; not yet implemented
**Builds on:** `docs/superpowers/specs/2026-07-09-post-inline-images-design.md`

## Problem

The volume/ledger audit lives only in `Newton.Blog.ImageBackfill.run/0`, run
by hand from a console. James won't regularly run a console audit, so drift
(orphaned volume files, posts referencing missing files) would go unnoticed.
The adopt half of that module is also scheduled for deletion after its one
production run — the audit must survive that removal.

## Decisions (made during brainstorming)

1. **Actionable, not view-only:** the admin can delete orphaned files
   (guarded server-side), consistent with the post-images manual-cleanup
   posture. Missing-file entries are view-only — the fix is editing the post.
2. **Dedicated page + dashboard signal:** a "Media" admin section at
   `/admin/media` carries the lists and actions; the dashboard shows a
   compact drift notice (linking there) only when something is found.
3. **Compute live, persist nothing:** the audit (two queries + one `File.ls`
   + post-body scan) runs on page/dashboard mount. No tables, no background
   jobs. Caching is deliberately out of scope at this scale.

## Design

### 1. Module split

`Newton.Blog.ImageAudit` (new; read-only engine):

- `run/0` → `%{missing: [{slug, key}], strays: [key]}` — the existing audit
  logic minus adoption. Volume listing excludes dotfiles (`.keep`). A stray
  is a volume file owned by neither `photos` (image_key/thumb_key) nor
  `post_images` AND referenced by no post body — the same predicate as
  `stray?/1`, so every listed stray is actually deletable.
- `stray?/1` → that predicate for one key; `delete_stray/1`'s guard.
- `delete_stray/1` → re-checks `stray?/1`, then `Storage.delete/1`;
  `{:error, :not_stray}` otherwise. Mirrors `delete_image/1`'s guard posture.
- Owns the `/media/<key>` extraction regex; exposes it to the backfill.
- `@spec` on all public functions (domain layer).

`Newton.Blog.ImageBackfill` (slimmed): adoption only, reusing ImageAudit's
extraction and ownership sets. It and `lib/mix/tasks/newton.post_images.backfill.ex`
are the complete file list for the post-backfill removal deploy; the admin
page must not depend on either.

### 2. Media page

`NewtonWeb.Admin.MediaLive` at `live "/media", MediaLive, :index` in the
existing `:admin` live_session (authenticated, admin root layout — same
placement as the other admin LiveViews). Nav: add
`%{key: :media, label: "Media", path: "/admin/media"}` to the sections list
in `lib/newton_web/components/admin/layouts.ex`.

On mount: run the audit, assign both lists.

- **Orphaned files:** each stray renders a thumbnail (`Gallery.image_url(key)`),
  the key, the file's size on disk, and a delete button (`data-confirm`).
  The `delete_stray` event calls `ImageAudit.delete_stray/1` and re-runs the
  audit. DOM ids: `#media-strays`, `#media-stray-<key-sans-extension>` (keys
  are UUIDs — DOM-safe once the dot is dropped).
- **Missing files:** each `{slug, key}` renders the key and a link to the
  referencing post's editor (`/admin/posts/<id>/edit`; resolve id via slug).
  DOM id: `#media-missing`.
- Empty state per section ("No orphaned files", "No missing files") when clean.

### 3. Dashboard signal

`DashboardLive` runs `ImageAudit.run/0` on mount. When either list is
non-empty, render a notice (id `#media-drift`) — e.g. "3 orphaned files ·
1 missing image" — linking to `/admin/media`. Render nothing when clean.

### 4. Error handling

- `delete_stray/1` refusal (`{:error, :not_stray}`) leaves the page consistent
  via the post-action re-audit; no flash needed (the row disappears from the
  list only when genuinely deleted).
- A missing media_root directory yields empty audit results (existing
  `File.ls` error handling carries over).

## Testing (behaviors)

- **ImageAudit:** `run/0` reports missing + strays and ignores dotfiles;
  `stray?/1` false for photo-owned, ledgered, and body-referenced keys;
  `delete_stray/1` removes a true stray's file and refuses (file survives)
  for owned/referenced keys.
- **Backfill after split:** existing adoption tests keep passing against the
  slimmed module.
- **MediaLive:** delete flow end-to-end (click delete → file gone from disk →
  row gone); missing entry links to the right post editor; empty states render
  when clean.
- **DashboardLive:** drift notice renders with counts when drift exists and
  is absent when clean.

## Out of scope

- Caching / background sweeps / persisted audit results.
- Bulk delete, stray previews beyond a thumbnail, download.
- Any change to the adopt flow beyond extracting shared pieces.
