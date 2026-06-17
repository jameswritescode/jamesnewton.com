# Admin Control Consistency — Design Spec

**Date:** 2026-06-16
**Status:** Approved (pending written review)
**Branch context:** `phoenix-migration`

## Overview

The admin's edit drawers and list tables each "do their own thing": the posts
list has a row Delete button (others don't), buttons lack a pointer cursor
(Tailwind v4 drops it), and the post/reading/photos edit drawers style and place
their Delete/Cancel/Save controls slightly differently. This pass makes them
consistent without restructuring: one global cursor rule, remove the lone table
delete, and extract shared drawer-control components that all three editors use.

## Decisions (locked during brainstorming)

- **Cursor:** one global admin CSS rule (root-cause fix), not per-button classes.
- **Tables:** remove the posts list row Delete; no list/table keeps a row delete.
- **Drawers:** align controls + extract a shared footer/delete component; do **not**
  restructure the post editor (it stays a full-page form + "Publish" drawer).
- **Label:** the destructive control reads **"Delete"** everywhere (the
  `data-confirm` carries the context, e.g. "permanently"/"and all its photos").

## Current state (for reference)

- **Posts list** (`PostLive.Index`): has a row Delete button (`handle_event("delete", %{"id" => id})`) — the only table with one. Styling lacks a pointer cursor.
- **Reading drawer** (`reading_live/index.ex` `reading_drawer/1`): footer
  `<div class="mt-2 flex items-center gap-2">` = `[Delete]·[spacer]·[Cancel link]·[Save submit]`. Delete: `phx-click="delete" phx-value-id={@entry.id}` confirm "Delete this entry?", cancel `~p"/admin/reading"`.
- **Gallery settings drawer** (`gallery_live/components.ex` `settings_drawer/1`):
  the **same** footer, near-verbatim. Delete: `phx-click="delete_gallery"` (no id) confirm "Delete this gallery and all its photos?", cancel `@cancel_path`.
- **Post editor** (`PostLive.Editor`): full-page form; a separate "Publish" drawer
  whose bottom has a standalone "Delete post" (`phx-click="delete"`, confirm
  "Delete this post permanently?"). Save is in the page header; "← Posts" is cancel.
- Tailwind v4 makes `<button>` `cursor: default`; `data-admin-theme` is set on the
  admin `<html>` only (not the public site).

## Section 1 — Global pointer cursor

Add to `assets/css/admin.css`:

```css
:where([data-admin-theme]) button:not(:disabled) {
  cursor: pointer;
}
```

- Scoped to admin (the public site never sets `data-admin-theme`).
- `:not(:disabled)` preserves the "Saving…" disabled button (its
  `disabled:cursor-not-allowed` still applies).
- `:where(...)` keeps specificity 0 so any `cursor-*` utility still wins.

The per-button `cursor-pointer` classes added earlier (hamburger, theme toggles)
become redundant but harmless; leave them.

## Section 2 — Remove the posts table delete

In `PostLive.Index`:
- Remove the row `<button … phx-click="delete" …>Delete</button>` from the post
  row markup.
- Remove the now-unused `handle_event("delete", %{"id" => id}, socket)` clause.

Deletion of a post happens in the editor's publish drawer (unchanged). Rows still
navigate to the editor via the existing stretched link. Remove the
`"deletes a post from the list"` test in `post_index_live_test.exs` (behavior
intentionally gone).

## Section 3 — Shared drawer controls

Add two function components to `NewtonWeb.Admin.Components` (alongside `drawer/1`,
`field/1`):

### `delete_button/1`
The single destructive button.

```elixir
attr :event, :string, required: true
attr :id, :any, default: nil
attr :confirm, :string, required: true
attr :label, :string, default: "Delete"
```

Renders a `type="button"` with `phx-click={@event}`, `phx-value-id={@id}` (omitted
when `nil` — HEEx drops nil attrs), `data-confirm={@confirm}`, and the shared
destructive styling (the current border + accent-text style, `text-[0.78rem]`).

### `drawer_footer/1`
The `[Delete · spacer · Cancel · Save]` action row reading + gallery duplicate.

```elixir
attr :cancel_path, :string, required: true
attr :deletable?, :boolean, default: false
attr :delete_event, :string, default: nil
attr :delete_id, :any, default: nil
attr :delete_confirm, :string, default: nil
attr :save_label, :string, default: "Save"
```

Renders `<div class="mt-2 flex items-center gap-2">` containing: an optional
`<.delete_button>` (when `@deletable?`, using `delete_event`/`delete_id`/
`delete_confirm`), a `flex-1` spacer, a Cancel `<.link patch={@cancel_path}>`, and
a `type="submit"` Save button. Must be placed inside the drawer's `<.form>` so the
submit works.

### Adopt the components
- **Reading** `reading_drawer/1`: replace the hand-rolled footer with
  `<.drawer_footer cancel_path={~p"/admin/reading"} deletable?={@entry.id != nil} delete_event="delete" delete_id={@entry.id} delete_confirm="Delete this entry?" />`.
- **Gallery** `settings_drawer/1`: replace its footer with
  `<.drawer_footer cancel_path={@cancel_path} deletable?={@editing?} delete_event="delete_gallery" delete_confirm="Delete this gallery and all its photos?" />`.
- **Post editor** publish drawer: replace the standalone "Delete post" button with
  `<.delete_button event="delete" confirm="Delete this post permanently?" />`
  (label defaults to "Delete"), keeping its current placement (bottom of the
  Publish drawer). It does not use `drawer_footer` (no Cancel/Save there).

`NewtonWeb.Admin.Components` is already aliased in reading, gallery, and editor
modules (they use `Components.drawer`/`Components.field`).

## Error handling / edge cases

- **`phx-value-id` nil** (gallery delete operates on the current group): rendered
  only when `delete_id` is non-nil, so no stray empty attribute.
- **Non-editing drawer** (new entry/gallery): `deletable?` false → no Delete
  button, just Cancel/Save (matches today).
- **Disabled buttons** (the editor "Saving…" state): unaffected — the cursor rule
  excludes `:disabled`, and that button isn't in these drawers.

## Testing approach

Behaviors, not structure.

- **Reading drawer:** opening an existing entry shows Delete; saving persists;
  Cancel returns to the list; deleting removes it. (Existing reading LiveView
  tests should pass against the shared footer; adjust selectors only if needed.)
- **Gallery settings drawer:** same — Delete present when editing, Save persists,
  Cancel closes. (Existing gallery tests should pass.)
- **Post editor:** the publish drawer still deletes the post and redirects.
  (Existing `delete removes the post and redirects` test should pass with the
  relabeled "Delete".)
- **Posts list:** the `"deletes a post from the list"` test is removed.
- **Component render:** `drawer_footer` renders Cancel + Save always and the
  Delete only when `deletable?`.

## Unit breakdown

- `assets/css/admin.css` — global admin button cursor rule.
- `NewtonWeb.Admin.Components` — `delete_button/1`, `drawer_footer/1`.
- `NewtonWeb.Admin.PostLive.Index` — remove row delete + handler (+ its test).
- `NewtonWeb.Admin.ReadingLive.Index` — adopt `drawer_footer`.
- `gallery_live/components.ex` (`settings_drawer/1`) — adopt `drawer_footer`.
- `NewtonWeb.Admin.PostLive.Editor` — publish drawer uses `delete_button`.

## Out of scope

- Restructuring the post editor into a drawer-as-form (the structural difference
  stays).
- Per-photo controls inside a gallery (the photo grid's own Delete) — that's a
  different context, not a list/table row delete.
- Public-site cursors/controls.
