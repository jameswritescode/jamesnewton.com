# Published Post Unsaved-Changes Indicator & Leave Guard — Design Spec

**Date:** 2026-06-16
**Status:** Approved (pending written review)
**Branch context:** `phoenix-migration`

## Overview

Draft posts autosave (debounced); published posts do **not** — they require a
manual Save. So a published post can have unsaved edits with no feedback, and
navigating away loses them silently. This adds, for published posts only: an
**"Unsaved changes…" indicator** when the form differs from the saved post, and a
**confirmation before leaving** (both in-app navigation and browser tab
close/refresh) while there are unsaved changes. Drafts are unaffected — autosave
already covers them.

All changes are in the post editor (`NewtonWeb.Admin.PostLive.Editor`) plus one
new JS hook; no schema or context changes.

## Decisions (locked during brainstorming)

- **Dirty = form differs from saved values** (not "any edit interaction"), so
  re-typing the original value or the CodeMirror mount-sync won't false-flag.
- **Leave guard covers both** in-app navigation (confirm dialog) **and** tab
  close/refresh (native `beforeunload`).
- **Published-only:** the indicator and guard apply only to published posts;
  drafts keep their autosave behavior with no leave guard.
- **Indicator shows only when dirty** for published posts (clean published posts
  show nothing); drafts keep their existing always-on "Saved / Unsaved changes…".

## Section 1 — Dirty tracking (server)

In `handle_event("validate", ...)`, the `published?` branch currently calls
`maybe_schedule_autosave(socket, params, not published?)`, which is a no-op for
published posts. Replace that no-op path with an explicit dirty check for
published posts:

- `dirty? =` any of these differ from the saved `@post`:
  - `params["title"] != post.title`
  - `params["slug"] != post.slug`
  - `(params["body_markdown"] || "") != (post.body_markdown || "")`
  - `(params["excerpt"] || "") != (post.excerpt || "")`
- Set `save_state` to `:unsaved` when `dirty?`, else `:saved`.

Explicit field comparison (rather than inspecting changeset changes) is chosen so
the result is predictable regardless of any markdown-derivation the changeset
performs. The four fields are exactly the editor's editable inputs; the form
submits all of them on every `validate`.

Drafts keep the existing `maybe_schedule_autosave` path unchanged. `published_at`
is edited through the separate publish drawer and is not part of dirty tracking.

On `apply_action(:edit)` / mount the post loads with `save_state: :saved` (already
the case), so a freshly opened published post is clean. A successful manual
**Save** sets `save_state: :saved` (already the case), clearing dirty.

## Section 2 — The indicator

The header already renders a save-state label gated to drafts:
`<span :if={Blog.publish_status(@published_at) == :draft}>{save_state_label(@save_state)}</span>`.

Broaden it so it also appears for a **published post when `@save_state` is
`:unsaved` or `:error`** (i.e. dirty), and stays hidden for a clean published
post. Drafts are unchanged (always shown). `save_state_label/1` already maps
`:unsaved → "Unsaved changes…"`, `:error → "Couldn't save"`, `_ → "Saved"`.

## Section 3 — Leave guard (`UnsavedGuard` JS hook)

A dedicated element in the editor template carries the live flag:

```heex
<div id="unsaved-guard" phx-hook="UnsavedGuard"
     data-unsaved={to_string(@save_state == :unsaved and not is_nil(@published_at))}>
</div>
```

`data-unsaved` is `"true"` only when **published and dirty** (drafts excluded).
The hook reads `this.el.dataset.unsaved` live at event time, so it always
reflects current state without needing `updated()`.

- **`beforeunload`** (tab close / refresh): a `window` listener that, when
  `data-unsaved === "true"`, calls `e.preventDefault()` and sets
  `e.returnValue = ""` to trigger the browser's native confirm. Otherwise it does
  nothing.
- **In-app navigation** (capture-phase `document` click listener): if the click
  target is inside a LiveView nav link (`a[data-phx-link]` — the "← Posts" link
  and the sidebar links) and `data-unsaved === "true"`, run
  `confirm("You have unsaved changes. Leave without saving?")`; if the user
  cancels, `e.preventDefault()` + `e.stopPropagation()` to block LiveView's
  navigation. If they accept (or it isn't dirty), navigation proceeds normally.

`destroyed()` removes both listeners, so the global click listener exists only
while the editor is mounted. Registered in `assets/js/admin.js` alongside the
other hooks; lives in `assets/js/hooks/unsaved_guard.js` with a vitest sibling.

**Not guarded:** the Delete button (a `phx-click` button with its own
`data-confirm`, and you're discarding the post anyway) and any server-driven
`push_navigate`/`push_patch` (those aren't link clicks and don't fire
`beforeunload`). For published posts the editor performs no internal patches, so
there's nothing to spuriously trip the guard.

## Error handling / edge cases

- **Save while dirty:** clears `save_state` to `:saved` → `data-unsaved` flips to
  `false` → leaving is unguarded immediately after.
- **Revert to original values:** typing an edit then changing it back to the
  saved value makes all four fields match → `:saved` → guard clears (correct;
  there's genuinely nothing to lose).
- **Draft posts:** `data-unsaved` is always `false` (the `not is_nil(published_at)`
  clause), so no guard and no published-style indicator — autosave owns drafts.
- **Move to draft / publish toggles** (publish drawer): these persist immediately
  via `set_published/2` and reset `save_state`; they don't interact with dirty
  tracking of the content fields.

## Testing approach

Behaviors, not structure; TDD.

- **LiveView (`post_editor_live_test`):**
  - Editing a published post's title via `render_change` sets the indicator to
    "Unsaved changes…" and the `#unsaved-guard` element's `data-unsaved` to
    `"true"`.
  - After a manual Save, the indicator is gone and `data-unsaved` is `"false"`.
  - Editing a **draft** never sets `data-unsaved` to `"true"`.
  - Typing a value equal to the saved one keeps `data-unsaved` `"false"`.
- **vitest (`unsaved_guard.test.js`):**
  - `beforeunload` is prevented (returnValue set) only when `data-unsaved="true"`.
  - A click on an `a[data-phx-link]` is blocked (preventDefault called) when dirty
    and confirm is declined; allowed when not dirty or confirm accepted.
  - `destroyed()` removes both listeners.
- **Playwright (manual verification pass):** edit a published post, click
  "← Posts" → a confirm dialog appears; dismissing it keeps you on the editor.

## Unit breakdown

- `NewtonWeb.Admin.PostLive.Editor` — published dirty check in `validate`; the
  broadened indicator `:if`; the `#unsaved-guard` element.
- `assets/js/hooks/unsaved_guard.js` (+ `.test.js`) — `beforeunload` + nav-link
  click-intercept, driven by `data-unsaved`.
- `assets/js/admin.js` — register `UnsavedGuard`.

## Out of scope

- Autosaving published posts (deliberately manual-Save).
- Guarding drafts (autosave covers them).
- A custom in-app "unsaved changes" modal (uses the native `confirm`, consistent
  with the existing `data-confirm` delete pattern).
- Field-level diff highlighting / "what changed" UI.
