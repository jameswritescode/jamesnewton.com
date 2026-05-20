# Static Site → Phoenix Migration — Design

Migrate James Newton's personal site from the `website-template-ideation` static
HTML/CSS/JS prototype into the `Newton` Phoenix application, preserving the
warm, typography-first design exactly while moving content into a database and
the rendering into idiomatic Phoenix.

The static prototype is the design/content source of truth. Its
`docs/design.md`, `docs/tone.md`, and `docs/migration.md` describe the visual
system, voice, and porting intent and govern this work.

## Decisions (locked during brainstorming)

- **Content storage:** database-backed (Ecto). Posts store Markdown as the
  source of truth and render to cached HTML.
- **Render architecture:** classic Phoenix controllers + HEEx (dead views), not
  LiveView. All domain logic lives in contexts so a later LiveView reskin is a
  thin web-layer swap.
- **View transitions:** real `<a href>` navigation so cross-document
  `@view-transition { navigation: auto; }` fires natively — zero JS. (LiveView's
  client-side navigation would defeat this and require manual
  `document.startViewTransition()` wiring; explicitly avoided.)
- **Markdown + highlighting:** MDEx (Comrak + Autumn tree-sitter highlighting),
  server-side, in one render pass. No highlight.js, no client JS, no CDN.
- **Render timing:** render-on-write. `body_html` (and `excerpt`,
  `reading_time`) are computed when a post is written and cached in columns.
- **Styling:** port the prototype's `:root` token blocks verbatim; rebuild the
  prototype's component language as Phoenix function components. Colors, type
  ladder, and signature treatments stay token-driven CSS. Tailwind for
  incidental structural spacing only.
- **daisyUI:** stays installed/configured for a future admin surface; never used
  in public-facing templates.
- **Scope:** full-fidelity port — all six page types plus ripple canvas, photo
  lightbox, and (server-side) syntax highlighting.
- **Content types in DB:** posts, reading entries, photos (+ photo groups).
  Résumé is a static HEEx template.
- **Authoring:** deferred to a separate brainstorm. This pass seeds placeholder
  content; editing is via IEx/console. No auth, no admin, no upload UI yet.
- **Database:** SQLite via `ecto_sqlite3` (swap out the scaffold's Postgres).
  Single-node; DB file lives on the Fly.io volume.
- **Image storage:** local filesystem in both dev and prod (Fly.io volume).
  `Image` (libvips) is the intended future processing library; **no** Waffle/
  ExAws. This pass builds only the storage-agnostic key + URL resolver + a
  `/media` static plug. Full upload/derivative pipeline is deferred.

## Architecture & routing

Contexts:

- `Newton.Blog` — posts.
- `Newton.Reading` — reading-list entries.
- `Newton.Gallery` — photo groups + photos, image URL resolution.
- `Newton.Feed` — merged home-feed query across the three.
- Résumé has no context (static template).

Routes (all classic controllers + HEEx):

| Path | Controller#action | Page |
|---|---|---|
| `/` | `PageController#home` | intro + merged feed |
| `/posts` | `PostController#index` | posts list |
| `/posts/:slug` | `PostController#show` | individual post |
| `/resume` | `PageController#resume` | static résumé template |
| `/reading` | `ReadingController#index` | reading list |
| `/photos` | `PhotoController#index` | photo grid + lightbox |

Posts are addressed by `slug` for stable URLs.

## Data model (SQLite, `Newton.Repo`)

### `posts` — `Newton.Blog`

| Field | Type | Notes |
|---|---|---|
| `id` | integer | PK |
| `slug` | string | unique, indexed; URL key |
| `title` | string | |
| `excerpt` | string | computed on write from first paragraph of `body_markdown` if blank |
| `body_markdown` | text | source of truth |
| `body_html` | text | MDEx-rendered, cached on write |
| `reading_time` | integer | minutes; computed on write; nullable |
| `published_at` | utc_datetime | nil = draft; lists show non-nil & past only |
| `inserted_at` / `updated_at` | utc_datetime | |

### `reading_entries` — `Newton.Reading`

| Field | Type | Notes |
|---|---|---|
| `id` | integer | PK |
| `title` | string | |
| `author` | string | rendered with `<cite>` |
| `link` | string | nullable |
| `note` | string | nullable short annotation |
| `status` | string | `Ecto.Enum`: `:reading \| :read \| :listening \| :listened` |
| `finished_at` | date | nullable; orders the list |
| `inserted_at` / `updated_at` | utc_datetime | |

### `photo_groups` — `Newton.Gallery`

| Field | Type | Notes |
|---|---|---|
| `id` | integer | PK |
| `slug` | string | unique; anchor id (`eastern-sierra`) |
| `title` | string | "Eastern Sierra" |
| `caption` | text | prose line under the title |
| `taken_on` | date | rendered "June 2025"; orders groups desc |
| `inserted_at` / `updated_at` | utc_datetime | |

### `photos` — `Newton.Gallery`, belongs_to `photo_group`

| Field | Type | Notes |
|---|---|---|
| `id` | integer | PK |
| `photo_group_id` | integer | FK → `photo_groups`, indexed |
| `image_key` | string | opaque key; resolved by `Gallery.image_url/1` |
| `alt` | string | required; also used for "Enlarge: …" aria-label |
| `position` | integer | explicit order within group |
| `width` | integer | nullable; `<img width>` for lazy-load CLS prevention |
| `height` | integer | nullable; `<img height>` for lazy-load CLS prevention |
| `inserted_at` / `updated_at` | utc_datetime | |

No `users`/auth tables this pass.

## MDEx render pipeline

Rendering happens in `Newton.Blog` on write, via the post changeset:

- `body_html` ← `MDEx.to_html!(body_markdown, opts)` with GFM extensions and
  built-in Autumn (tree-sitter) syntax highlighting. `unsafe: false` by default
  so stored HTML is escape-safe; opt into raw HTML only if a post needs it.
- `excerpt` ← if blank, first paragraph of `body_markdown`, Markdown-stripped to
  plain text, truncated (~30 words / 200 chars at a word boundary).
- `reading_time` ← `ceil(word_count(body_markdown) / 200)` minutes.

Highlighting theme matches the prototype's `--syntax-*` tokens: pick the closest
Autumn theme and override token colors via the existing CSS custom properties so
light/dark track the design tokens. No cool-tone token colors (warm-only palette
is load-bearing per `design.md`).

Read path: controllers fetch the row and render `raw(post.body_html)`. Zero
render cost per request.

`mix newton.posts.rerender`: idempotent task re-running the pipeline over all
posts (for MDEx/theme upgrades).

## Components, tokens & styling

Port the entire `:root` (light) + dark-remap blocks from `styles.css` into
`assets/css/app.css` verbatim — palette tiers, layout sizes, radii, motion,
letter-spacing, opacity. These are the source of truth. Colors, type ladder, and
signature treatments stay token-driven CSS; Tailwind utilities only for
incidental structural spacing in HEEx.

Function components built from the prototype's component language:

| Component | Source pattern |
|---|---|
| `<.layout>` (root) | `<head>` block, skip-link, ripple canvas, `site-header` |
| `<.site_nav>` | middot-separated primary nav |
| `<.feed>` + `<.feed_item>` | merged stream; variants `:post`, `:book`, `:photo` |
| `<.post_article>` | `.post` wrapper: title, byline meta, `raw(body_html)` |
| `<.post_list>` | posts index rows |
| `<.reading_list>` | `<cite>`-based entries ordered by `finished_at` |
| `<.photo_group>` + `<.photo_grid>` | group header + masonry columns |
| `<.section_label>`, `<.meta_line>` | reusable label + middot-meta primitives |

The `pre::before` uppercase language badge is pure CSS keyed off MDEx's
`language-xxx` class — ports as-is.

## Merged home feed

`Newton.Feed.recent/1` pulls recent published posts (`published_at`), reading
entries (`finished_at`), and photo groups (`taken_on`); normalizes each to
`%{date, kind, payload}`; sorts desc; limits. The book verb ("Read" vs
"Listened to") derives from `status`. Photo entries link to
`/photos#<group-slug>` and show the group's first photo image-first.

## JS behaviors (LiveSocket hooks, DOM-only)

`app.js` registers hooks; they attach via `phx-hook` and run on mount without
needing a socket connection.

- `Hooks.RippleCanvas` — `ripple.js` logic verbatim in `mounted()`, cleanup in
  `destroyed()`; reads `--dot` tokens. Attached to the layout `<canvas>`.
- `Hooks.PhotoMasonry` — column-distribution; `mounted()` builds columns,
  debounced `resize` re-layouts, `destroyed()` removes the listener.
- `Hooks.PhotoLightbox` — overlay open/close + focus-trap, minus the Unsplash
  high-res-swap hack. Opens with the full image; `Esc`/click-out close; restores
  focus.
- Syntax highlighting — none (server-side via MDEx).

## Layout, dark mode, view transitions, media serving

- **Root layout** (`root.html.heex`): the prototype's `<head>` — dual
  `theme-color`, Lora preconnect + stylesheet, inline scheme-class script (sets
  `.dark` on `<html>` from `prefers-color-scheme` before paint), skip-link,
  ripple canvas, site header. App layout wraps content in
  `<main id="main" class="page">`.
- **Dark mode**: system-driven only (no toggle), as prototype — inline script +
  CSS `:root.dark` / `@media` remap.
- **View transitions**: `@view-transition { navigation: auto; }` in CSS; real
  links everywhere. No JS.
- **`/media` static plug**: `Plug.Static` at `/media` serving the configured
  images root (Fly volume in prod), separate from `phx.digest` assets.
  `Gallery.image_url/1` returns `/media/<key>` for stored files and passes
  absolute URLs through untouched (dev seeds use remote placeholder URLs).

## Seeds & testing

- **Seeds** (`priv/repo/seeds.exs`): port the prototype's placeholder content —
  ~2 posts (including the code-heavy "Three Ways to Retry", bodies converted to
  Markdown), the reading entries, and the 4 photo groups with their photos using
  the existing remote URLs as `image_key`s. Idempotent upserts by slug.
- **Testing**: context tests (changeset computed fields —
  `excerpt`/`reading_time`/`body_html`; feed merge ordering; published-only
  filtering) and controller tests (each route 200s; post `show` renders
  `body_html`; 404 on bad slug). DOM-only hooks are not unit-tested this pass.

## Out of scope (deferred)

- Authoring UI, authentication, admin surface (separate brainstorm).
- Image upload + `Image`/libvips derivative pipeline (only key + resolver +
  `/media` plug now).
- Postgres (revisit if/when single-node SQLite is outgrown).
- `width`/`height` auto-population (hand-set in seeds for now).
- Same-document (LiveView) view transitions.
