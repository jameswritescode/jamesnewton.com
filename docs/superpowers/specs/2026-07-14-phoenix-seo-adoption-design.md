# phoenix_seo Adoption — Design

**Date:** 2026-07-14
**Status:** Approved direction; not yet implemented

## Problem

SEO metadata is hand-rolled: ~12 meta lines in `root.html.heex` with `||`
fallbacks, five og assigns in `post_controller.ex`, and nothing else — no
canonical URLs, no structured data. Only posts have per-page metadata;
every other public page emits the site tagline.

## Decisions (made during brainstorming)

1. **Library and version:** `phoenix_seo` at **0.3.0-rc** (James read the
   changelog and chose it — the JSON-LD overhaul is the version's point).
   Requires Elixir ≥ 1.17 (met).
2. **Sequencing:** Phase (a) migrates the existing metadata and verifies
   parity; phase (b) then adds deliberate per-page SEO items for the
   non-post public pages. Both in this project, in that order.
3. **JSON-LD scope:** `Article` on posts plus `WebSite` + `Person`
   site-wide. **No breadcrumbs** (two-level site; breadcrumb rich results
   reward depth we don't have).
4. **No `llms.txt`** for now — revisit later.
5. **Canonicals:** every public page self-canonical; post *preview* URLs
   (`?p=` token) keep their existing `noindex` and canonicalize to the
   clean post URL.

## Design

### 1. Dependency & wiring

- `{:phoenix_seo, "~> 0.3.0-rc"}` in `mix.exs`.
- 0.3.0's compile-time JSON-LD: `compilers: [:seo_jsonld] ++ Mix.compilers()`
  in the project config, and `config :phoenix_seo, json_ld_types:` limited
  to exactly `Article`, `WebSite`, `Person` — not `:all`.

### 2. `NewtonWeb.SEO` + the Post protocol implementation

One new file owns all SEO knowledge:

- Site defaults (replacing the layout's `||` fallbacks): site name
  "James Newton", description "Software & Photography" (today's tagline;
  phase (b) may refine), default image `og-default.png`, Twitter
  `summary_large_image`, and the site-wide `WebSite` + `Person` JSON-LD.
- `defimpl` for `Newton.Blog.Post`: title; excerpt as description;
  `article` og type with the published date; canonical
  `url(~p"/posts/#{slug}")`; `og:image` = the existing SocialCard endpoint
  `url(~p"/og/posts/#{slug}")` with `width: 1200, height: 630` and the
  post title as alt — dimensions and alt are net-new over the hand-rolled
  tags. Article JSON-LD from the same fields.
- `Newton.SocialCard` and `OgImageController` are untouched — the library
  emits tags; the image pipeline stays ours.

### 3. The swap

- `root.html.heex`: the hand-rolled og/twitter meta block is replaced by
  the library's single head render (fed from the conn; pages without an
  assigned item get the site defaults).
- `post_controller.ex`: the five og assigns become one SEO assign of the
  post struct. The preview branch assigns the same item — its canonical
  already points at the clean URL by construction — and the existing
  `page_robots` noindex behavior is preserved.
- The `page_title`/`live_title` mechanism is unchanged (title rendering
  stays with `<.live_title>`; the library handles meta, not the title
  tag).

### 4. Verification (phase a gate)

- **Parity diff:** before any change, capture the rendered `<head>` meta
  of all seven public routes (`/`, `/resume`, `/posts`, `/posts/:slug`,
  `/reading`, `/photos`, `/links`). After migration, capture again and
  diff: every existing og/twitter value must be preserved (modulo
  attribute ordering), and additions (canonical, image dimensions/alt,
  JSON-LD) must be exactly the expected set. The diff is reviewed, not
  skimmed.
- **Controller tests:** on a post page — og:title equals the post title,
  canonical tag present with the clean URL, the `ld+json` script parses
  as JSON with `"@type" => "Article"`; on the home page — site defaults +
  `WebSite`/`Person` JSON-LD parse. Preview URL keeps noindex and clean
  canonical.
- **CSP check:** JSON-LD `<script type="application/ld+json">` is
  non-executable and unaffected by the nonce-based `script-src`; a test
  asserts the page still renders it (no nonce required).
- **James's tophat:** paste a post URL into a real unfurler (Slack or
  iMessage) and confirm the card still renders with the dynamic image.

### 5. Phase (b): deliberate per-page items

After (a) verifies, each remaining public page gets a real SEO item with
a hand-written description (drafted during implementation, approved by
James at tophat): home, posts index, reading, photos, links, resume.
Same mechanism (SEO assign in each controller), no new machinery.

## Out of scope

- Breadcrumbs, FAQ, and Actions JSON-LD (considered; nothing truthful to
  declare on a two-level personal site — FAQ rich results are restricted
  anyway, and Actions serve on-site search/apps we don't have).
- `llms.txt` (parked by decision; the library supports it if revisited).
- Admin pages, sitemap changes, the og-image pipeline itself.

## Testing

Covered in §4: parity diff artifact + controller tests for the tag/JSON-LD
contract + preview noindex/canonical + James's unfurl tophat. Existing
controller/LiveView suites must pass unchanged except where they assert
the old meta markup directly (none known; any discovered get justified
individually).
