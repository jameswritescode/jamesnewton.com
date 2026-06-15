# Post Admin Improvements — Design Spec

**Date:** 2026-06-15
**Status:** Approved (pending written review)
**Branch context:** `phoenix-migration`

## Overview

Four related improvements to the post admin, prompted by real use after the Fly
deploy: an **editable publish date** (to backdate posts during the blog
migration), a **cleaner draft model** (drafts are created only once they have
content, eliminating phantom draft counts), a **robust excerpt** (render-and-strip
instead of fragile regex), and **list filters + sort** (All / Drafts / Published,
newest first). All live in the post-admin surface — `Newton.Blog`,
`Newton.Markdown`, `NewtonWeb.Admin.PostLive.{Index, Editor}` — so they ship as
one spec.

## Decisions (locked during brainstorming)

1. **Publish date:** date-only control, stored at **noon UTC** for the chosen
   date. **Future dates allowed** → `:scheduled` (already hidden by the public
   `published_at <= now` filter).
2. **Draft model:** "New post" creates **no row**; the row is created on the
   **first autosave that has content**. Delete the `discard_empty_untitled_drafts`
   cleanup machinery.
3. **Excerpt:** render the full markdown via MDEx, take the first paragraph's
   text, truncate. Replaces the `strip_markdown` regex.
4. **List:** filter `:all | :drafts | :published`, **URL-backed**, sorted by
   `coalesce(published_at, inserted_at) desc` (newest first).

## Section 1 — Editable publish date

The publish drawer (`PostLive.Editor`) gains date control over `published_at`
(schema unchanged — still `:utc_datetime`).

- **Storage:** a date-only value is stored as `that date @ 12:00:00 UTC`. Noon UTC
  keeps the displayed calendar date stable across timezones (display is
  date-only via `Calendar.strftime`).
- **Publish now (draft → published):** the existing "Publish now" button sets
  `published_at = DateTime.utc_now()` (truncated to seconds) and persists
  immediately — an instant, unambiguous publish (not noon, so it can't briefly
  read as `:scheduled`).
- **Editing the date (published/scheduled):** the drawer shows a **date input**
  bound to `published_at`'s date. Changing it re-saves `published_at` as the
  picked date at noon UTC via `Blog.update_post/2`. A **past** date backdates; a
  **future** date schedules (`:scheduled`, hidden publicly until it passes).
- **Move to draft:** clears `published_at` (existing behavior).
- The status badge (`Blog.publish_status/1`) already renders draft / scheduled /
  published from the value.

**New editor event:** `set_publish_date` (parses `%{"date" => "YYYY-MM-DD"}`,
builds the noon-UTC `DateTime`, calls `set_published/2`). Reuses the existing
`set_published/2` persistence path. An empty/invalid date is ignored.

## Section 2 — Draft model: create on first content

Today "New post" eagerly inserts an "Untitled post" row, which counts as a draft
everywhere until `discard_empty_untitled_drafts/0` runs on the list mount — so
e.g. New post → Dashboard shows a phantom "1 draft." The fix: **don't create
until there's content.**

- **Routing:** re-add `live "/posts/new", PostLive.Editor, :new` (alongside the
  existing `/posts/:id/edit`).
- **`PostLive.Index` "New post" button:** navigates to `/admin/posts/new`
  (no creation). (Removes the `new_post` create-and-navigate handler.)
- **Editor `apply_action(:new)`:** sets up an **in-memory** `%Post{}` form. No DB
  write, no `push_patch` (avoids the historical double-create-on-mount: creation
  no longer happens in mount).
- **Autosave / save on an unpersisted post (`%Post{id: nil}`):**
  - If **content is present** (title or body non-empty), **create** the post,
    then `push_patch` to `/admin/posts/:id/edit` so subsequent saves update it.
    At creation, if the title is blank (body-only draft), backfill
    `title: "Untitled post"` and `slug: Blog.next_untitled_slug()` so the
    changeset validates; once a real title is typed the slug auto-derives.
  - If **no content**, do nothing (no row).
- **Delete** `Blog.discard_empty_untitled_drafts/0` and its call in
  `PostLive.Index.mount`. Phantom drafts can't exist, so dashboard/list counts
  are always correct with no cleanup. (Keep `next_untitled_slug/0` — still used
  for body-only creation.)
- Creation living in the **autosave/save event** (fires once on a real edit) is
  what makes this safe — the prior failure was creating during mount, which ran
  twice (disconnected + connected) and surfaced the redirect as a `live_redirect`.

**Content predicate:** `title` present (non-blank) **or** `body_markdown`
non-empty. (The autosave form params carry both.)

## Section 3 — Excerpt: render-then-strip

`Newton.Markdown.excerpt/1` currently regex-strips a subset of markdown and so
leaves reference-style links intact (`[Code School][1]` and `[1]/[2]` markers
survive). Replace with a parse-based approach:

- Render/parse the **full** markdown via MDEx (the full doc, so reference-link
  **definitions** in later paragraphs resolve), obtain the **first paragraph's
  plain text** (tags stripped, HTML entities decoded), then truncate at a word
  boundary to `@excerpt_max_chars`.
- Implementation note (finalized in the plan): use MDEx to get plain text of the
  first paragraph — either walking the parsed document AST to the first
  `Paragraph` node and collecting its text, or rendering to HTML and extracting
  the first `<p>` text with entity decoding. Either is robust against all
  markdown constructs; the AST walk avoids HTML regex and is preferred.
- Remove the old `strip_markdown/1` regex helper. `first_paragraph/1` /
  `truncate/2` may be reused or folded in as needed.

## Section 4 — Posts list: filters + sort

- **`Blog.list_posts/1`** takes a filter and applies a unified sort:
  - `order_by: [desc: coalesce(published_at, inserted_at)]` for every filter
    (published by publish date, drafts by created — one newest-first timeline).
  - `:all` → no status filter.
  - `:drafts` → `where is_nil(published_at)`.
  - `:published` → `where not is_nil(published_at)` (includes scheduled, which
    have a future date).
  - Default arg `:all` keeps existing callers working.
- **`PostLive.Index`:** the filter is a **URL param** (`/admin/posts?filter=drafts`).
  `handle_params` reads `filter` (default `:all`, unknown values fall back to
  `:all`) and re-streams `list_posts(filter)`. A segmented control (All / Drafts /
  Published) renders as `<.link patch=…>` tabs, the active one highlighted.

## Error handling

- **Invalid/empty publish date** input → ignored (no change); the field only
  ever sets a valid `Date`.
- **Autosave create with no content** → no-op (the whole point).
- **Autosave create with body but blank title** → title/slug backfilled so the
  insert succeeds; a changeset error (e.g. slug collision) leaves `save_state`
  `:error` as today, nothing persisted broken.
- **Unknown `?filter=` value** → treated as `:all`.

## Testing approach

Behaviors, not structure; TDD.

- **Publish date:** setting a past date backdates `published_at` (status
  `:published`); a future date → `:scheduled`; "Publish now" → `:published` with
  `published_at` ≈ now; the stored time is noon UTC for an edited date.
- **Draft model:** visiting `/admin/posts/new` creates **no** row; an autosave
  with content creates exactly one row and patches to its edit URL; an autosave
  with no content creates nothing; navigating New post → Dashboard shows **no**
  phantom draft in `count_drafts`.
- **Excerpt:** a first paragraph containing reference-style links yields excerpt
  text with **no brackets or `[n]` markers** (the reported case); inline links,
  emphasis, and code still strip to their text.
- **List filters:** `list_posts(:drafts)` returns only unpublished,
  `list_posts(:published)` only published, both newest-first by the coalesced
  date; the index renders the active filter from `?filter=` and switching
  re-streams.

## Unit breakdown

- `Newton.Blog` — `list_posts/1` (filter + coalesced sort); remove
  `discard_empty_untitled_drafts/0`; keep `next_untitled_slug/0`.
- `Newton.Markdown` — rewrite `excerpt/1` (render-then-strip); remove
  `strip_markdown/1`.
- `NewtonWeb.Admin.PostLive.Index` — URL-backed filter + segmented control;
  "New post" navigates to `/admin/posts/new`; drop the eager-create handler and
  the cleanup call.
- `NewtonWeb.Admin.PostLive.Editor` — `apply_action(:new)` (in-memory form);
  autosave/save create-or-update branch; `set_publish_date` event + the date
  input in the publish drawer.
- `lib/newton_web/router.ex` — re-add `/posts/new`.

## Out of scope

- Datetime (time-of-day) precision / intra-day ordering — date-only by decision.
- A background scheduler — scheduled posts appear passively once the date passes.
- Changes to Reading/Photos lists (filters here are posts-only for now).
