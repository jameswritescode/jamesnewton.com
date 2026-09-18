# Admin Pages: editable standalone markdown pages

Add a **Pages** section to the admin: editable, markdown-authored standalone
pages (e.g. `/about`, `/now`, `/uses`) served at top-level slugs on the public
site. Pages are a new content type alongside posts, reading, and photos. The
hand-tuned `/resume` template stays as-is and is out of scope.

## Decision summary

- **Purpose:** editable standalone pages, authored in markdown, each at its own
  top-level path. Not a feed, not a page builder, not section-index copy.
- **URL:** top-level `/:slug` (e.g. `/about`), via a catch-all route placed last
  so it cannot shadow existing routes, backed by a reserved-slug guard.
- **Lifecycle:** a `published` boolean (draft ↔ published). No scheduling, no
  preview tokens.
- **Editor:** the same CodeMirror markdown editor and inline image upload as
  posts, with autosave. A *lean* editor — none of the post-only machinery.
- **Navigation:** published pages are reachable by URL only; they appear in no
  menu automatically. Placement is done by hand.
- **Images:** per-page uploads via a `PageImage` table mirroring `PostImage`;
  the shared file store and upload *behavior* are extracted, not the table.
- **Code sharing:** because pages overlaps posts heavily, genuinely shared
  behavior is extracted into shared modules that both editors consume, rather
  than forked from the post editor. See "Guiding principle" below.

## Guiding principle: share behavior, not divergent structure

Extract where the behavior is genuinely shared and the seam is clean; duplicate
small divergent bits rather than build a leaky abstraction. Every extraction
lands **behind the existing post tests first** (posts refactored to consume the
shared version, suite green), *then* pages builds on the shared version — so the
working post editor is never put at risk by the refactor.

**Extracted and shared (posts refactored to consume):**

1. **Media file store** — `Newton.Gallery.Storage` → `Newton.Storage` (pure
   infra: `store/2`, `delete/1`, magic-number sniffing, path containment), plus
   the generic `image_url/1` → `Newton.Storage.url/1`.
2. **Inline-image upload flow** — store → attach ledger row → push
   `insert_image`; the upload constants (`accept`, max entries, max file size);
   and the pure `image_referenced?(body_markdown, key)` check. Parameterized by
   owner (an attach callback and a create-on-demand fn).
3. **Autosave engine** — the debounce timer, `save_state` transitions, param
   staging, and the `_unused_` field handling — as shared functions both
   editors delegate to.
4. **Draft-on-first-image** — the `ensure_record` pattern (create a draft the
   first time an image is uploaded into a new document), parameterized by a
   create fn.
5. **Public content article component** — the shared `article.post` /
   `post-body` skeleton that renders `body_html`.
6. **Admin index list/row chrome** — a shared component, if the post-index and
   page-index row structures line up.

**Kept separate (forcing a shared abstraction would leak):** the two schemas
and their image tables; the two changesets; and post-only concerns — excerpt,
reading_time, social card, scheduled publish, preview token, publication
notifier.

## Architecture

| Unit | Responsibility |
|---|---|
| `Newton.Storage` | Site media file store (lifted from `Gallery.Storage`); `store/2`, `delete/1`, `url/1`. Shared by Gallery, Blog, Pages. |
| `Newton.Pages` (context) | Pages CRUD, published-scoped lookup, page images. Mirrors `Newton.Blog`'s shape but leaner. |
| `Newton.Pages.Page` | Schema: slug, title, body_markdown, body_html, meta_description, published, lock_version. |
| `Newton.Pages.PageImage` | Per-page upload ledger; mirror of `Newton.Blog.PostImage`. |
| Shared editor behavior | Inline-image upload flow, autosave engine, draft-on-first-image, `image_referenced?` — consumed by both the post and page editors. |
| `PageContentController` | Public `/:slug` render; published for all, draft for logged-in admin, 404 otherwise. |
| `NewtonWeb.Admin.PageLive.Index` | Admin list of pages. |
| `NewtonWeb.Admin.PageLive.Editor` | Admin new/edit editor (lean cousin of the post editor). |

The codebase already organizes one context per content type (Blog, Reading,
Gallery); `Newton.Pages` follows that pattern. Posts are left structurally
intact — they only change to *consume* the extracted shared behavior.

## Data model

**`pages`** table:
- `slug` (string, unique), `title` (string), `body_markdown` (text),
  `body_html` (text), `meta_description` (string, nullable),
  `published` (boolean, default `false`), `lock_version` (integer, default 1),
  timestamps.

**`page_images`** table (mirror of `post_images`):
- `key` (string, unique), `original_filename` (string, nullable),
  `page_id` (FK → pages, cascade on delete), timestamps.

`Newton.Pages.Page.changeset/2`:
- casts `slug, title, body_markdown, meta_description, published`
- `validate_required([:slug, :title])`
- `unique_constraint(:slug)`
- `optimistic_lock(:lock_version)`
- renders `body_html` from `body_markdown` via `Newton.Markdown.to_html/1`
  when the body changes (coerce a missing body to `""`, as posts do)
- **reserved-slug validation** — rejects slugs that collide with existing
  top-level routes: `posts`, `blog`, `reading`, `photos`, `links`, `resume`,
  `admin`, `oauth`, `mcp`, `og`, `login`, `logout`, `dev`, `sitemap.xml`,
  `robots.txt`, `.well-known` (defined as a module list so it stays in sync).

`Newton.Pages.PageImage.create_changeset/2`: casts `key, original_filename`;
`validate_required([:page_id, :key])`; `unique_constraint(:key)`;
`foreign_key_constraint(:page_id)`. All fields server-set, never form-cast —
same posture as `PostImage`.

Secrets/keys posture is unchanged from posts: storage keys are opaque UUIDs;
single-user site, so no `user_id` ownership column.

## Context — `Newton.Pages`

- `list_pages/0` — admin list, newest-first.
- `get_page!/1` — by id (admin).
- `get_published_page_by_slug/1` — public lookup, `published == true`,
  returns `nil` when absent or draft.
- `get_page_by_slug/1` — admin/preview lookup regardless of published state.
- `create_page/1`, `update_page/2` (rescue `Ecto.StaleEntryError → {:error,
  :stale}`), `delete_page/1` (sweeps image files before deleting the row;
  ledger rows cascade).
- Image fns: `attach_image/3`, `list_images/1`, `delete_image/1` —
  delegating to the shared image behavior; `delete_image/1` refuses while the
  page body still references the key (mirrors `Blog.delete_image/1`).

## Routing

Public catch-all, in a dedicated scope placed at the **very end** of the router
(after every other single-segment GET route — `/login`, `/logout`,
`/sitemap.xml`, `/robots.txt` — so route matching resolves those first):

```elixir
scope "/", NewtonWeb do
  pipe_through :browser
  get "/:slug", PageContentController, :show
end
```

Reserved-slug validation (data model) is the belt to this route ordering's
suspenders: even if a page somehow held a colliding slug, the specific route
wins, and the reserved list prevents creating one in the first place.

Admin routes, added to the existing `live_session :admin`:

```elixir
live "/pages", PageLive.Index, :index
live "/pages/new", PageLive.Editor, :new
live "/pages/:id/edit", PageLive.Editor, :edit
```

## Public rendering — `PageContentController`

`show/2`:
- Look up the page by slug (all states).
- **Published** → render.
- **Draft** → render only when `current_scope.user` is present (logged-in
  admin), with a small "Draft — not public" banner; otherwise 404.
  `current_scope` is available because the route runs through `:browser`.
- **Unknown slug** → 404 (`Phoenix.Router.NoRouteError`/`raise` the standard
  not-found path used elsewhere).
- Renders `body_html` inside `<Layouts.app>` using the shared content-article
  component (the `article.post` / `post-body` skeleton posts already use). If
  the extraction is clean, post-show is refactored to the same component.
- SEO: `title` = page title; `description` = `meta_description` or a
  markdown-derived fallback; `path` = `/#{slug}`.

## Admin

**`PageLive.Index`** — list of pages: title, slug, published badge,
updated-at; new button; edit and delete actions. Mirrors `PostLive.Index`; if
the row/list chrome matches, extract a shared component rather than copy it
(bias-to-reusable-UI-chrome).

**`PageLive.Editor`** (`:new` / `:edit`) — a lean cousin of the post editor:
- Fields: `title`, `slug`, `meta_description`, `published` toggle, and the
  CodeMirror `body_markdown` with inline image upload.
- Reuses the CodeMirror colocated hook, the admin form components, the shared
  inline-image upload flow, and the shared autosave engine.
- **Autosave** — matches the post editor (debounced), for a consistent editing
  feel; the shared autosave engine drives both.
- **Draft-on-first-image** — the first inline upload triggers `ensure_page`
  (creates a draft), via the shared helper.
- Delete action (sweeps images).
- **Omits** the post editor's drawer, social-card preview, scheduling,
  preview tokens, and publication notifier.

**Nav + dashboard:** add a "Pages" entry to the admin nav (`layouts.ex`
`nav_items`) and a Pages-count card on the admin dashboard.

## Error handling

- Unknown or draft page for anonymous visitor → 404, same as any missing route.
- Reserved or duplicate slug → changeset error surfaced in the editor form.
- Stale concurrent edit → `{:error, :stale}` surfaced in the editor (mirrors
  posts).
- Image store failure → flash error, placeholder not replaced (mirrors the
  post editor's inline-upload behavior).

## Testing (behavior-focused)

**Task 0 (storage lift):** existing Gallery/Blog/editor tests updated to the
`Newton.Storage` name; full suite stays green. No behavior change.

**Shared-behavior extractions:** each extraction keeps the existing post tests
green as it lands (the tests are the regression guard); add focused unit tests
for the pure pieces (`image_referenced?`).

**`Newton.Pages` context:**
- create / update / delete; slug uniqueness; reserved-slug rejection.
- `get_published_page_by_slug/1` returns published, refuses drafts.
- stale-update handling.
- image attach / delete; `delete_image` refused while referenced; page delete
  sweeps image files.

**Public (`PageContentController`):**
- published page renders at `/:slug`.
- draft 404s for anonymous, renders (with banner) for logged-in admin.
- unknown slug 404s.

**Admin (LiveView):**
- create → publish → edit → delete flow drives real outcomes.
- inline image upload inserts a URL into the body.
- reserved/duplicate slug shows a form error.

Tests assert on outcomes and interactions, not static markup.

## Out of scope (deliberate)

- Auto-navigation / nav placement fields (reachable by URL only).
- Scheduling, preview tokens, social cards, excerpt, reading_time for pages.
- Migrating `/resume` to a page (stays hand-tuned HEEx).
- A generic polymorphic content abstraction, or a single shared `images` table
  (mirror tables + shared behavior chosen instead; revisit if a third
  image-owning content type appears).
- Consolidating `Blog.ImageAudit`'s direct `media_root` access (unrelated).
