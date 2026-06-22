# Open Graph / Twitter Preview Cards — Design Spec

**Date:** 2026-06-21
**Status:** Approved (pending written review)
**Branch context:** `phoenix-migration`

## Overview

When a page is linked on Twitter/Discord/Slack/etc., show a rich preview. Every
public page gets Open Graph + Twitter **meta tags** (title, description, image,
url). **Posts** additionally get a **custom-generated card image** with the post
**title** as the primary text and **published date · reading time** as secondary
text, **rendered on demand** at `GET /og/posts/:slug` from the live post. A single
static **default card** covers all other pages.

> **Revision (2026-06-21):** the original design stored a generated PNG per post
> (an `og_image_key` column + a `Task.Supervisor` that regenerated the card in the
> background on title/date changes + `Gallery.Storage`). It was replaced with an
> **on-demand endpoint** (Section 3 below): the card is rendered from the post each
> request and cached via HTTP headers. This removes the migration, the column, the
> background job, the storage writes, and the staleness window — and the card can
> never be out of date. Per-request render cost (tens of ms) is irrelevant because
> OG images are fetched by crawlers when a link is *shared*, not on user navigations.

## Decisions (locked)

- **Rendering engine:** the **`image`** Elixir library (libvips via `vix`), text
  drawn with libvips/Pango. **Lora** is shipped in-repo (`priv/fonts/`) and made
  resolvable via a project `fonts.conf` + a fontconfig env var set at boot — so
  rendering is identical in dev and prod with no OS-level font install.
- **Spike first:** the very first implementation task verifies vix can render Lora
  text to a PNG in this environment. If it can't, fall back to the favicon's
  proven Node `fontkit`+`sharp` pipeline (run as a generation step). No further
  work until the spike passes one way or the other.
- **Card size:** 1200×630 (standard `summary_large_image`).
- **Per-post card content:** a **"James Newton"** brand mark top-left, the **title**
  (Lora, font size scaled down by length, wrapping to a second line for long titles),
  the **excerpt** beneath it (truncated to ~160 chars), and a bottom line
  **"<Mon D, YYYY> · <N> min read"**. Flat background — a dot-matrix accent was
  trialed and removed.
- **Color scheme:** **dark** — bg `#151311`, cream text `#eed3ba`, muted secondary
  `#ad9987` — with a 20px full-width cream accent stripe along the bottom edge. (A
  warm-red palette was trialed; the site is going dark-only, so dark won.) The
  renderer stays palette-parameterized (`red` + `dark` in `@palettes`) but defaults
  to and only uses `dark`.
- **Delivery:** rendered **on demand** by a thin controller at `GET /og/posts/:slug`
  and returned as `image/png` with `Cache-Control` (no stored image, no DB column,
  no background job). Always reflects the live post. Crawlers/CDN cache the bytes.
- **Out of scope:** OG images for drafts/private previews (they're `noindex` — they
  use the default card); per-network image variants; animated cards; a stored/CDN
  copy of the per-post card.

## Section 1 — Feasibility spike (first task)

Confirm `Image.Text`/vix renders Lora to a PNG in dev: load the in-repo Lora via
fontconfig, render a short string at a large size, write a PNG, eyeball it. If it
works, proceed with the `image`-based renderer. If vix lacks working Pango text
support, switch the renderer to a Node `fontkit`+`sharp` generation step (same
glyph-path approach as the favicon) invoked at card-generation time. The rest of
the design (trigger, storage, meta tags, default card) is unchanged either way —
only `Newton.SocialCard`'s internals differ.

## Section 2 — The card renderer (`Newton.SocialCard`)

A context module that renders card PNGs (pure, no DB):

- `post_card(%{title, excerpt, published_on, reading_time}, palette)` →
  `{:ok, binary}` — composes the 1200×630 card: background fill, the "James Newton"
  brand mark, the length-scaled title wrapped to the card width in Lora, the excerpt
  beneath it, and the bottom date·reading-time line. Returns PNG bytes.
- A `palette` is a small map (`bg`, `fg`, `muted`); `dark` is the module default.
- The **static site card is not rendered by this module** — it's a fixed Figma
  export committed as `priv/static/og-default.png` (see Section 5). The renderer has
  no `default_card/1`.
- Date formatting is shared via `Newton.Format.format_date/1` (full month), not
  duplicated here.

Fonts: `priv/fonts/Lora.ttf` (the variable font) committed; a `priv/fonts/fonts.conf`
adds that dir and includes the system defaults; `config/runtime.exs` sets
`FONTCONFIG_FILE` **before vix initializes**. On macOS dev, libvips resolves fonts
via CoreText (so Lora is also installed locally for rendering); on Linux/prod it
resolves via fontconfig + the bundled font. The Pango font string is `font: "Lora"`
with a separate `font_size:` integer.

## Section 3 — The on-demand image endpoint

A thin `NewtonWeb.OgImageController` serves `GET /og/posts/:slug`:

- Loads the **published** post via `Blog.get_published_post!/1` (raises → 404 for
  unknown or unpublished slugs).
- Renders the card with `SocialCard.post_card/2` from the post's
  title/excerpt/published_at/reading_time and streams the PNG with
  `content-type: image/png` and `Cache-Control: public, max-age=3600`.
- On the unlikely render error, falls back to streaming the static
  `priv/static/og-default.png` rather than 500-ing, so a crawler still gets an image.

**Routing:** the `/og` route is in its **own scope with no pipeline** — not the
`:browser` pipeline, whose `plug :accepts, ["html", "json"]` would 406 an image
request that sends `Accept: image/png`. The endpoint needs no session/CSRF/layout;
the controller sets the response headers explicitly.

No database column, no storage, no background job, no regeneration trigger — the
card is computed from the live post on each request, so it is never stale. HTTP
caching (and any future CDN/`Cachex` layer, if ever needed) covers repeat fetches.

## Section 4 — Meta tags (public layout)

In `lib/newton_web/components/layouts/root.html.heex` `<head>`, add OG/Twitter
tags driven by optional assigns with sensible defaults:

- `og:title` = `@og_title` || the page/site title
- `og:description` = `@og_description` || a site description constant
- `og:image` = `@og_image` (absolute) || the default card's absolute URL
- `og:url` = `@og_url` || `Phoenix.Controller.current_url(@conn)`
- `og:type` = `"article"` for posts else `"website"`; `og:site_name` = `"James Newton"`
- `twitter:card` = `"summary_large_image"`; `twitter:title`/`twitter:description`
  mirror the OG values.

`PostController.show` sets the assigns from the post: `og_title` = title,
`og_description` = excerpt, `og_url` = canonical `url(~p"/posts/#{slug}")`,
`og_image` = the post's live card URL `url(~p"/og/posts/#{slug}")` for published
posts, or the default card `url(~p"/og-default.png")` for drafts/previews (noindex).
All image/url values are **absolute** (crawlers require it).

## Section 5 — The default site card

A fixed brand image (the "JN" monogram lockup — "James Newton" / "Software &
Photography" on the dark bg with the cream stripe), designed in Figma and committed
as-is to `priv/static/og-default.png` (1200×630); add it to `NewtonWeb.static_paths()`.
It's **not rendered** — it has no dynamic content, so generating it would only
reproduce a worse copy of the export. Non-post pages (home, /posts, /reading,
/photos, /resume) reference it through the default `og:image`. Replaced only by
dropping in a new export if the brand changes.

## Error handling / edge cases

- **Card render fails** (font/lib issue): the endpoint streams the static
  `og-default.png` instead of 500-ing; the post page's meta tags are unaffected.
- **Unknown / unpublished slug:** `Blog.get_published_post!/1` raises → 404. Post
  pages only reference the endpoint for *published* posts, so this stays internal.
- **Very long titles:** the renderer scales the font down by length and wraps to a
  second line so text always fits 1200×630; the excerpt is truncated to ~160 chars.
- **Drafts / `?p` previews:** no per-post card (default card), consistent with their
  `noindex` status.
- **Reading time:** always current — the card is rendered from the live post, so any
  edit (including body-only) is reflected on the next crawl/cache expiry.

## Testing approach

- **Spike:** manual visual confirmation (a rendered "Hello" PNG in Lora).
- **`Newton.SocialCard`:** `post_card/2` returns a valid PNG of exactly 1200×630
  (assert PNG magic bytes + dimensions via `Image`); long-title and nil-excerpt
  input still produce a 1200×630 image (no overflow/crash).
- **`OgImageController`:** `GET /og/posts/:slug` for a published post returns a
  `200` `image/png` of exactly 1200×630 with a `public` `Cache-Control`; an unknown
  or unpublished slug returns `404`.
- **Meta tags (controller):** a published post's `<head>` has `og:title` = title,
  `og:description` = excerpt, an absolute `og:image`, `og:type=article`,
  `twitter:card=summary_large_image`; the home page uses the default image and
  `og:type=website`.
- **Visual:** render sample post cards (short + long title), compare against the
  Figma mockups, confirm the match. (Resolved: dark palette.)

## Unit breakdown

- `mix.exs` — add `{:image, "~> ...""}` (and its `vix` dep).
- `priv/fonts/Lora-SemiBold.ttf`, `priv/fonts/fonts.conf` — in-repo font + config.
- `config/runtime.exs` — fontconfig env at boot (before vix initializes).
- `lib/newton/social_card.ex` — the renderer (`post_card/2` only).
- `lib/newton/format.ex` — shared `format_date/2`; `NewtonWeb.Helpers` delegates to it.
- `lib/newton_web/controllers/og_image_controller.ex` — `GET /og/posts/:slug`.
- `lib/newton_web/router.ex` — pipeline-less `/og` scope.
- `priv/static/og-default.png` — committed Figma export; `NewtonWeb.static_paths()`.
- `lib/newton_web/controllers/post_controller.ex` — OG assigns.
- `lib/newton_web/components/layouts/root.html.heex` — meta tags.

## Out of scope (future)

- Cards for the reading/photos items individually; locale/og:locale; structured
  data (JSON-LD); cache-busting query strings; CDN for `/media`.
