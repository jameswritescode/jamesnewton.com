# Post Edit Conflict Handling — Design

**Date:** 2026-07-28
**Status:** Approved for planning

## Problem

The post editor loses data when the same post is open in two browsers. Observed
failure: a laptop that reopened a day-old editor tab silently overwrote edits
saved from another computer in the meantime.

Two root causes, confirmed in code:

1. **LiveView form recovery re-submits stale content.** `#post-form` has
   `phx-change="validate"` and no `phx-auto-recover` opt-out, so on socket
   reconnect LiveView re-sends the client's current input values — including a
   hidden `post[body_markdown]` textarea holding day-old text — as a `validate`
   event. For drafts, `validate` funnels into `maybe_schedule_autosave`, which
   persists the full stale params. No user action required.
2. **Last-writer-wins saves.** `Blog.update_post/2` is a plain full-document
   `Repo.update` with no version check, so any two sessions editing the same
   post silently clobber each other regardless of trigger.

## Goals

- A stale session can never silently overwrite newer content.
- Genuine concurrent edits surface as a visible conflict the author resolves.
- Reconnects (laptop wake, flaky network) neither lose local typing when it is
  safe to keep it, nor adopt it when it is stale.

Out of scope: real-time collaborative merging (CRDT/OT), Presence-based
"open elsewhere" hints, multi-user concerns. Single author, multiple devices.

## Design

### 1. Optimistic locking on posts

- Migration: `add :lock_version, :integer, default: 1, null: false` on `posts`.
- Schema: `field :lock_version, :integer, default: 1`.
- `Post.changeset/2` adds `Ecto.Changeset.optimistic_lock(:lock_version)`, so
  every update compiles to `UPDATE ... WHERE id = ? AND lock_version = ?` and
  raises `Ecto.StaleEntryError` when another session already bumped the version.
- `Blog.update_post/2` rescues `Ecto.StaleEntryError` and returns
  `{:error, :stale}`. Callers receive a value, never an exception.
- `rerender_post/1` keeps its behavior; its version bump correctly conflicts
  any editor session that was open across a re-render.
- Creates (`%Post{id: nil}`) cannot conflict and are untouched.

### 2. Editor conflict state

`save_state` gains a fourth value: `:saved | :unsaved | :error | :conflict`.

When autosave (`persist_autosave/3`) or manual save receives `{:error, :stale}`:

- Cancel the autosave timer. Keep the pending params but never auto-retry them
  — a retry would conflict again.
- Enter `save_state: :conflict`. The top bar replaces the save indicator with a
  banner: **"This post was changed in another window"** and two actions:
  - **Load latest** (`phx-click="conflict_load_latest"`): refetch the post,
    rebuild the editor by bumping `editor_key` (the existing post-switch
    mechanism), reset the form from the fresh post, return to `:saved`. This
    window's version is discarded.
  - **Keep mine** (`phx-click="conflict_keep_mine"`): refetch the current
    post (for its `lock_version`), re-save this window's content over it,
    return to `:saved`. This window wins, deliberately and visibly.
- `set_published/2` (publish now / unpublish / set date) handles
  `{:error, :stale}` the same way instead of crash-matching `{:ok, post}`.

### 3. Version-checked reconnect handshake

Replace default form recovery with `phx-auto-recover="recover"` on
`#post-form`, plus a hidden `post[lock_version]` input rendered from the form.

`handle_event("recover", %{"post" => params}, socket)` compares the client's
`lock_version` param against the freshly-mounted post:

- **Match** (no other session wrote since this client loaded): adopt the params
  through the same path as `validate` — local typing survives the reconnect,
  autosave resumes. The editor DOM must end up showing the recovered content:
  since remount rebuilt CodeMirror from DB state, the handler re-syncs the
  editor by bumping `editor_key` after assigning the form from the client
  params — the rebuilt textarea then carries the recovered body into the hook.
- **Stale** (another session wrote meanwhile): do not adopt the params. Keep
  the fresh DB content in the editor and flash
  "Updated in another window — showing the latest version." No write occurs.

This strictly improves both axes over the status quo: no stale overwrite, no
lost typing on benign reconnects.

## Data flow summary

```
typing → validate → autosave params → :autosave → Blog.update_post
                                                    ├─ {:ok, post}      → :saved, version advances
                                                    └─ {:error, :stale} → :conflict banner
reconnect → recover(params incl. lock_version)
              ├─ version match → adopt params (as validate) → autosave resumes
              └─ stale         → keep DB content, flash, no write
```

## Testing

Context level (`test/newton/blog_test.exs`):

- `update_post/2` returns `{:error, :stale}` when the underlying row's
  `lock_version` has advanced; the row keeps the newer content.

LiveView level (`test/newton_web/live/admin/post_editor_live_test.exs`):

- Two mounted sessions on one post: A saves, then B's save/autosave path →
  B shows the conflict banner (assert on element id) and the DB retains A's
  content.
- **Load latest** replaces B's form/editor state with A's version and clears
  the conflict.
- **Keep mine** persists B's content (DB now B's body) and clears the conflict.
- `recover` with matching version: client params are adopted and subsequently
  persisted by autosave.
- `recover` with stale version: DB content is kept, nothing is written.
- Publish/unpublish from a stale session surfaces the conflict instead of
  crashing the LiveView.

Tests assert behavior (DB outcomes, element presence by id, state transitions),
not markup details, per project convention.
