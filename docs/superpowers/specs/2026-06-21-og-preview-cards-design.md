# Open Graph / Twitter Preview Cards — Design Spec

**Date:** 2026-06-21
**Status:** Approved (pending written review)
**Branch context:** `phoenix-migration`

## Overview

When a page is linked on Twitter/Discord/Slack/etc., show a rich preview. Every
public page gets Open Graph + Twitter **meta tags** (title, description, image,
url). **Posts** additionally get a **custom-generated card image** with the post
**title** as the primary text and **published date · reading time** as secondary
text, regenerated in the background when the title (or publish date) changes. A
single static **default card** covers all other pages.

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
- **Per-post card content:** brand background, **title** (Lora, large, wrapped +
  truncated to fit), secondary line **"<Mon D, YYYY> · <N> min read"**, and a
  small footer (`jamesnewton.com`).
- **Color scheme:** decided **visually during the build** — generate samples in
  both a warm-red palette (`#aa4040` bg, cream text) and a dark palette
  (`#151311` bg, cream text); the user picks. The renderer is palette-parameterized.
- **Regeneration trigger:** asynchronous via a supervised `Task` (a
  `Task.Supervisor` in the app tree), fired from the Blog context after a post is
  saved **when the title or `published_at` changed** (or no card exists yet).
  Oban is out of scope unless we outgrow `Task`.
- **Out of scope:** OG images for drafts/private previews (they're `noindex`);
  regenerating on body-only edits (reading time may lag until the next
  title/publish change); per-network image variants; animated cards.

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

- `post_card(%{title, published_on, reading_time}, palette)` → `{:ok, binary}` —
  composes the 1200×630 card: background fill, the title wrapped to the card width
  in Lora (auto-shrink/truncate for very long titles), the secondary
  date·reading-time line, and the footer. Returns PNG bytes.
- `default_card(palette)` → `{:ok, binary}` — the static site card: "James Newton"
  + a short tagline + the JN mark, same dimensions/palette.
- A `palette` is a small struct/map (`bg`, `fg`, `muted`) so red vs dark is one
  parameter; the chosen palette is then the module default.

Fonts: `priv/fonts/Lora-SemiBold.ttf` (+ regular if needed) committed; a
`priv/fonts/fonts.conf` adds that dir and includes the system defaults; the app
sets the fontconfig env (e.g. `FONTCONFIG_FILE`) **before vix initializes**
(early in `Newton.Application.start/2` or via release env). The spike nails the
exact incantation.

## Section 3 — Data model, storage & async regeneration

- **Migration:** add `og_image_key :string` (nullable) to `posts`. Not
  mass-assignable (set only by the regen path).
- **Storage:** reuse `Newton.Gallery.Storage` — render the PNG to a temp file,
  `Storage.store(tmp, "og.png")` → key (served at `/media/<key>`). On regen,
  store the new key, set it on the post, and `Storage.delete/1` the old key.
- **Supervision:** add a `Task.Supervisor` (e.g. `Newton.TaskSupervisor`) to the
  application children.
- **Trigger (`Newton.Blog`):** `create_post/1` and `update_post/2`, on success,
  check whether the changeset changed `:title` or `:published_at` (or the post has
  no `og_image_key`). If so **and the post is published** (a public card only
  matters for live posts), start an async task:
  `Task.Supervisor.start_child(Newton.TaskSupervisor, fn -> Blog.regenerate_og_image(post) end)`.
- **`Blog.regenerate_og_image/1`** (sync, the unit-testable core): builds the
  card via `SocialCard.post_card/2` from the post's title/published_at/reading_time,
  stores it, updates `og_image_key` (programmatic changeset, deletes the prior
  key). Errors are logged and swallowed — a card failure must never break saving.

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
`og_image` = the post's card (`Endpoint.url() <> "/media/" <> og_image_key`) or the
default card if the key is nil. Drafts/previews use the defaults (no private card).
All image/url values are **absolute** (crawlers require it).

## Section 5 — The default site card

Generated **once** with `SocialCard.default_card/1` (via a one-off `mix run` during
implementation) and committed as `priv/static/og-default.png`; add it to
`NewtonWeb.static_paths()`. Non-post pages (home, /posts, /reading, /photos,
/resume) reference it through the default `og:image`. Regenerated only by re-running
the generator if the brand changes.

## Error handling / edge cases

- **Card render fails** (font/lib issue): `regenerate_og_image` logs and returns
  without raising; the post keeps its old (or nil) `og_image_key`; saving is
  unaffected; meta `og:image` falls back to the default card.
- **No card yet** (older posts, or first publish before the async task finishes):
  `og:image` falls back to the default until the task completes.
- **Very long titles:** the renderer wraps and, past a max, reduces font size /
  truncates with an ellipsis so text always fits 1200×630.
- **Drafts / `?p` previews:** no per-post card (defaults), consistent with their
  `noindex` status.
- **Reading-time staleness:** body-only edits don't trigger regen; the card's
  reading time refreshes on the next title/publish change. Acceptable.

## Testing approach

- **Spike:** manual visual confirmation (a rendered "Hello" PNG in Lora).
- **`Newton.SocialCard`:** `post_card/2` and `default_card/1` return a valid PNG of
  exactly 1200×630 (assert PNG magic bytes + dimensions via `Image`); long-title
  input still produces a 1200×630 image (no overflow/crash).
- **`Blog.regenerate_og_image/1`:** for a published post, sets a non-nil
  `og_image_key` and the stored file exists; replaces+deletes a prior key.
- **Trigger:** updating a published post's **title** results (synchronously, by
  calling the regen core, or via the task with a sync await in test) in a refreshed
  `og_image_key`; a body-only change does not.
- **Meta tags (controller):** a published post's `<head>` has `og:title` = title,
  `og:description` = excerpt, an absolute `og:image`, `og:type=article`,
  `twitter:card=summary_large_image`; the home page uses the default image and
  `og:type=website`.
- **Visual:** render sample post cards + the default card in **both palettes**,
  screenshot, user picks the palette (this resolves the color decision).

## Unit breakdown

- `mix.exs` — add `{:image, "~> ...""}` (and its `vix` dep).
- `priv/fonts/Lora-SemiBold.ttf`, `priv/fonts/fonts.conf` — in-repo font + config.
- `lib/newton/application.ex` — `Task.Supervisor` child + fontconfig env at boot.
- `lib/newton/social_card.ex` — the renderer (`post_card/2`, `default_card/1`).
- `priv/repo/migrations/*_add_og_image_key_to_posts.exs`, `lib/newton/blog/post.ex`
  (field), `lib/newton/blog.ex` (trigger + `regenerate_og_image/1`).
- `priv/static/og-default.png` — generated, committed; `NewtonWeb.static_paths()`.
- `lib/newton_web/controllers/post_controller.ex` — OG assigns.
- `lib/newton_web/components/layouts/root.html.heex` — meta tags.

## Out of scope (future)

- Cards for the reading/photos items individually; locale/og:locale; structured
  data (JSON-LD); cache-busting query strings; CDN for `/media`.
