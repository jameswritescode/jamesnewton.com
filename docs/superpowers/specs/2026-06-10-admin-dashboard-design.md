# Admin Dashboard — Design Spec

**Date:** 2026-06-10
**Status:** Approved (pending written review)
**Branch context:** `phoenix-migration`

## Overview

A back-office admin for jamesnewton.com that lets the site owner manage the
three content types — **Posts**, **Reading** entries, and **Photo galleries** —
through a focused, modern interface. The admin is a separate surface from the
public site with its own design language: a **Linear-inspired, token-driven
theme** (`assets/css/admin.css`) built on stepped shades of a warm-neutral base,
high contrast, hairline borders, and a **warm terracotta/peach accent** that ties
back to the public palette without copying its layout. It supports **light and
dark themes** — following the OS preference by default, with a sidebar toggle
that overrides and remembers the choice (`data-admin-theme` on `<html>`, set
before first paint to avoid a flash). The admin is built **end-to-end in
LiveView** (the public site remains classic controllers / dead views).

### Goals

- Manage posts (markdown), reading entries, and photo galleries from one place.
- A writing experience that mirrors the published page's **typography** while
  staying visually neutral in color.
- Keep the public site untouched in look and rendering; the admin is additive.
- Single-owner authentication; no public sign-up.

### Non-goals (out of scope for this spec)

- Multi-user / roles / permissions beyond a single admin.
- Public-facing comments, analytics dashboards, or media CDN integration.
- Bulk import/export tooling.
- Rich résumé editing (the résumé remains template-driven for now).

## Architecture

### Surfaces and boundaries

| Surface | Tech | Layout |
| --- | --- | --- |
| Public site | Classic controllers + HEEx dead views (unchanged) | `Layouts.app` (warm palette), public `root` layout |
| Admin | LiveView | `Admin.Layouts` shell + dedicated `admin_root` layout (no ripple canvas/public chrome), token-driven theme in `admin.css` |

- **Routing:** all admin lives under a single `scope "/admin", NewtonWeb.Admin`
  with a dedicated `live_session` gated by an authentication `on_mount`. The
  default `:browser` pipeline plus a `:require_authenticated_user` plug protect
  the routes.
- **The admin is LiveView end-to-end** so we get live validation, drag-drop
  uploads, slide-over drawers, and the live markdown editor without page reloads.

### Authentication

Generated with **`phx.gen.auth`** (scope-based), then trimmed:

- **Email + password** login only. The magic-link flow the generator scaffolds
  is **removed** (routes, LiveViews, and tokens for link login deleted).
- **Public registration removed** — there is no sign-up route. The only way to
  create the admin account is from a console.
- **Admin creation from a production console:** a release helper
  `Newton.Release.create_admin(email, password)` (alongside the existing
  release migration pattern), callable on Fly via
  `bin/newton eval 'Newton.Release.create_admin("hello@jamesnewton.com", "…")'`
  or a remote IEx one-liner against the `Newton.Accounts` context.
- `phx.gen.auth` adds an **`Accounts` context** and a `users` table. Reading,
  Gallery, and Blog schemas are unchanged.

The scope gives us `current_scope`, which the project's existing `CLAUDE.md`
guidelines already assume, and which the public site reuses (below).

### Public-site change: draft visibility

The only change to the public site. Today `Blog.get_published_post!/1` filters to
`published_at <= now`. We add a **session-aware** path:

- A **signed-in admin** visiting `/posts/:slug` sees the post **regardless of
  publish status** (this *is* the "preview as published" mechanism — the draft
  rendered by the real `PostController` / template / MDEx / `site.css`).
- An **anonymous** visitor sees only published posts; an unpublished slug returns
  **404**.
- Drafts never appear in the public `/posts` index; they are reached from the
  admin or by direct URL.

Implementation: `PostController.show/2` branches on `current_scope` (admin present
or not) and calls either an admin fetch (any status) or the existing published
fetch. The public index query is unchanged.

### Build / assets

- **Milkdown** (editor) is bundled into a **separate `admin.js` esbuild entry**
  loaded only by the admin root layout, so the public `app.js` bundle is not
  bloated by the editor for visitors who never see it. (Implemented as a second
  bundle rather than a dynamic `import()` split — same goal, no ESM/code-split
  migration of the shared bundle.)
- Milkdown's theme CSS is scoped to the admin editor container; the editor canvas
  **reuses the public post typography** (Lora serif, heading scale, spacing,
  blockquote/list rhythm) but in **neutral admin colors**.
- Admin chrome is driven by a scoped `admin.css` design-token system (semantic
  `.admin-*` classes over CSS custom properties), with a small theme-toggle hook
  in `app.js`. `site.css` is imported into Tailwind's `components` layer so admin
  utilities can win over it while the public site is unaffected. Per project
  rules, everything stays in the single `app.css` / `app.js` bundle pair (no
  external `<script src>`).

## Navigation shell

A **persistent left sidebar** with entries: **Dashboard**, **Posts**,
**Reading**, **Photos**, and a light/dark theme toggle in the footer. The
**Dashboard** entry is a landing hub.

### Dashboard hub

Three summary cards mirroring the sidebar sections, each showing a count plus a
primary quick-action:

- **Posts** — total + draft count · "New post"
- **Reading** — total + "currently reading/listening" count · "Add entry"
- **Photos** — galleries + photo count · "New gallery"

Below the cards, a short **"Recently updated"** list linking straight into the
relevant editor/drawer.

## Editing pattern (cross-cutting)

A **right-hand slide-over drawer** is the consistent editing affordance across
all three sections. Lists show records at a glance; the drawer holds the form /
settings for a single record. This is the shared interaction language of the
admin.

## Sections

### Posts

- **List = the hub.** Each row shows title, **status** (draft / published /
  scheduled), and date; click to open the editor. A quick status control may live
  on the row.
- **Editor:** a single, focused **CodeMirror 6 styled-markdown-source** editor
  (Obsidian "Live Preview" / Discord-composer style): the markdown source stays
  visible (`##`, backticks, `[text](url)`) but is styled in place, and everything
  — including links — is directly editable as text. One writing surface, no split
  preview. (We tried Milkdown WYSIWYG first; the rendered-as-you-type model hid
  the markers and made links/code awkward to edit, so we moved to styled source.)
  - **`body_markdown` stays the single source of truth.** The editor's content
    *is* the markdown (no serialization layer); on change it syncs to a hidden
    field and **MDEx renders `body_html` server-side on save, unchanged.**
  - **In-editor code highlighting** comes from CodeMirror's markdown nested code
    languages (`@codemirror/language-data`); the published page highlights
    canonically via MDEx/Lumis. GFM (tables, strikethrough, task lists) is just
    markdown the author writes, rendered by MDEx on the published page.
  - **Fidelity:** the editor matches the published page's **typography** (Lora),
    not its color (neutral admin palette). For the exact published render,
    **"View on site"** opens `/posts/:slug` (the true MDEx render — see draft
    visibility above).
  - **Integration:** the editor runs as a LiveView `phx-hook` with
    `phx-update="ignore"`, mirroring the markdown into a hidden field that drives
    the form's change/save.
- **Publish drawer:** a toolbar gear/"Publish" button slides in a panel with:
  - **Status** (draft ↔ published) — toggling sets/clears `published_at`.
  - **Slug** (auto from title, editable), **publish date** (a future date =
    scheduled), read-only **excerpt** and **reading time** (computed by MDEx).
  - Links: **View on site** (`/posts/:slug`), **Delete**.
- **No schema change.** Draft = `published_at` nil; scheduled = future
  `published_at`; published = `published_at <= now`.

### Reading

- A clean list with **status badges** (reading / read / listening / listened) and
  finished date.
- **Add / edit via the slide-over drawer** (consistent with Posts). The drawer
  form covers title, author, link, status, finished date, and the multi-line
  note.

### Photos

Two-level: **galleries** → **photos within a gallery**.

- **Galleries list** works like Posts: cover thumbnail + title + photo count,
  click to open a gallery.
- **In-gallery manager:**
  - **Upload** via LiveView drag-drop (`allow_upload`); image **dimensions
    (width/height) captured server-side via the `Image` library**, files stored
    locally (dev and prod — Fly volume), `image_key` generated on store.
  - **Drag-to-reorder** the photo grid (updates `position`).
  - **Clean thumbnail grid; click a photo → drawer** for alt text, replace image,
    delete. A **"needs alt" badge** flags photos missing alt text so blank alt
    still nags despite being a click away.
  - **Gallery settings** (title, slug, caption, taken-on) live in the usual
    settings drawer.

## Unit breakdown

Each is independently understandable and testable:

- `Newton.Accounts` (+ `users` table) — generated, trimmed to email+password.
- `Newton.Release.create_admin/2` — console admin creation.
- `NewtonWeb.Admin.Layouts` + `admin_root` layout — Linear-style admin shell,
  sidebar, and theme toggle, styled by `assets/css/admin.css`.
- `NewtonWeb.Admin.DashboardLive` — hub cards + recently-updated.
- `NewtonWeb.Admin.PostLive.{Index, Editor}` — list + Milkdown editor + publish
  drawer.
- `NewtonWeb.Admin.ReadingLive.Index` — list + drawer.
- `NewtonWeb.Admin.GalleryLive.{Index, Show}` — galleries list + in-gallery photo
  manager (upload, reorder, photo drawer, settings drawer).
- A shared **drawer component** used across sections.
- A **Milkdown editor hook** (`assets/js/hooks/milkdown_editor.js`) with the
  dynamic import.
- Context additions: admin-facing query functions (e.g. list all posts incl.
  drafts, photo reorder, gallery CRUD) added to `Blog`, `Reading`, `Gallery`.

## Error handling

- **Auth:** failed login → generic error (no account enumeration); admin routes
  redirect to login when unauthenticated.
- **Validation:** changeset errors surfaced inline in drawer forms via
  `to_form/2` + `<.input>`.
- **Uploads:** reject non-images / oversized files with a clear message; show
  per-file progress; a failed `Image` dimension read aborts that file's entry
  with an error rather than persisting a bad record.
- **Markdown:** the editor cannot emit raw HTML, and MDEx renders with
  `unsafe: false`, so the publish path stays XSS-safe.

## Testing approach

- **Auth:** generated `phx.gen.auth` tests, trimmed to match removed flows;
  add a test that public registration routes are gone and that an admin sees an
  unpublished `/posts/:slug` while anonymous gets 404.
- **LiveView:** per-section LiveView tests keyed off DOM IDs — list renders,
  drawer opens, create/edit/delete round-trips, status toggle updates publish
  state, photo reorder persists `position`, upload happy-path.
- **JS:** a Vitest test for the Milkdown hook's mount/serialize contract
  (markdown in → markdown out, GFM round-trip), consistent with the existing
  `assets/js` harness.
- TDD per project default: failing test first, then implement.

## Future (explicitly deferred)

- Scheduled-publish background job (today scheduling is passive — a future
  `published_at` simply isn't visible until that time passes on the next view).
- Image derivatives / responsive sizes via `Image`.
- Tags / series for posts.
