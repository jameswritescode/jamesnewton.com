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
- **Auto-discard untouched drafts** — a draft auto-created this session and never
  edited is deleted when the editor LiveView terminates.
- **Debounced trigger** — auto-save fires ~1.5s after the last edit, and
  immediately on blur.
- **Drafts only** — auto-save is gated on draft state; published posts are
  manual-Save only.

## Architecture

All changes are within the existing post editor LiveView
(`NewtonWeb.Admin.PostLive.Editor`) and the `Newton.Blog` context. No JS, no
schema change. The editor's form already fires `phx-change="validate"` on every
edit (the CodeMirror body syncs to a hidden field that triggers it); auto-save is
a **server-side debounce** layered on top of that existing event.

### New post creates a draft (`apply_action(:new)`)

Instead of rendering an empty form, `:new`:

1. Creates a draft: `Blog.create_post(%{title: "Untitled post", slug: <unique>,
   body_markdown: ""})`.
2. `push_patch`es to `/admin/posts/#{post.id}/edit`, carrying an
   `:autocreated?` flag (same LiveView process, so the assign survives the
   patch).

`apply_action(:edit)` preserves an existing `:autocreated?` (via `assign_new`,
defaulting false) so directly opening an existing post's edit URL is never
flagged.

**Unique slug:** slugs are `unique_constraint`-protected, so the default cannot
always be `untitled-post`. `Newton.Blog` gains a helper that returns the first
free slug in the series `untitled-post`, `untitled-post-2`, `untitled-post-3`, …
Because slugs auto-follow the title while unpublished (existing lock logic in the
editor), the slug self-corrects the moment a real title is typed.

### Auto-save (debounced)

State assigns on the editor: `:autosave_params` (latest validated params),
`:autosave_timer` (timer ref or nil), `:save_state` (`:saved | :unsaved |
:saving | :error`), `:edited?` (bool), `:autocreated?` (bool).

- **`handle_event("validate", ...)`** keeps its current behavior (slug/excerpt
  autofill, rebuild form). Then, when the post is a **draft**:
  - sets `:edited?` true when params differ from the created defaults,
  - stores params in `:autosave_params`, sets `:save_state` to `:unsaved`,
  - cancels any existing `:autosave_timer` and schedules a new one:
    `Process.send_after(self(), :autosave, 1500)`.
- **`handle_info(:autosave, socket)`** — if still a draft and there are pending
  params: set `:save_state` to `:saving`, `Blog.update_post(socket.assigns.post,
  params)`.
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

### Discard untouched draft on leave (`terminate/2`)

`terminate(_reason, socket)`: if `@autocreated? and not @edited?` and the post is
still a draft, `Blog.delete_post(socket.assigns.post)`. Leaving the editor —
sidebar nav, the "← Posts" link, or closing the tab — ends the LiveView process
and runs `terminate/2` (navigating to a different LiveView, even within
`live_session :admin`, terminates the old one). The only thing ever auto-deleted
is a draft created this session and never edited, so there is no content to lose;
even a spurious terminate (brief disconnect) can only remove an empty Untitled
draft.

### Save-state indicator

A quiet status next to the Save button, driven by `:save_state`:

- `:saved` → "Saved" (muted)
- `:unsaved` → "Unsaved changes…" (shown while the debounce timer is pending)
- `:saving` → "Saving…"
- `:error` → "Couldn't save" (accent)

Hidden entirely when the post is published (auto-save off).

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
- **New post creates a draft + redirects:** visiting `/admin/posts/new` creates
  an "Untitled post" draft and patches to its `/edit` URL; the post exists.
- **Unique default slug:** creating two new posts yields distinct slugs
  (`untitled-post`, `untitled-post-2`).
- **Untouched draft discarded on leave:** create via `/new`, then leave without
  editing → the draft is deleted; edit first → it survives.
- **Indicator reflects state:** after an auto-save the view shows "Saved"; after
  an edit it shows the unsaved state.

## Unit breakdown

- `Newton.Blog.next_untitled_slug/0` (or similar) — first free `untitled-post[-n]`
  slug.
- `NewtonWeb.Admin.PostLive.Editor` — `apply_action(:new)` creates+redirects;
  `validate` schedules debounce + tracks `:edited?`/`:save_state`;
  `handle_info(:autosave, …)` persists; `autosave_now` blur flush;
  `terminate/2` discards untouched drafts; the save-state indicator in the
  template.

## Future (explicitly deferred)

- Revision history.
- Auto-save for published posts behind an explicit "update live" affordance.
- A periodic "saved N seconds ago" relative timestamp.
