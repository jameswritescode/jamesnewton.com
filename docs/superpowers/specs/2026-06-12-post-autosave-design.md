# Post Auto-Save — Design Spec

**Date:** 2026-06-12
**Status:** Approved (pending written review)
**Branch context:** `phoenix-migration`

## Overview

Add auto-save to the admin post editor so draft edits persist on their own. A new
post becomes a real draft the moment you click **New post**, the editor only ever
edits a persisted post, and changes save automatically (debounced) while the post
is a draft. An untouched, auto-created draft is discarded when you leave, so the
list never collects empties. Published posts are never auto-saved — they require
an explicit Save, so in-progress edits never silently go live.

### Goals

- Drafts persist without the author remembering to Save.
- "New post" creates a draft immediately (single, uniform editing path).
- No junk: an untouched "Untitled post" draft is removed on leave.
- Published posts stay manual-Save only.
- A quiet indicator communicates save state.

### Non-goals

- Auto-saving published posts.
- Revision history / multiple drafts per post.
- Offline/local-storage drafting.
- Conflict resolution across simultaneous editors (single admin).

## Decisions (locked during brainstorming)

- **New post creates a draft immediately** — title "Untitled post", a unique
  slug, opens its `/edit` URL. The editor always edits a real post (`id`
  present); the previous "unsaved new post" branch is removed.
- **Auto-discard untouched drafts** — an "Untitled post" with an empty body and
  no publish date is junk and gets cleaned up so the list never accumulates them.
- **Debounced trigger** — auto-save fires ~1.5s after the last edit, and
  immediately on blur.
- **Drafts only** — auto-save is gated on draft state; published posts are
  manual-Save only.

> **Revisions during implementation** (see the matching plan for detail):
> 1. **Creation moved to the "New post" button event, not the editor mount.**
>    Creating in `apply_action(:new)` runs on both the disconnected and connected
>    render (double-create) and surfaces the mount-time redirect as a
>    `live_redirect`. So `PostLive.Index`'s "New post" button creates the draft
>    (one event) via `Blog.create_draft/0` and `push_navigate`s to `/edit`.
> 2. **Discard moved from `terminate/2` to a list-mount cleanup.** Within a
>    `live_session` the LiveView process is **reused** across navigations, so
>    `terminate/2` is *not* reliably called when leaving the editor — untouched
>    drafts accumulated. Instead `PostLive.Index.mount` calls
>    `Blog.discard_empty_untitled_drafts/0`, which runs every time you land on the
>    list. The `?new`/`:autocreated?`/`:edited?` machinery is removed.
> 3. **Bodyless drafts need a changeset coercion, not just relaxed validation.**
>    The `body_markdown` column is `NOT NULL` and Ecto `cast` turns `""` into
>    `nil`; `Post.changeset` coerces a missing body to `""`.

## Architecture

Changes are within the post editor and list LiveViews
(`NewtonWeb.Admin.PostLive.Editor` / `.Index`) and the `Newton.Blog` context. No
JS, no schema change. The editor's form already fires `phx-change="validate"` on every
edit (the CodeMirror body syncs to a hidden field that triggers it); auto-save is
a **server-side debounce** layered on top of that existing event.

### New post creates a draft (the "New post" button)

`PostLive.Index`'s "New post" is a `phx-click="new_post"` button. The handler
calls `Blog.create_draft/0` (title "Untitled post", unique slug, empty body) and
`push_navigate`s to `/admin/posts/#{post.id}/edit`. The editor then only ever
edits a persisted post; the previous "unsaved new post" branch is gone.
Creating from the button (a single event) avoids the double-create that an
`apply_action(:new)` would cause on the disconnected + connected mount.

**Unique slug:** slugs are `unique_constraint`-protected, so the default cannot
always be `untitled-post`. `Newton.Blog` gains a helper that returns the first
free slug in the series `untitled-post`, `untitled-post-2`, `untitled-post-3`, …
Because slugs auto-follow the title while unpublished (existing lock logic in the
editor), the slug self-corrects the moment a real title is typed.

### Auto-save (debounced)

State assigns on the editor: `:autosave_params` (latest validated params),
`:autosave_timer` (timer ref or nil), `:save_state` (`:saved | :unsaved |
:error`).

- **`handle_event("validate", ...)`** keeps its current behavior (slug/excerpt
  autofill, rebuild form). Then, when the post is a **draft**:
  - stores params in `:autosave_params`, sets `:save_state` to `:unsaved`,
  - cancels any existing `:autosave_timer` and schedules a new one:
    `Process.send_after(self(), :autosave, 1500)`.
- **`handle_info(:autosave, socket)`** — if still a draft and there are pending
  params: `Blog.update_post(socket.assigns.post, params)`.
  - success → assign the updated post as the new baseline (`:post`), clear
    `:autosave_params`, set `:save_state` to `:saved`. **Does not rebuild the
    form or `push_patch`**, so the cursor and the CodeMirror editor are never
    disrupted mid-typing.
  - changeset error → set `:save_state` to `:error`, persist nothing; inline
    field errors already explain why. Recovers to `:saved` on the next valid
    save.
- **Blur flush** — `phx-blur="autosave_now"` on the title/slug/excerpt inputs and
  the editor container cancels the debounce timer and performs the save
  immediately, so leaving a field flushes pending changes.

Manual **Save** is unchanged and also resolves `:save_state` to `:saved`. A
pending timer after a manual save is a harmless no-op (params already saved).

### Discard untouched drafts (list-mount cleanup)

`PostLive.Index.mount` calls `Blog.discard_empty_untitled_drafts/0` before
streaming the list. That deletes every post whose title is the `@untitled_title`
constant, whose body is `""`, and which has no `published_at`. Because the list's
`mount` runs every time you navigate back to it, abandoned new drafts never
accumulate. The only thing ever auto-deleted is an untouched, empty "Untitled
post" draft — there is no content to lose. Typing a title or any body makes it no
longer match, so real work is kept.

(This replaces the original `terminate/2` design: within a `live_session` the
LiveView process is reused across navigations, so `terminate/2` did not fire
reliably when leaving the editor.)

### Save-state indicator

A quiet status next to the Save button, driven by `:save_state`:

- `:saved` → "Saved" (muted)
- `:unsaved` → "Unsaved changes…" (shown while the debounce timer is pending)
- `:error` → "Couldn't save" (accent)

There is no `:saving` state — the auto-save DB write is synchronous within
`handle_info`, so there is no async window to show it. Hidden entirely when the
post is published (auto-save off).

## Error handling

- **Validation failure during auto-save:** skip the write, set `:error`; nothing
  persists broken. Recovers on the next valid save.
- **Rapid typing:** the single timer is rescheduled per keystroke, so only one
  save fires ~1.5s after typing stops (no write-per-keystroke).
- **Publishing mid-edit:** publish persists immediately (existing behavior); the
  post leaves draft state, the pending timer is irrelevant, the indicator hides.
- **Process crash/disconnect:** at most the last <1.5s of keystrokes are lost
  (inherent to debounced auto-save); on reconnect the editor re-mounts from the
  last saved state.

## Testing approach

Behaviors, not structure; TDD (failing test first).

- **Auto-save persists a draft:** mount the editor on a draft, run a `validate`
  with changed params, drive the `:autosave` `handle_info` → the DB post is
  updated with no manual Save.
- **Published posts don't auto-save:** `validate` on a published post → no write;
  the post is unchanged.
- **New post creates a draft + opens the editor:** clicking "New post" creates an
  "Untitled post" draft and `live_redirect`s to its `/edit` URL; the post exists.
- **Unique default slug:** creating two new posts yields distinct slugs
  (`untitled-post`, `untitled-post-2`).
- **Untouched drafts discarded on list load:** an empty "Untitled post" draft is
  gone after `/admin/posts` mounts; a titled or non-empty draft survives.
- **Indicator reflects state:** after an auto-save the view shows "Saved"; after
  an edit it shows the unsaved state.

## Unit breakdown

- `Newton.Blog` — `@untitled_title` constant; `create_draft/0`;
  `next_untitled_slug/0` (first free `untitled-post[-n]` slug);
  `discard_empty_untitled_drafts/0`; `Post.changeset` body coercion.
- `NewtonWeb.Admin.PostLive.Index` — `new_post` event creates a draft + navigates;
  `mount` runs the cleanup.
- `NewtonWeb.Admin.PostLive.Editor` — `validate` schedules the debounce;
  `handle_info(:autosave, …)` persists; `autosave_now` blur flush; the save-state
  indicator in the template.

## Future (explicitly deferred)

- Revision history.
- Auto-save for published posts behind an explicit "update live" affordance.
- A periodic "saved N seconds ago" relative timestamp.
