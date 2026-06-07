# Static Site → Phoenix Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate James Newton's static HTML/CSS/JS personal site into the `Newton` Phoenix app — DB-backed posts/reading/photos, server-rendered Markdown, and a pixel-faithful port of the warm typography-first design.

**Architecture:** Classic Phoenix controllers + HEEx (dead views) so real `<a href>` navigation triggers native cross-document view transitions. Domain logic lives in contexts (`Newton.Blog`, `Newton.Reading`, `Newton.Gallery`, `Newton.Feed`). Posts store Markdown rendered to cached HTML on write via MDEx. Postgres (the scaffold default); images served from a configurable local root (Fly volume) via a `/media` static plug. Decorative JS (ripple canvas, photo masonry, lightbox) ports to LiveView Hooks that run on dead pages without a socket.

**Tech Stack:** Phoenix 1.8, LiveView 1.1 (hooks only), Ecto + Postgres (`postgrex`, scaffold default), MDEx 0.12 (Lumis highlighter), Tailwind v4 + daisyUI (retained for future admin, unused publicly), esbuild, Lora (Google Fonts).

**Spec:** `docs/superpowers/specs/2026-05-18-static-site-to-phoenix-migration-design.md`

**Prototype source (this machine):** `/Users/james/code/website-template-ideation/` — referenced as `$PROTO` below. Contains `styles.css`, `ripple.js`, and the page/post HTML the seeds transcribe.

---

## File Structure

**Config / deps**
- `mix.exs` — add `mdex` (Postgres/`postgrex` stays as scaffolded).
- `config/config.exs` — `:media` root, MDEx not configured here.
- `config/prod.exs` — media root override.
- Repo/DB config is the unchanged Phoenix Postgres scaffold.

**Contexts (`lib/newton/`)**
- `blog.ex` — posts API + `Post` queries.
- `blog/post.ex` — `Post` schema + changeset render pipeline.
- `markdown.ex` — MDEx wrapper (`to_html/1`, `excerpt/1`, `reading_time/1`).
- `reading.ex` — reading entries API + `verb/1`.
- `reading/entry.ex` — `ReadingEntry` schema.
- `gallery.ex` — photo groups/photos API + `image_url/1`.
- `gallery/photo_group.ex`, `gallery/photo.ex` — schemas.
- `feed.ex` — merged home-feed query.

**Web (`lib/newton_web/`)**
- `components/layouts/root.html.heex` — ported `<head>` + body.
- `components/layouts.ex` — `app/1` wrapper, `site_header/1`.
- `components/site_components.ex` — `site_nav`, `section_label`, `meta_line`, `feed`, `feed_item`, `post_article`, `reading_list`, `photo_group`.
- `controllers/page_controller.ex` + `page_html/` — home, resume.
- `controllers/post_controller.ex` + `post_html/` — index, show.
- `controllers/reading_controller.ex` + `reading_html/`.
- `controllers/photo_controller.ex` + `photo_html/`.
- `plugs/media_static.ex` — `/media` Plug.Static wrapper (or inline in endpoint).
- `router.ex` — routes.
- `endpoint.ex` — `/media` static plug.

**Assets (`assets/`)**
- `css/app.css` — `@import "./site.css"` at top.
- `css/site.css` — ported design tokens + all prototype CSS + syntax-highlight map.
- `js/hooks/ripple_canvas.js`, `js/hooks/photo_masonry.js`, `js/hooks/photo_lightbox.js`.
- `js/app.js` — register hooks.

**Tasks**
- `lib/mix/tasks/newton.posts.rerender.ex`.

**Seeds**
- `priv/repo/seeds.exs`.

---

## Conventions for every task

- Run tests with `mix test`. Postgres + `Ecto.Adapters.SQL.Sandbox` supports async cases; the scaffold's `DataCase`/`ConnCase` already handle this.
- After a green test, `mix precommit` (compile-warnings-as-errors, format, test) before committing where practical.
- Commit messages end with the Co-Authored-By trailer this repo uses.
- Browser-observable changes: verify by running `mix phx.server` and loading the page, not by asking the user.

---

## Task 1: Verify the Postgres baseline

The app keeps the Phoenix Postgres scaffold (`postgrex`, `Ecto.Adapters.Postgres`) unchanged. This task is a baseline check before feature work; no code changes.

**Files:** none (verification only).

- [ ] **Step 1: Fetch deps and create the database**

Run: `mix deps.get && mix ecto.create`
Expected: compiles; prints that the database for `Newton.Repo` was created (or already exists). Requires a running local Postgres reachable with the scaffold's dev credentials. If Postgres is not running/reachable, STOP and report BLOCKED with the exact error.

- [ ] **Step 2: Verify the app boots and tests pass**

Run: `mix test`
Expected: the scaffold test(s) pass, no compile errors.

- [ ] **Step 3: No commit**

Nothing changed; do not create a commit.

---

## Task 2: Add MDEx and the Markdown module

**Files:**
- Modify: `mix.exs` (deps)
- Create: `lib/newton/markdown.ex`
- Test: `test/newton/markdown_test.exs`

- [ ] **Step 1: Add the MDEx dependency**

In `mix.exs` `defp deps`, add after the `{:jason, ...}` line:

```elixir
      {:mdex, "~> 0.12"},
```

Run: `mix deps.get`
Expected: fetches `mdex` (and native `lumis`/`comrak` artifacts).

- [ ] **Step 2: Write failing tests for the Markdown module**

Create `test/newton/markdown_test.exs`:

```elixir
defmodule Newton.MarkdownTest do
  use ExUnit.Case, async: true
  alias Newton.Markdown

  test "to_html renders GFM tables" do
    md = "| A | B |\n|---|---|\n| 1 | 2 |"
    html = Markdown.to_html(md)
    assert html =~ "<table>"
    assert html =~ "<td>1</td>"
  end

  test "to_html highlights fenced code with language class output" do
    md = "```elixir\ndefmodule Foo do\nend\n```"
    html = Markdown.to_html(md)
    assert html =~ "<pre"
    assert html =~ "defmodule"
  end

  test "to_html escapes raw HTML by default (unsafe disabled)" do
    html = Markdown.to_html("<script>alert(1)</script>")
    refute html =~ "<script>"
  end

  test "excerpt takes the first paragraph as plain text, truncated" do
    md = "First paragraph with **bold** text that goes on.\n\nSecond paragraph."
    excerpt = Markdown.excerpt(md)
    assert excerpt =~ "First paragraph with bold text"
    refute excerpt =~ "**"
    refute excerpt =~ "Second paragraph"
  end

  test "excerpt truncates very long first paragraphs with an ellipsis" do
    long = String.duplicate("word ", 80)
    excerpt = Markdown.excerpt(long)
    assert String.length(excerpt) <= 205
    assert String.ends_with?(excerpt, "…")
  end

  test "reading_time returns whole minutes, minimum 1" do
    assert Markdown.reading_time("just a few words") == 1
    assert Markdown.reading_time(String.duplicate("word ", 400)) == 2
  end
end
```

- [ ] **Step 3: Run the tests to confirm they fail**

Run: `mix test test/newton/markdown_test.exs`
Expected: FAIL with `Newton.Markdown is not available` / `function ... is undefined`.

- [ ] **Step 4: Implement the Markdown module**

Create `lib/newton/markdown.ex`:

```elixir
defmodule Newton.Markdown do
  @moduledoc """
  Server-side Markdown rendering via MDEx (Lumis highlighter), plus excerpt
  and reading-time derivation. Output uses CSS classes (the `:html_linked`
  formatter) so the warm light/dark syntax palette is driven by `--syntax-*`
  tokens in `assets/css/site.css`.
  """

  @words_per_minute 200
  @excerpt_max 200

  @extension [
    table: true,
    strikethrough: true,
    autolink: true,
    tasklist: true,
    footnotes: true
  ]

  @doc "Render Markdown to highlighted, escape-safe HTML."
  def to_html(markdown) when is_binary(markdown) do
    MDEx.to_html!(markdown,
      extension: @extension,
      render: [unsafe: false],
      syntax_highlight: [engine: :lumis, opts: [formatter: :html_linked]]
    )
  end

  @doc "Plain-text excerpt from the first paragraph, truncated at a word boundary."
  def excerpt(markdown) when is_binary(markdown) do
    markdown
    |> first_paragraph()
    |> strip_markdown()
    |> truncate(@excerpt_max)
  end

  @doc "Estimated reading time in whole minutes (minimum 1)."
  def reading_time(markdown) when is_binary(markdown) do
    words =
      markdown
      |> String.split(~r/\s+/, trim: true)
      |> length()

    max(1, ceil(words / @words_per_minute))
  end

  defp first_paragraph(markdown) do
    markdown
    |> String.split(~r/\n\s*\n/, parts: 2)
    |> List.first()
    |> String.trim()
  end

  # Strip the Markdown syntax we actually use in bodies to recover plain text.
  defp strip_markdown(text) do
    text
    |> String.replace(~r/!?\[([^\]]*)\]\([^)]*\)/, "\\1")
    |> String.replace(~r/[*_`#>]/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp truncate(text, max) when byte_size(text) <= max, do: text

  defp truncate(text, max) do
    text
    |> binary_part(0, max)
    |> String.replace(~r/\s+\S*$/, "")
    |> Kernel.<>("…")
  end
end
```

- [ ] **Step 5: Run the tests to confirm they pass**

Run: `mix test test/newton/markdown_test.exs`
Expected: PASS (all 6 tests).

If `formatter: :html_linked` raises an "unknown formatter" error, change it to `formatter: {:html_linked, []}` and re-run. Record whichever form works — Task 11 depends on this formatter emitting CSS classes.

- [ ] **Step 6: Commit**

```bash
git add mix.exs mix.lock lib/newton/markdown.ex test/newton/markdown_test.exs
git commit -m "Add MDEx-backed Markdown rendering module"
```

---

## Task 2.5: Shared slug helper

**Files:**
- Create: `lib/newton/slug.ex`
- Test: `test/newton/slug_test.exs`

Defined early because Reading (Task 12) and the home feed (Task 17) both anchor-link by slugified title.

- [ ] **Step 1: Failing test**

Create `test/newton/slug_test.exs`:

```elixir
defmodule Newton.SlugTest do
  use ExUnit.Case, async: true

  test "slugifies titles" do
    assert Newton.Slug.slugify("A Philosophy of Software Design") == "a-philosophy-of-software-design"
    assert Newton.Slug.slugify("Eastern Sierra!") == "eastern-sierra"
  end
end
```

- [ ] **Step 2: Run, confirm fail**

Run: `mix test test/newton/slug_test.exs` → FAIL.

- [ ] **Step 3: Implement**

Create `lib/newton/slug.ex`:

```elixir
defmodule Newton.Slug do
  @moduledoc "Deterministic slugs from titles."
  def slugify(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end
end
```

- [ ] **Step 4: Tests pass**

Run: `mix test test/newton/slug_test.exs` → PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/newton/slug.ex test/newton/slug_test.exs
git commit -m "Add shared Slug helper"
```

---

## Task 3: Port design tokens and base CSS

**Files:**
- Create: `assets/css/site.css`
- Modify: `assets/css/app.css`

- [ ] **Step 1: Create site.css from the prototype stylesheet**

Copy the **entire** contents of `$PROTO/styles.css` into a new file `assets/css/site.css` **except** the syntax-highlighting block (the `.post-body pre code.hljs` rule through the `.hljs-comment` rule). That block is re-added, reconciled to MDEx output, in Task 11. Everything else — token `:root` blocks, dark triggers, `@view-transition`, scrollbars, reset, base, canvas, skip-link, header, containers, typography, links, feed, photos, lightbox, resume — is copied verbatim.

(The full source is at `$PROTO/styles.css`; it is the source of truth. Do not paraphrase it.)

- [ ] **Step 2: Import site.css from app.css**

At the very top of `assets/css/app.css`, **above** the `@import "tailwindcss"` line, add:

```css
@import "./site.css";
```

This keeps the prototype's plain-CSS design system authoritative for the public site; Tailwind/daisyUI remain below it for future admin use.

- [ ] **Step 3: Build assets and verify no CSS errors**

Run: `mix assets.build`
Expected: completes without Tailwind/lightningcss errors; `priv/static/assets/css/app.css` contains `--bg: #aa4040`.

Verify: `grep -c "aa4040" priv/static/assets/css/app.css` → at least 1.

- [ ] **Step 4: Commit**

```bash
git add assets/css/site.css assets/css/app.css
git commit -m "Port prototype design tokens and base styles into site.css"
```

---

## Task 4: Port the root layout and app wrapper

**Files:**
- Modify: `lib/newton_web/components/layouts/root.html.heex`
- Modify: `lib/newton_web/components/layouts.ex`

- [ ] **Step 1: Replace the root layout**

Overwrite `lib/newton_web/components/layouts/root.html.heex` with the ported head (theme-color, Lora, scheme script) and the ripple canvas + skip link:

```heex
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="csrf-token" content={get_csrf_token()} />
    <meta name="theme-color" content="#aa4040" media="(prefers-color-scheme: light)" />
    <meta name="theme-color" content="#151311" media="(prefers-color-scheme: dark)" />
    <.live_title default="James Newton">{assigns[:page_title]}</.live_title>
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
    <link
      rel="stylesheet"
      href="https://fonts.googleapis.com/css2?family=Lora:ital,wght@0,400;0,600;1,400;1,600&display=swap"
    />
    <link phx-track-static rel="stylesheet" href={~p"/assets/css/app.css"} />
    <script defer phx-track-static type="text/javascript" src={~p"/assets/js/app.js"}>
    </script>
    <script>
      (() => {
        const mq = window.matchMedia('(prefers-color-scheme: dark)');
        const applyScheme = (e) => document.documentElement.classList.toggle('dark', e.matches);
        applyScheme(mq);
        mq.addEventListener('change', applyScheme);
      })();
    </script>
  </head>
  <body>
    <a class="skip-link" href="#main">Skip to content</a>
    <canvas class="ripple-canvas" id="rippleCanvas" phx-hook="RippleCanvas" aria-hidden="true">
    </canvas>
    {@inner_content}
  </body>
</html>
```

- [ ] **Step 2: Replace the app layout and add the site header**

In `lib/newton_web/components/layouts.ex`, replace the `app/1` function, the `flash_group/1` function body usage, and the `theme_toggle/1` function. Replace the whole module body below `embed_templates "layouts/*"` with:

```elixir
  @doc "The site header used on every page."
  attr :wide, :boolean, default: false

  def site_header(assigns) do
    ~H"""
    <header class={["site-header", @wide && "site-header--wide"]}>
      <a href={~p"/"} class="site-name">James Newton</a>
    </header>
    """
  end

  @doc """
  The app layout. Wraps page content; `inner_block` is rendered inside `<main>`.
  Set `wide` for the photos page (wider container).
  """
  attr :flash, :map, default: %{}
  attr :wide, :boolean, default: false
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <.site_header wide={@wide} />
    <main id="main">
      {render_slot(@inner_block)}
    </main>
    <.flash_group flash={@flash} />
    """
  end

  @doc "Shows the flash group with standard titles and content."
  attr :flash, :map, required: true
  attr :id, :string, default: "flash-group"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
    </div>
    """
  end
```

(The `app/1` layout no longer renders the daisyUI navbar or `theme_toggle`. daisyUI stays installed for future admin use.)

Note: `.site-header--wide` is not in the prototype CSS, which instead uses `body:has(.post.photos) .site-header`. Keep using the prototype's `body:has(...)` selector — so in this layout the `wide` flag on `site_header` can be ignored for styling, but pass it through for clarity. If you prefer, drop the `wide` attr from `site_header` entirely and rely solely on the `body:has(.post.photos)` rule (the photos template sets `.post.photos`). **Decision: drop the `wide` handling from `site_header`** — delete the `class={[...]}` and use `class="site-header"`, and remove `attr :wide` from `site_header`. Keep `wide` only as an unused passthrough on `app/1` removed too. Simplify `app/1` to not take `wide`.

Apply that simplification: `site_header/1` takes no attrs and renders `class="site-header"`; `app/1` takes only `flash`.

- [ ] **Step 3: Verify it compiles**

Run: `mix compile --warnings-as-errors`
Expected: compiles clean. (The home page still renders the scaffold template until Task 14; that's fine.)

- [ ] **Step 4: Commit**

```bash
git add lib/newton_web/components/layouts/root.html.heex lib/newton_web/components/layouts.ex
git commit -m "Port root layout, site header, and app wrapper from prototype"
```

---

## Task 5: Site components (nav, labels, meta)

**Files:**
- Create: `lib/newton_web/components/site_components.ex`
- Modify: `lib/newton_web.ex` (import the new components into `html_helpers`)

- [ ] **Step 1: Create the shared component module**

Create `lib/newton_web/components/site_components.ex`:

```elixir
defmodule NewtonWeb.SiteComponents do
  @moduledoc "Function components built from the prototype's component language."
  use Phoenix.Component
  use NewtonWeb, :verified_routes

  @doc "Primary middot-separated nav."
  def site_nav(assigns) do
    ~H"""
    <nav class="site-nav" aria-label="Primary">
      <a href={~p"/posts"}>Posts</a>
      <span class="site-nav-sep" aria-hidden="true">·</span>
      <a href={~p"/photos"}>Photos</a>
      <span class="site-nav-sep" aria-hidden="true">·</span>
      <a href={~p"/reading"}>Reading</a>
      <span class="site-nav-sep" aria-hidden="true">·</span>
      <a href={~p"/resume"}>Resume</a>
    </nav>
    """
  end
end
```

- [ ] **Step 2: Import the module into HTML helpers**

In `lib/newton_web.ex`, inside `defp html_helpers do ... quote do`, add after `import NewtonWeb.CoreComponents`:

```elixir
      import NewtonWeb.SiteComponents
```

- [ ] **Step 3: Verify compile**

Run: `mix compile --warnings-as-errors`
Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add lib/newton_web/components/site_components.ex lib/newton_web.ex
git commit -m "Add site_nav component and wire SiteComponents into helpers"
```

---

## Task 6: Résumé page (first end-to-end page, no DB)

**Files:**
- Modify: `lib/newton_web/controllers/page_controller.ex`
- Create: `lib/newton_web/controllers/page_html/resume.html.heex`
- Modify: `lib/newton_web/router.ex`
- Test: `test/newton_web/controllers/page_controller_test.exs`

- [ ] **Step 1: Write a failing controller test**

Replace `test/newton_web/controllers/page_controller_test.exs` with:

```elixir
defmodule NewtonWeb.PageControllerTest do
  use NewtonWeb.ConnCase

  test "GET /resume renders the résumé", %{conn: conn} do
    conn = get(conn, ~p"/resume")
    html = html_response(conn, 200)
    assert html =~ "Mark OS"
    assert html =~ "What I'm doing"
  end
end
```

- [ ] **Step 2: Run it to confirm failure**

Run: `mix test test/newton_web/controllers/page_controller_test.exs`
Expected: FAIL (no `/resume` route).

- [ ] **Step 3: Add the route**

In `lib/newton_web/router.ex`, in the `scope "/", NewtonWeb` block, add under the existing `get "/", PageController, :home`:

```elixir
    get "/resume", PageController, :resume
```

- [ ] **Step 4: Add the controller action**

In `lib/newton_web/controllers/page_controller.ex`, add:

```elixir
  def resume(conn, _params) do
    render(conn, :resume, page_title: "Resume")
  end
```

- [ ] **Step 5: Create the résumé template**

Create `lib/newton_web/controllers/page_html/resume.html.heex` by transcribing `$PROTO/resume.html`'s `<article class="post">` into the app layout. Wrap with `<Layouts.app flash={@flash}>`:

```heex
<Layouts.app flash={@flash}>
  <article class="post">
    <header>
      <h1 class="post-title">Resume</h1>
    </header>

    <section class="post-body">
      <h2>What I'm doing</h2>

      <div class="resume-job">
        <h3 class="resume-job-company">Mark OS</h3>
        <p class="resume-job-meta">2025 — Present · Founding Engineer</p>
        <p>
          <a href="https://markos.ai">Mark OS</a> is an AI-powered content review platform
          that helps marketing teams evaluate their creative work — digital ads, videos,
          product pages, and campaigns — for brand consistency, compliance, and performance,
          before and after launch.
        </p>
        <p>I work across the stack as we build the platform from the ground up.</p>
      </div>

      <h2>What I've done</h2>
      <!-- Transcribe the remaining .resume-job blocks (Shopify, ShareGrid, IZEA,
           Code School, Chargify, CYber SYtes), the "Other Projects" h2 with
           WhatPulse and GitLab, and the final .resume-contact paragraph,
           verbatim from $PROTO/resume.html. Replace `&middot;` with `·`. -->
      <p class="resume-contact"><a href="mailto:hello@jamesnewton.com">Email me today →</a></p>
    </section>
  </article>
</Layouts.app>
```

Transcribe the omitted blocks faithfully from `$PROTO/resume.html`. Ensure `PageHTML` (`lib/newton_web/controllers/page_html.ex`) embeds templates from `page_html/` (the scaffold already does via `embed_templates`).

- [ ] **Step 6: Confirm the test passes**

Run: `mix test test/newton_web/controllers/page_controller_test.exs`
Expected: PASS.

- [ ] **Step 7: Visually verify**

Run `mix phx.server`, open `http://localhost:4000/resume`. Confirm: cream-on-terracotta palette, Lora serif, ripple canvas behind content, header "James Newton" links home. Stop the server.

- [ ] **Step 8: Commit**

```bash
git add lib/newton_web/controllers/page_controller.ex lib/newton_web/controllers/page_html/resume.html.heex lib/newton_web/router.ex test/newton_web/controllers/page_controller_test.exs
git commit -m "Add résumé page on ported layout"
```

---

## Task 7: Ripple canvas hook

**Files:**
- Create: `assets/js/hooks/ripple_canvas.js`
- Modify: `assets/js/app.js`

- [ ] **Step 1: Port ripple.js into a hook**

Create `assets/js/hooks/ripple_canvas.js`. Wrap the prototype IIFE body (`$PROTO/ripple.js`) as a hook. Key changes: target `this.el` instead of `document.getElementById('rippleCanvas')`; store the `resize`/`keydown` listeners and the RAF id on `this` so `destroyed()` can remove them.

```js
// Ported from the prototype ripple.js — a dot-matrix canvas with an expanding
// ripple and a Konami "bloom" mode. Logic is unchanged; lifecycle is managed by
// the LiveView hook so it cleans up on navigation.
export const RippleCanvas = {
  mounted() {
    const canvas = this.el;
    const ctx = canvas.getContext("2d");

    const DOT_SPACING = 20, DOT_RADIUS = 1.5, BASE_OPACITY = 0.06;
    const RIPPLE_PEAK_OPACITY = 0.3, CYCLE_DURATION = 8000, RIPPLE_WIDTH = 150;
    const BLOOM_SIGMA = 140, BLOOM_DURATION = 3600, BLOOM_SPAWN_INTERVAL = 720;
    const BLOOM_BASE_ALPHA = 0.18, BLOOM_PEAK_ALPHA = 1;

    let width, height, cols, rows, maxDist;
    const ripples = [];
    const blooms = [];
    let lastBloomSpawn = -Infinity;
    let konamiMode = false;
    const KONAMI_SEQUENCE = ["ArrowUp","ArrowUp","ArrowDown","ArrowDown","ArrowLeft","ArrowRight","ArrowLeft","ArrowRight","b","a"];
    let konamiProgress = 0;

    const resize = () => {
      width = canvas.width = window.innerWidth;
      height = canvas.height = window.innerHeight;
      cols = Math.ceil(width / DOT_SPACING) + 1;
      rows = Math.ceil(height / DOT_SPACING) + 1;
      maxDist = Math.sqrt(width * width + height * height);
    };
    const spawnRipple = (t) => ripples.push({ originX: Math.random()*width, originY: Math.random()*height, startTime: t });
    const spawnBloom = (t) => { blooms.push({ centerX: Math.random()*width, centerY: Math.random()*height, startTime: t }); lastBloomSpawn = t; };

    const draw = (timestamp) => {
      const style = getComputedStyle(document.documentElement);
      const bg = style.getPropertyValue("--bg").trim();
      const dot = style.getPropertyValue("--dot").trim();
      const baseOpacity = parseFloat(style.getPropertyValue("--dot-base-opacity").trim()) || BASE_OPACITY;
      const ripplePeakOpacity = parseFloat(style.getPropertyValue("--ripple-peak-opacity").trim()) || RIPPLE_PEAK_OPACITY;

      ctx.clearRect(0, 0, width, height);
      ctx.fillStyle = bg;
      ctx.fillRect(0, 0, width, height);

      if (konamiMode) {
        for (let i = blooms.length - 1; i >= 0; i--) {
          if (timestamp - blooms[i].startTime >= BLOOM_DURATION) blooms.splice(i, 1);
        }
        if (timestamp - lastBloomSpawn >= BLOOM_SPAWN_INTERVAL) spawnBloom(timestamp);
        const activeBlooms = blooms.map((b) => {
          const t01 = (timestamp - b.startTime) / BLOOM_DURATION;
          const s = Math.sin(Math.PI * t01);
          return { x: b.centerX, y: b.centerY, intensity: s * s };
        });
        const bloomSigmaSq2 = 2 * BLOOM_SIGMA * BLOOM_SIGMA;
        const bloomCutoffSq = (BLOOM_SIGMA * 3) * (BLOOM_SIGMA * 3);
        const alphaSpan = BLOOM_PEAK_ALPHA - BLOOM_BASE_ALPHA;
        for (let row = 0; row < rows; row++) {
          for (let col = 0; col < cols; col++) {
            const x = col * DOT_SPACING, y = row * DOT_SPACING;
            let boost = 0;
            for (const b of activeBlooms) {
              const dx = x - b.x, dy = y - b.y, distSq = dx*dx + dy*dy;
              if (distSq > bloomCutoffSq) continue;
              boost += b.intensity * Math.exp(-distSq / bloomSigmaSq2);
            }
            if (boost > 1) boost = 1;
            const alpha = BLOOM_BASE_ALPHA + alphaSpan * boost;
            const hue = (col * 47 + row * 137) % 360;
            ctx.beginPath();
            ctx.arc(x, y, DOT_RADIUS, 0, Math.PI * 2);
            ctx.fillStyle = `hsla(${hue}, 90%, 60%, ${alpha})`;
            ctx.fill();
          }
        }
      } else {
        for (let i = ripples.length - 1; i >= 0; i--) {
          if ((timestamp - ripples[i].startTime) / CYCLE_DURATION >= 1) ripples.splice(i, 1);
        }
        if (ripples.length === 0) spawnRipple(timestamp);
        const active = ripples.map((r) => ({
          originX: r.originX, originY: r.originY,
          rippleRadius: Math.min((timestamp - r.startTime) / CYCLE_DURATION, 1) * (maxDist + RIPPLE_WIDTH),
        }));
        const sigmaSq2 = 2 * (RIPPLE_WIDTH / 3) * (RIPPLE_WIDTH / 3);
        const halfWidth = RIPPLE_WIDTH / 2;
        for (let row = 0; row < rows; row++) {
          for (let col = 0; col < cols; col++) {
            const x = col * DOT_SPACING, y = row * DOT_SPACING;
            let totalEffect = 0, behindAny = false;
            for (const r of active) {
              const dx = x - r.originX, dy = y - r.originY, dist = Math.sqrt(dx*dx + dy*dy);
              if (dist > r.rippleRadius + halfWidth) continue;
              behindAny = true;
              const distFromRing = Math.abs(dist - r.rippleRadius);
              totalEffect += Math.exp(-(distFromRing * distFromRing) / sigmaSq2);
            }
            const combinedEffect = totalEffect > 1 ? 1 : totalEffect;
            const opacity = behindAny ? baseOpacity + (ripplePeakOpacity - baseOpacity) * combinedEffect : baseOpacity;
            ctx.beginPath();
            ctx.arc(x, y, DOT_RADIUS, 0, Math.PI * 2);
            ctx.fillStyle = `rgba(${dot}, ${opacity})`;
            ctx.fill();
          }
        }
      }
      this._raf = requestAnimationFrame(draw);
    };

    this._onKonami = (event) => {
      const key = event.key.length === 1 ? event.key.toLowerCase() : event.key;
      const expected = KONAMI_SEQUENCE[konamiProgress];
      if (key === expected) {
        konamiProgress++;
        if (konamiProgress === KONAMI_SEQUENCE.length) {
          konamiMode = !konamiMode;
          konamiProgress = 0;
          if (konamiMode) { blooms.length = 0; lastBloomSpawn = -Infinity; }
        }
      } else {
        konamiProgress = key === KONAMI_SEQUENCE[0] ? 1 : 0;
      }
    };
    this._onResize = resize;

    window.addEventListener("resize", this._onResize);
    window.addEventListener("keydown", this._onKonami);
    resize();
    this._raf = requestAnimationFrame(draw);
  },

  destroyed() {
    cancelAnimationFrame(this._raf);
    window.removeEventListener("resize", this._onResize);
    window.removeEventListener("keydown", this._onKonami);
  },
};
```

- [ ] **Step 2: Register the hook in app.js**

In `assets/js/app.js`, add an import after the `topbar` import:

```js
import {RippleCanvas} from "./hooks/ripple_canvas"
```

And change the `hooks:` option of the `LiveSocket` constructor to:

```js
  hooks: {...colocatedHooks, RippleCanvas},
```

- [ ] **Step 3: Build and verify**

Run: `mix assets.build`
Expected: esbuild bundles without error.

Run `mix phx.server`, open `/resume`. Confirm the dot-matrix ripple animates behind the content and re-renders on window resize. Stop the server.

- [ ] **Step 4: Commit**

```bash
git add assets/js/hooks/ripple_canvas.js assets/js/app.js
git commit -m "Port ripple canvas as a LiveView hook"
```

---

## Task 8: Posts migration, schema, and render pipeline

**Files:**
- Create: `priv/repo/migrations/<ts>_create_posts.exs`
- Create: `lib/newton/blog/post.ex`
- Create: `lib/newton/blog.ex`
- Test: `test/newton/blog_test.exs`

- [ ] **Step 1: Generate the migration**

Run: `mix ecto.gen.migration create_posts`
Then replace the generated file body with:

```elixir
defmodule Newton.Repo.Migrations.CreatePosts do
  use Ecto.Migration

  def change do
    create table(:posts) do
      add :slug, :string, null: false
      add :title, :string, null: false
      add :excerpt, :string
      add :body_markdown, :text, null: false
      add :body_html, :text, null: false
      add :reading_time, :integer
      add :published_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:posts, [:slug])
    create index(:posts, [:published_at])
  end
end
```

Run: `mix ecto.migrate`
Expected: creates the `posts` table.

- [ ] **Step 2: Write failing context tests**

Create `test/newton/blog_test.exs`:

```elixir
defmodule Newton.BlogTest do
  use Newton.DataCase
  alias Newton.Blog

  @valid %{
    slug: "hello-world",
    title: "Hello World",
    body_markdown: "First paragraph here.\n\n## Heading\n\nMore text.",
    published_at: ~U[2026-01-01 00:00:00Z]
  }

  test "create_post renders body_html, derives excerpt and reading_time" do
    {:ok, post} = Blog.create_post(@valid)
    assert post.body_html =~ "<h2"
    assert post.excerpt =~ "First paragraph here"
    assert post.reading_time >= 1
  end

  test "create_post keeps an explicit excerpt" do
    {:ok, post} = Blog.create_post(Map.put(@valid, :excerpt, "Custom excerpt"))
    assert post.excerpt == "Custom excerpt"
  end

  test "create_post requires slug, title, body_markdown" do
    {:error, changeset} = Blog.create_post(%{})
    assert %{slug: _, title: _, body_markdown: _} = errors_on(changeset)
  end

  test "slug must be unique" do
    {:ok, _} = Blog.create_post(@valid)
    {:error, changeset} = Blog.create_post(@valid)
    assert "has already been taken" in errors_on(changeset).slug
  end

  test "list_published_posts returns only past, published posts newest-first" do
    {:ok, _draft} = Blog.create_post(%{@valid | slug: "draft", published_at: nil})
    {:ok, _future} = Blog.create_post(%{@valid | slug: "future", published_at: ~U[2999-01-01 00:00:00Z]})
    {:ok, older} = Blog.create_post(%{@valid | slug: "older", published_at: ~U[2026-01-01 00:00:00Z]})
    {:ok, newer} = Blog.create_post(%{@valid | slug: "newer", published_at: ~U[2026-02-01 00:00:00Z]})

    slugs = Blog.list_published_posts() |> Enum.map(& &1.slug)
    assert slugs == ["newer", "older"]
  end

  test "get_published_post!/1 fetches by slug and raises on miss" do
    {:ok, post} = Blog.create_post(@valid)
    assert Blog.get_published_post!("hello-world").id == post.id
    assert_raise Ecto.NoResultsError, fn -> Blog.get_published_post!("nope") end
  end
end
```

- [ ] **Step 3: Run to confirm failure**

Run: `mix test test/newton/blog_test.exs`
Expected: FAIL (`Newton.Blog` undefined).

- [ ] **Step 4: Implement the Post schema with the render pipeline**

Create `lib/newton/blog/post.ex`:

```elixir
defmodule Newton.Blog.Post do
  use Ecto.Schema
  import Ecto.Changeset
  alias Newton.Markdown

  schema "posts" do
    field :slug, :string
    field :title, :string
    field :excerpt, :string
    field :body_markdown, :string
    field :body_html, :string
    field :reading_time, :integer
    field :published_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(post, attrs) do
    post
    |> cast(attrs, [:slug, :title, :excerpt, :body_markdown, :published_at])
    |> validate_required([:slug, :title, :body_markdown])
    |> unique_constraint(:slug)
    |> render_derived_fields()
  end

  # Render body_html, excerpt, and reading_time from body_markdown whenever the
  # markdown is present and valid in the changeset.
  defp render_derived_fields(%Ecto.Changeset{valid?: true} = changeset) do
    case fetch_change(changeset, :body_markdown) do
      {:ok, markdown} ->
        changeset
        |> put_change(:body_html, Markdown.to_html(markdown))
        |> put_change(:reading_time, Markdown.reading_time(markdown))
        |> maybe_put_excerpt(markdown)

      :error ->
        changeset
    end
  end

  defp render_derived_fields(changeset), do: changeset

  defp maybe_put_excerpt(changeset, markdown) do
    case get_field(changeset, :excerpt) do
      nil -> put_change(changeset, :excerpt, Markdown.excerpt(markdown))
      "" -> put_change(changeset, :excerpt, Markdown.excerpt(markdown))
      _present -> changeset
    end
  end
end
```

- [ ] **Step 5: Implement the Blog context**

Create `lib/newton/blog.ex`:

```elixir
defmodule Newton.Blog do
  @moduledoc "The blog context: posts and their queries."
  import Ecto.Query, warn: false
  alias Newton.Repo
  alias Newton.Blog.Post

  def create_post(attrs) do
    %Post{} |> Post.changeset(attrs) |> Repo.insert()
  end

  def update_post(%Post{} = post, attrs) do
    post |> Post.changeset(attrs) |> Repo.update()
  end

  def list_published_posts do
    Repo.all(published_query())
  end

  def get_published_post!(slug) do
    Repo.one!(from p in published_query(), where: p.slug == ^slug)
  end

  def list_posts, do: Repo.all(from p in Post, order_by: [desc: p.published_at])

  defp published_query do
    now = DateTime.utc_now()

    from p in Post,
      where: not is_nil(p.published_at) and p.published_at <= ^now,
      order_by: [desc: p.published_at]
  end
end
```

- [ ] **Step 6: Run tests to confirm pass**

Run: `mix test test/newton/blog_test.exs`
Expected: PASS (all tests).

- [ ] **Step 7: Commit**

```bash
git add priv/repo/migrations lib/newton/blog.ex lib/newton/blog/post.ex test/newton/blog_test.exs
git commit -m "Add Post schema, render pipeline, and Blog context"
```

---

## Task 9: Posts index page

**Files:**
- Create: `lib/newton_web/controllers/post_controller.ex`
- Create: `lib/newton_web/controllers/post_html.ex`
- Create: `lib/newton_web/controllers/post_html/index.html.heex`
- Modify: `lib/newton_web/components/site_components.ex` (add `feed`, `feed_item`)
- Modify: `lib/newton_web/router.ex`
- Test: `test/newton_web/controllers/post_controller_test.exs`

- [ ] **Step 1: Add feed components**

In `lib/newton_web/components/site_components.ex`, add inside the module:

```elixir
  @doc "Feed wrapper with an uppercase heading."
  attr :heading, :string, default: nil
  slot :inner_block, required: true

  def feed(assigns) do
    ~H"""
    <section class="feed">
      <h2 :if={@heading} class="feed-heading">{@heading}</h2>
      {render_slot(@inner_block)}
    </section>
    """
  end

  @doc """
  A single feed entry. `href` makes it a link; omit for a static block.
  `date` is a preformatted date string. Variants: nil (post), "book", "photo".
  """
  attr :href, :string, default: nil
  attr :id, :string, default: nil
  attr :date, :string, default: nil
  attr :variant, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def feed_item(assigns) do
    assigns = assign(assigns, :class, ["feed-item", @variant && "feed-item--#{@variant}"])

    ~H"""
    <.dynamic_tag :if={@href} tag_name="a" href={@href} id={@id} class={@class} {@rest}>
      <time :if={@date} class="feed-item-date">{@date}</time>
      {render_slot(@inner_block)}
    </.dynamic_tag>
    <div :if={!@href} id={@id} class={@class} {@rest}>
      <time :if={@date} class="feed-item-date">{@date}</time>
      {render_slot(@inner_block)}
    </div>
    """
  end
```

(`dynamic_tag` is built into Phoenix.Component. If your Phoenix version warns on `dynamic_tag` usage, replace the link branch with a literal `<a>` element.)

- [ ] **Step 2: Write a failing controller test**

Create `test/newton_web/controllers/post_controller_test.exs`:

```elixir
defmodule NewtonWeb.PostControllerTest do
  use NewtonWeb.ConnCase
  alias Newton.Blog

  setup do
    {:ok, post} =
      Blog.create_post(%{
        slug: "three-ways-to-retry",
        title: "Three Ways to Retry",
        body_markdown: "Retry logic is one of those small utilities.\n\n## The problem\n\nText.",
        published_at: ~U[2026-04-17 00:00:00Z]
      })

    %{post: post}
  end

  test "GET /posts lists published posts", %{conn: conn} do
    html = conn |> get(~p"/posts") |> html_response(200)
    assert html =~ "Three Ways to Retry"
    assert html =~ ~p"/posts/three-ways-to-retry"
  end
end
```

- [ ] **Step 3: Run to confirm failure**

Run: `mix test test/newton_web/controllers/post_controller_test.exs`
Expected: FAIL (no `/posts` route).

- [ ] **Step 4: Add routes**

In `router.ex` add to the `scope "/"`:

```elixir
    get "/posts", PostController, :index
    get "/posts/:slug", PostController, :show
```

- [ ] **Step 5: Add the controller and HTML module**

Create `lib/newton_web/controllers/post_controller.ex`:

```elixir
defmodule NewtonWeb.PostController do
  use NewtonWeb, :controller
  alias Newton.Blog

  def index(conn, _params) do
    render(conn, :index, page_title: "Posts", posts: Blog.list_published_posts())
  end

  def show(conn, %{"slug" => slug}) do
    post = Blog.get_published_post!(slug)
    render(conn, :show, page_title: post.title, post: post)
  end
end
```

Create `lib/newton_web/controllers/post_html.ex`:

```elixir
defmodule NewtonWeb.PostHTML do
  use NewtonWeb, :html

  embed_templates "post_html/*"

  @doc "Format a post date like \"April 17, 2026\"."
  def format_date(nil), do: ""
  def format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%B %-d, %Y")
end
```

- [ ] **Step 6: Create the index template**

Create `lib/newton_web/controllers/post_html/index.html.heex`:

```heex
<Layouts.app flash={@flash}>
  <article class="post">
    <header>
      <h1 class="post-title">Posts</h1>
    </header>

    <.feed>
      <.feed_item :for={post <- @posts} href={~p"/posts/#{post.slug}"} date={format_date(post.published_at)}>
        <h2 class="feed-item-title">{post.title}</h2>
        <p class="feed-item-excerpt">{post.excerpt}</p>
      </.feed_item>
    </.feed>
  </article>
</Layouts.app>
```

- [ ] **Step 7: Confirm the test passes**

Run: `mix test test/newton_web/controllers/post_controller_test.exs`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/newton_web/controllers/post_controller.ex lib/newton_web/controllers/post_html.ex lib/newton_web/controllers/post_html/index.html.heex lib/newton_web/components/site_components.ex lib/newton_web/router.ex test/newton_web/controllers/post_controller_test.exs
git commit -m "Add posts index page and feed components"
```

---

## Task 10: Post show page

**Files:**
- Create: `lib/newton_web/controllers/post_html/show.html.heex`
- Test: extend `test/newton_web/controllers/post_controller_test.exs`

- [ ] **Step 1: Add failing show tests**

Append to `test/newton_web/controllers/post_controller_test.exs` (inside the module):

```elixir
  test "GET /posts/:slug renders the rendered HTML body", %{conn: conn} do
    html = conn |> get(~p"/posts/three-ways-to-retry") |> html_response(200)
    assert html =~ "<h2"
    assert html =~ "The problem"
  end

  test "GET /posts/:slug 404s on unknown slug", %{conn: conn} do
    assert_error_sent 404, fn -> get(conn, ~p"/posts/does-not-exist") end
  end
```

- [ ] **Step 2: Run to confirm failure**

Run: `mix test test/newton_web/controllers/post_controller_test.exs`
Expected: FAIL (no show template).

- [ ] **Step 3: Create the show template**

Create `lib/newton_web/controllers/post_html/show.html.heex`:

```heex
<Layouts.app flash={@flash}>
  <article class="post">
    <header>
      <h1 class="post-title">{@post.title}</h1>
      <p class="post-byline">
        {format_date(@post.published_at)} · {@post.reading_time} min read
      </p>
    </header>

    <section class="post-body">
      {Phoenix.HTML.raw(@post.body_html)}
    </section>
  </article>
</Layouts.app>
```

- [ ] **Step 4: Confirm tests pass**

Run: `mix test test/newton_web/controllers/post_controller_test.exs`
Expected: PASS (all 3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/newton_web/controllers/post_html/show.html.heex test/newton_web/controllers/post_controller_test.exs
git commit -m "Add post show page rendering cached body HTML"
```

---

## Task 11: Reconcile syntax-highlighting CSS to MDEx output

**Files:**
- Modify: `assets/css/site.css`

This task replaces the prototype's `.hljs-*` rules (omitted in Task 3) with rules matching MDEx/Lumis `:html_linked` class output, preserving the warm token palette and light/dark flip.

- [ ] **Step 1: Capture the actual highlighted HTML**

Run in IEx:

```bash
iex -S mix
```

```elixir
Newton.Markdown.to_html("```python\ndef f(x):\n    return x + 1  # comment\n```")
|> IO.puts()
```

Record the exact markup: the class on `<pre>` and `<code>`, whether the language survives (e.g. `class="language-python"` or a `data-lang`/`data-language` attribute), and the per-token class names (keywords, strings, numbers, comments, function/type names). Exit IEx.

- [ ] **Step 2: Adjust the language-badge selectors if needed**

The prototype's `pre:has(code.language-python)::before` rules in `site.css` assume a `language-xxx` class on `<code>`. If MDEx emits the language differently (e.g. `data-lang="python"` on `<pre>`), rewrite those badge rules to match what you observed in Step 1. For example, if the language is on `<pre data-lang="python">`:

```css
.post-body pre[data-lang]::before { content: attr(data-lang); }
```

Replace the per-language `:has(...)` block accordingly. Keep the existing `pre::before` positioning rule (top-right, uppercase, tracked) unchanged.

- [ ] **Step 3: Add the token color map keyed to the design tokens**

At the end of the `/* === Syntax Highlighting === */` section in `site.css`, add rules mapping the **observed** Lumis token classes to the warm tokens. Using the documented Lumis scope classes as the starting point, map them like the prototype's five tiers (adjust class names to match Step 1):

```css
/* Warm-only highlight palette mapped to --syntax-* tokens (flips light/dark).
   Class names below must match the Lumis :html_linked output captured in
   Task 11 Step 1 — adjust selectors to the real emitted classes. */
.post-body pre code { color: inherit; background: transparent; }

/* keywords / storage / meta */
.post-body .keyword,
.post-body .meta,
.post-body .storage { color: var(--syntax-keyword); font-weight: 600; }

/* strings / regex */
.post-body .string,
.post-body .regexp { color: var(--link); }

/* numbers / constants / literals */
.post-body .number,
.post-body .constant,
.post-body .boolean { color: var(--syntax-amber); }

/* types / functions / classes */
.post-body .function,
.post-body .type,
.post-body .class,
.post-body .title { color: var(--syntax-rose); font-style: italic; }

/* comments */
.post-body .comment { color: var(--text-muted); font-style: italic; }
```

If Lumis prefixes classes (e.g. `.ahl-keyword` or a `lumis` namespace), prefix all selectors accordingly to match Step 1. The goal: every token color resolves to a `--syntax-*`/`--link`/`--text-muted` token so it inverts correctly in dark mode.

- [ ] **Step 4: Build and visually verify**

Run: `mix assets.build`
Run `mix phx.server`, open `/posts/three-ways-to-retry` (after seeds, Task 18 — for now use the test post or a temporary `iex` insert). Confirm: code blocks show warm-toned highlighting, a language badge in the top-right, and colors invert under OS dark mode. Stop the server.

- [ ] **Step 5: Update the design doc**

In the migrated copy of `docs/design.md` (carried over in Task 19, or note now for later): change the "Syntax highlighting" entry to describe MDEx/Lumis server-side rendering with `:html_linked` classes instead of highlight.js + `.hljs-*`. If `docs/design.md` is not yet in this repo, record this change to apply during Task 19.

- [ ] **Step 6: Commit**

```bash
git add assets/css/site.css
git commit -m "Reconcile syntax-highlight CSS to MDEx Lumis output"
```

---

## Task 12: Reading context, schema, and page

**Files:**
- Create: `priv/repo/migrations/<ts>_create_reading_entries.exs`
- Create: `lib/newton/reading/entry.ex`
- Create: `lib/newton/reading.ex`
- Create: `lib/newton_web/controllers/reading_controller.ex`
- Create: `lib/newton_web/controllers/reading_html.ex`
- Create: `lib/newton_web/controllers/reading_html/index.html.heex`
- Modify: `lib/newton_web/router.ex`
- Test: `test/newton/reading_test.exs`, `test/newton_web/controllers/reading_controller_test.exs`

- [ ] **Step 1: Generate and write the migration**

Run: `mix ecto.gen.migration create_reading_entries`
Replace body:

```elixir
defmodule Newton.Repo.Migrations.CreateReadingEntries do
  use Ecto.Migration

  def change do
    create table(:reading_entries) do
      add :title, :string, null: false
      add :author, :string, null: false
      add :link, :string
      add :note, :string
      add :status, :string, null: false
      add :finished_at, :date

      timestamps(type: :utc_datetime)
    end

    create index(:reading_entries, [:finished_at])
  end
end
```

Run: `mix ecto.migrate`

- [ ] **Step 2: Write failing context tests**

Create `test/newton/reading_test.exs`:

```elixir
defmodule Newton.ReadingTest do
  use Newton.DataCase
  alias Newton.Reading

  test "create_entry validates status enum" do
    {:error, cs} = Reading.create_entry(%{title: "T", author: "A", status: :bogus})
    assert %{status: _} = errors_on(cs)
  end

  test "list_entries orders by finished_at desc" do
    {:ok, _a} = Reading.create_entry(%{title: "Old", author: "A", status: :read, finished_at: ~D[2025-01-01]})
    {:ok, _b} = Reading.create_entry(%{title: "New", author: "B", status: :read, finished_at: ~D[2026-01-01]})
    assert Reading.list_entries() |> Enum.map(& &1.title) == ["New", "Old"]
  end

  test "verb/1 maps status to a display verb" do
    assert Reading.verb(:read) == "Read"
    assert Reading.verb(:reading) == "Reading"
    assert Reading.verb(:listened) == "Listened to"
    assert Reading.verb(:listening) == "Listening to"
  end
end
```

- [ ] **Step 3: Run to confirm failure**

Run: `mix test test/newton/reading_test.exs`
Expected: FAIL.

- [ ] **Step 4: Implement schema and context**

Create `lib/newton/reading/entry.ex`:

```elixir
defmodule Newton.Reading.Entry do
  use Ecto.Schema
  import Ecto.Changeset

  schema "reading_entries" do
    field :title, :string
    field :author, :string
    field :link, :string
    field :note, :string
    field :status, Ecto.Enum, values: [:reading, :read, :listening, :listened]
    field :finished_at, :date

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:title, :author, :link, :note, :status, :finished_at])
    |> validate_required([:title, :author, :status])
  end
end
```

Create `lib/newton/reading.ex`:

```elixir
defmodule Newton.Reading do
  @moduledoc "The reading context: books read/listened, newest first."
  import Ecto.Query, warn: false
  alias Newton.Repo
  alias Newton.Reading.Entry

  def create_entry(attrs) do
    %Entry{} |> Entry.changeset(attrs) |> Repo.insert()
  end

  def list_entries do
    Repo.all(from e in Entry, order_by: [desc: e.finished_at])
  end

  def verb(:read), do: "Read"
  def verb(:reading), do: "Reading"
  def verb(:listened), do: "Listened to"
  def verb(:listening), do: "Listening to"
end
```

- [ ] **Step 5: Run context tests**

Run: `mix test test/newton/reading_test.exs`
Expected: PASS.

- [ ] **Step 6: Write a failing controller test**

Create `test/newton_web/controllers/reading_controller_test.exs`:

```elixir
defmodule NewtonWeb.ReadingControllerTest do
  use NewtonWeb.ConnCase
  alias Newton.Reading

  test "GET /reading lists entries with the right verb and cite", %{conn: conn} do
    {:ok, _} =
      Reading.create_entry(%{
        title: "A Philosophy of Software Design",
        author: "John Ousterhout",
        status: :read,
        finished_at: ~D[2026-04-18],
        note: "The argument for deep modules stuck with me."
      })

    html = conn |> get(~p"/reading") |> html_response(200)
    assert html =~ "Read"
    assert html =~ "<cite>A Philosophy of Software Design</cite>"
    assert html =~ "John Ousterhout"
    assert html =~ "deep modules"
  end
end
```

- [ ] **Step 7: Run to confirm failure**

Run: `mix test test/newton_web/controllers/reading_controller_test.exs`
Expected: FAIL (no route).

- [ ] **Step 8: Add route, controller, HTML module, template**

In `router.ex` add: `get "/reading", ReadingController, :index`

Create `lib/newton_web/controllers/reading_controller.ex`:

```elixir
defmodule NewtonWeb.ReadingController do
  use NewtonWeb, :controller
  alias Newton.Reading

  def index(conn, _params) do
    render(conn, :index, page_title: "Reading", entries: Reading.list_entries())
  end
end
```

Create `lib/newton_web/controllers/reading_html.ex`:

```elixir
defmodule NewtonWeb.ReadingHTML do
  use NewtonWeb, :html

  embed_templates "reading_html/*"

  def format_date(nil), do: ""
  def format_date(%Date{} = d), do: Calendar.strftime(d, "%B %-d, %Y")

  defdelegate verb(status), to: Newton.Reading
end
```

Create `lib/newton_web/controllers/reading_html/index.html.heex`:

```heex
<Layouts.app flash={@flash}>
  <article class="post">
    <header>
      <h1 class="post-title">Reading</h1>
    </header>

    <.feed>
      <.feed_item :for={entry <- @entries} id={Newton.Slug.slugify(entry.title)} variant="book" date={format_date(entry.finished_at)}>
        <p class="feed-item-book">
          {verb(entry.status)} <cite>{entry.title}</cite> by {entry.author}
        </p>
        <p :if={entry.note} class="feed-item-book-caption">{entry.note}</p>
      </.feed_item>
    </.feed>
  </article>
</Layouts.app>
```

(`Newton.Slug.slugify/1` was created in Task 2.5; the `id` anchors must match the `/reading#<slug>` links the home feed generates.)

- [ ] **Step 9: Confirm controller test passes**

Run: `mix test test/newton_web/controllers/reading_controller_test.exs`
Expected: PASS.

- [ ] **Step 10: Commit**

```bash
git add priv/repo/migrations lib/newton/reading.ex lib/newton/reading/entry.ex lib/newton_web/controllers/reading_controller.ex lib/newton_web/controllers/reading_html.ex lib/newton_web/controllers/reading_html/index.html.heex lib/newton_web/router.ex test/newton/reading_test.exs test/newton_web/controllers/reading_controller_test.exs
git commit -m "Add reading context, page, and entry schema"
```

---

## Task 13: Media serving plug and config

**Files:**
- Modify: `config/config.exs`, `config/dev.exs`, `config/test.exs`, `config/prod.exs`
- Modify: `lib/newton_web/endpoint.ex`

- [ ] **Step 1: Configure the media root per environment**

In `config/config.exs`, add near the top (after the `config :newton, ecto_repos:` block):

```elixir
config :newton, :media_root, Path.expand("../priv/media", __DIR__)
```

In `config/prod.exs`, add:

```elixir
config :newton, :media_root, "/data/images"
```

(Dev/test inherit the `priv/media` default. The Fly volume mounts at `/data`.)

- [ ] **Step 2: Serve /media from the endpoint**

In `lib/newton_web/endpoint.ex`, add **above** the existing `plug Plug.Static, at: "/"` block:

```elixir
  # User images (not fingerprinted assets) served from a configurable root.
  plug Plug.Static,
    at: "/media",
    from: Application.compile_env(:newton, :media_root),
    gzip: false
```

- [ ] **Step 3: Create the dev media dir with a .keep**

Run: `mkdir -p priv/media && touch priv/media/.keep`

- [ ] **Step 4: Verify compile + boot**

Run: `mix compile --warnings-as-errors`
Expected: clean. (No files in `/media` yet; dev seeds use remote URLs.)

- [ ] **Step 5: Commit**

```bash
git add config/config.exs config/prod.exs lib/newton_web/endpoint.ex priv/media/.keep
git commit -m "Add configurable /media static plug for user images"
```

---

## Task 14: Gallery context, schemas, and image_url

**Files:**
- Create: `priv/repo/migrations/<ts>_create_photo_groups.exs`
- Create: `priv/repo/migrations/<ts>_create_photos.exs`
- Create: `lib/newton/gallery/photo_group.ex`, `lib/newton/gallery/photo.ex`
- Create: `lib/newton/gallery.ex`
- Test: `test/newton/gallery_test.exs`

- [ ] **Step 1: Migrations**

Run: `mix ecto.gen.migration create_photo_groups` → body:

```elixir
defmodule Newton.Repo.Migrations.CreatePhotoGroups do
  use Ecto.Migration

  def change do
    create table(:photo_groups) do
      add :slug, :string, null: false
      add :title, :string, null: false
      add :caption, :text
      add :taken_on, :date

      timestamps(type: :utc_datetime)
    end

    create unique_index(:photo_groups, [:slug])
    create index(:photo_groups, [:taken_on])
  end
end
```

Run: `mix ecto.gen.migration create_photos` → body:

```elixir
defmodule Newton.Repo.Migrations.CreatePhotos do
  use Ecto.Migration

  def change do
    create table(:photos) do
      add :photo_group_id, references(:photo_groups, on_delete: :delete_all), null: false
      add :image_key, :string, null: false
      add :alt, :string, null: false
      add :position, :integer, null: false, default: 0
      add :width, :integer
      add :height, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:photos, [:photo_group_id])
  end
end
```

Run: `mix ecto.migrate`

- [ ] **Step 2: Failing context tests**

Create `test/newton/gallery_test.exs`:

```elixir
defmodule Newton.GalleryTest do
  use Newton.DataCase
  alias Newton.Gallery

  test "image_url passes absolute URLs through" do
    assert Gallery.image_url("https://example.com/a.jpg") == "https://example.com/a.jpg"
  end

  test "image_url maps a stored key to /media" do
    assert Gallery.image_url("eastern-sierra/01.jpg") == "/media/eastern-sierra/01.jpg"
  end

  test "list_groups returns groups newest-first with ordered photos preloaded" do
    {:ok, g} = Gallery.create_group(%{slug: "eastern-sierra", title: "Eastern Sierra", taken_on: ~D[2025-06-01]})
    {:ok, _} = Gallery.add_photo(g, %{image_key: "b.jpg", alt: "B", position: 2})
    {:ok, _} = Gallery.add_photo(g, %{image_key: "a.jpg", alt: "A", position: 1})

    [group] = Gallery.list_groups()
    assert group.slug == "eastern-sierra"
    assert Enum.map(group.photos, & &1.image_key) == ["a.jpg", "b.jpg"]
  end
end
```

- [ ] **Step 3: Run, confirm fail**

Run: `mix test test/newton/gallery_test.exs` → FAIL.

- [ ] **Step 4: Schemas**

Create `lib/newton/gallery/photo_group.ex`:

```elixir
defmodule Newton.Gallery.PhotoGroup do
  use Ecto.Schema
  import Ecto.Changeset
  alias Newton.Gallery.Photo

  schema "photo_groups" do
    field :slug, :string
    field :title, :string
    field :caption, :string
    field :taken_on, :date

    has_many :photos, Photo, preload_order: [asc: :position]
    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(group, attrs) do
    group
    |> cast(attrs, [:slug, :title, :caption, :taken_on])
    |> validate_required([:slug, :title])
    |> unique_constraint(:slug)
  end
end
```

Create `lib/newton/gallery/photo.ex`:

```elixir
defmodule Newton.Gallery.Photo do
  use Ecto.Schema
  import Ecto.Changeset
  alias Newton.Gallery.PhotoGroup

  schema "photos" do
    field :image_key, :string
    field :alt, :string
    field :position, :integer, default: 0
    field :width, :integer
    field :height, :integer

    belongs_to :photo_group, PhotoGroup
    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(photo, attrs) do
    photo
    |> cast(attrs, [:image_key, :alt, :position, :width, :height, :photo_group_id])
    |> validate_required([:image_key, :alt, :position])
  end
end
```

- [ ] **Step 5: Context**

Create `lib/newton/gallery.ex`:

```elixir
defmodule Newton.Gallery do
  @moduledoc "Photo groups and photos; resolves image keys to URLs."
  import Ecto.Query, warn: false
  alias Newton.Repo
  alias Newton.Gallery.{PhotoGroup, Photo}

  def create_group(attrs) do
    %PhotoGroup{} |> PhotoGroup.changeset(attrs) |> Repo.insert()
  end

  def add_photo(%PhotoGroup{id: group_id}, attrs) do
    attrs = Map.put(attrs, :photo_group_id, group_id)
    %Photo{} |> Photo.changeset(attrs) |> Repo.insert()
  end

  def list_groups do
    Repo.all(from g in PhotoGroup, order_by: [desc: g.taken_on], preload: [:photos])
  end

  @doc "Resolve an image_key to a URL. Absolute URLs pass through; keys map to /media."
  def image_url("http://" <> _ = url), do: url
  def image_url("https://" <> _ = url), do: url
  def image_url(key) when is_binary(key), do: "/media/" <> key
end
```

- [ ] **Step 6: Run tests**

Run: `mix test test/newton/gallery_test.exs`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add priv/repo/migrations lib/newton/gallery.ex lib/newton/gallery/ test/newton/gallery_test.exs
git commit -m "Add gallery context, photo schemas, and image_url resolver"
```

---

## Task 15: Photos page, masonry, and lightbox

**Files:**
- Create: `lib/newton_web/controllers/photo_controller.ex`, `photo_html.ex`, `photo_html/index.html.heex`
- Create: `assets/js/hooks/photo_masonry.js`, `assets/js/hooks/photo_lightbox.js`
- Modify: `assets/js/app.js`, `lib/newton_web/router.ex`
- Test: `test/newton_web/controllers/photo_controller_test.exs`

- [ ] **Step 1: Failing controller test**

Create `test/newton_web/controllers/photo_controller_test.exs`:

```elixir
defmodule NewtonWeb.PhotoControllerTest do
  use NewtonWeb.ConnCase
  alias Newton.Gallery

  test "GET /photos renders groups and photos", %{conn: conn} do
    {:ok, g} = Gallery.create_group(%{slug: "eastern-sierra", title: "Eastern Sierra", caption: "Granite and water.", taken_on: ~D[2025-06-01]})
    {:ok, _} = Gallery.add_photo(g, %{image_key: "https://example.com/a.jpg", alt: "Morning light", position: 1})

    html = conn |> get(~p"/photos") |> html_response(200)
    assert html =~ "Eastern Sierra"
    assert html =~ "Granite and water."
    assert html =~ ~s(id="eastern-sierra")
    assert html =~ "https://example.com/a.jpg"
    assert html =~ ~s(alt="Morning light")
  end
end
```

- [ ] **Step 2: Run, confirm fail**

Run: `mix test test/newton_web/controllers/photo_controller_test.exs` → FAIL.

- [ ] **Step 3: Route, controller, HTML module**

In `router.ex`: `get "/photos", PhotoController, :index`

Create `lib/newton_web/controllers/photo_controller.ex`:

```elixir
defmodule NewtonWeb.PhotoController do
  use NewtonWeb, :controller
  alias Newton.Gallery

  def index(conn, _params) do
    render(conn, :index, page_title: "Photos", groups: Gallery.list_groups())
  end
end
```

Create `lib/newton_web/controllers/photo_html.ex`:

```elixir
defmodule NewtonWeb.PhotoHTML do
  use NewtonWeb, :html

  embed_templates "photo_html/*"

  def format_month(nil), do: ""
  def format_month(%Date{} = d), do: Calendar.strftime(d, "%B %Y")

  defdelegate image_url(key), to: Newton.Gallery
end
```

- [ ] **Step 4: Photos template**

Create `lib/newton_web/controllers/photo_html/index.html.heex`:

```heex
<Layouts.app flash={@flash}>
  <article class="post photos">
    <header>
      <h1 class="post-title">Photos</h1>
    </header>

    <section :for={group <- @groups} class="photo-group" id={group.slug}>
      <header class="photo-group-header">
        <time :if={group.taken_on} class="photo-group-date">{format_month(group.taken_on)}</time>
        <h2 class="photo-group-title">{group.title}</h2>
        <p :if={group.caption} class="photo-group-caption">{group.caption}</p>
      </header>
      <div class="photo-grid" phx-hook="PhotoMasonry" id={"grid-#{group.slug}"}>
        <button
          :for={photo <- group.photos}
          type="button"
          class="photo-button"
          aria-label={"Enlarge: #{photo.alt}"}
        >
          <img
            src={image_url(photo.image_key)}
            loading="lazy"
            decoding="async"
            alt={photo.alt}
            width={photo.width}
            height={photo.height}
          />
        </button>
      </div>
    </section>
  </article>
  <div
    class="photo-overlay"
    id="photoOverlay"
    phx-hook="PhotoLightbox"
    role="dialog"
    aria-modal="true"
    aria-labelledby="photoOverlayImg"
    tabindex="-1"
    inert
  >
    <img class="photo-overlay-img" id="photoOverlayImg" alt="" />
  </div>
</Layouts.app>
```

- [ ] **Step 5: Masonry hook**

Create `assets/js/hooks/photo_masonry.js` (per-grid column distribution; ported from the prototype, scoped to `this.el`):

```js
// Distributes .photo-button children into N columns by viewport width.
// Ported from the prototype; runs per grid element.
export const PhotoMasonry = {
  mounted() {
    this._buttons = Array.from(this.el.querySelectorAll(".photo-button"));
    this._currentCols = 0;
    this._columnCount = () => {
      if (innerWidth <= 480) return 1;
      if (innerWidth <= 720) return 2;
      return 3;
    };
    this._layout = () => {
      const cols = this._columnCount();
      if (cols === this._currentCols) return;
      this._currentCols = cols;
      const columns = Array.from({ length: cols }, () => {
        const c = document.createElement("div");
        c.className = "photo-column";
        return c;
      });
      this._buttons.forEach((btn, i) => columns[i % cols].appendChild(btn));
      this.el.replaceChildren(...columns);
    };
    this._onResize = () => {
      clearTimeout(this._timer);
      this._timer = setTimeout(this._layout, 150);
    };
    this._layout();
    window.addEventListener("resize", this._onResize);
  },
  destroyed() {
    clearTimeout(this._timer);
    window.removeEventListener("resize", this._onResize);
  },
};
```

- [ ] **Step 6: Lightbox hook**

Create `assets/js/hooks/photo_lightbox.js` (overlay open/close + focus trap; the Unsplash high-res-swap is intentionally dropped):

```js
// Lightbox overlay. Opens the full image, traps focus, restores on close.
// Attached to #photoOverlay; binds a delegated click for .photo-button.
export const PhotoLightbox = {
  mounted() {
    const overlay = this.el;
    const full = overlay.querySelector(".photo-overlay-img");
    let lastFocus = null;

    const open = (img) => {
      full.src = img.src;
      full.alt = img.alt;
      lastFocus = document.activeElement;
      document.body.style.overflow = "hidden";
      overlay.removeAttribute("inert");
      overlay.classList.add("is-open");
      overlay.focus();
    };
    const close = () => {
      if (!overlay.classList.contains("is-open")) return;
      overlay.classList.remove("is-open");
      overlay.setAttribute("inert", "");
      document.body.style.overflow = "";
      if (lastFocus) lastFocus.focus();
      setTimeout(() => { full.src = ""; }, 240);
    };

    this._onClick = (e) => {
      const btn = e.target.closest(".photo-button");
      if (btn) open(btn.querySelector("img"));
    };
    this._onKeydown = (e) => {
      if (!overlay.classList.contains("is-open")) return;
      if (e.key === "Escape") return close();
      if (e.key === "Tab") { e.preventDefault(); overlay.focus(); }
    };
    this._onOverlayClick = close;

    document.addEventListener("click", this._onClick);
    document.addEventListener("keydown", this._onKeydown);
    overlay.addEventListener("click", this._onOverlayClick);
  },
  destroyed() {
    document.removeEventListener("click", this._onClick);
    document.removeEventListener("keydown", this._onKeydown);
  },
};
```

- [ ] **Step 7: Register hooks**

In `assets/js/app.js`, add imports:

```js
import {PhotoMasonry} from "./hooks/photo_masonry"
import {PhotoLightbox} from "./hooks/photo_lightbox"
```

Update the `hooks:` option to:

```js
  hooks: {...colocatedHooks, RippleCanvas, PhotoMasonry, PhotoLightbox},
```

- [ ] **Step 8: Confirm test passes + visual check**

Run: `mix test test/newton_web/controllers/photo_controller_test.exs`
Expected: PASS.

Run: `mix assets.build && mix phx.server`, open `/photos` (after seeds, or insert a group via iex). Confirm: masonry columns, click enlarges to overlay, Esc/click-out closes, focus returns. Stop server.

- [ ] **Step 9: Commit**

```bash
git add lib/newton_web/controllers/photo_controller.ex lib/newton_web/controllers/photo_html.ex lib/newton_web/controllers/photo_html/index.html.heex assets/js/hooks/photo_masonry.js assets/js/hooks/photo_lightbox.js assets/js/app.js lib/newton_web/router.ex test/newton_web/controllers/photo_controller_test.exs
git commit -m "Add photos page with masonry and lightbox hooks"
```

---

## Task 16: Merged home feed

**Files:**
- Create: `lib/newton/feed.ex`
- Test: `test/newton/feed_test.exs`

- [ ] **Step 1: Failing test**

Create `test/newton/feed_test.exs`:

```elixir
defmodule Newton.FeedTest do
  use Newton.DataCase
  alias Newton.{Blog, Reading, Gallery, Feed}

  test "recent/1 merges posts, reading, and photo groups newest-first" do
    {:ok, _post} = Blog.create_post(%{slug: "p", title: "Post", body_markdown: "Body.", published_at: ~U[2026-04-17 00:00:00Z]})
    {:ok, _book} = Reading.create_entry(%{title: "Book", author: "A", status: :read, finished_at: ~D[2026-04-18]})
    {:ok, g} = Gallery.create_group(%{slug: "sierra", title: "Sierra", taken_on: ~D[2026-04-16]})
    {:ok, _} = Gallery.add_photo(g, %{image_key: "https://example.com/a.jpg", alt: "A", position: 1})

    kinds = Feed.recent(10) |> Enum.map(& &1.kind)
    assert kinds == [:book, :post, :photo]
  end

  test "recent/1 excludes unpublished posts" do
    {:ok, _draft} = Blog.create_post(%{slug: "d", title: "Draft", body_markdown: "B.", published_at: nil})
    assert Feed.recent(10) == []
  end
end
```

- [ ] **Step 2: Run, confirm fail**

Run: `mix test test/newton/feed_test.exs` → FAIL.

- [ ] **Step 3: Implement the Feed module**

Create `lib/newton/feed.ex`:

```elixir
defmodule Newton.Feed do
  @moduledoc """
  Merged home-feed stream across posts, reading entries, and photo groups.
  Each item is normalized to `%{date: Date.t(), kind: atom, payload: struct}`
  and sorted newest-first.
  """
  alias Newton.{Blog, Reading, Gallery}

  def recent(limit \\ 10) do
    (post_items() ++ reading_items() ++ photo_items())
    |> Enum.sort_by(& &1.date, {:desc, Date})
    |> Enum.take(limit)
  end

  defp post_items do
    for p <- Blog.list_published_posts() do
      %{date: DateTime.to_date(p.published_at), kind: :post, payload: p}
    end
  end

  defp reading_items do
    for e <- Reading.list_entries(), not is_nil(e.finished_at) do
      %{date: e.finished_at, kind: :book, payload: e}
    end
  end

  defp photo_items do
    for g <- Gallery.list_groups(), not is_nil(g.taken_on) do
      %{date: g.taken_on, kind: :photo, payload: g}
    end
  end
end
```

- [ ] **Step 4: Run tests**

Run: `mix test test/newton/feed_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/newton/feed.ex test/newton/feed_test.exs
git commit -m "Add merged home-feed query"
```

---

## Task 17: Home page

**Files:**
- Modify: `lib/newton_web/controllers/page_controller.ex`
- Replace: `lib/newton_web/controllers/page_html/home.html.heex`
- Modify: `lib/newton_web/controllers/page_html.ex` (date + verb helpers)
- Test: `test/newton_web/controllers/page_controller_test.exs`

- [ ] **Step 1: Add a failing home test**

Add to `test/newton_web/controllers/page_controller_test.exs`:

```elixir
  test "GET / shows intro, nav, and a merged feed", %{conn: conn} do
    {:ok, _} = Newton.Blog.create_post(%{slug: "three-ways-to-retry", title: "Three Ways to Retry", body_markdown: "Retry logic.", published_at: ~U[2026-04-17 00:00:00Z]})
    {:ok, _} = Newton.Reading.create_entry(%{title: "Working in Public", author: "Nadia Eghbal", status: :listened, finished_at: ~D[2026-04-13]})

    html = conn |> get(~p"/") |> html_response(200)
    assert html =~ "Hello, I'm James Newton."
    assert html =~ "Three Ways to Retry"
    assert html =~ "Listened to"
    assert html =~ "<cite>Working in Public</cite>"
  end
```

- [ ] **Step 2: Run, confirm fail**

Run: `mix test test/newton_web/controllers/page_controller_test.exs` → FAIL (scaffold home page).

- [ ] **Step 3: Update the controller**

In `lib/newton_web/controllers/page_controller.ex`, replace the `home/2` action:

```elixir
  def home(conn, _params) do
    render(conn, :home, page_title: nil, feed: Newton.Feed.recent(10))
  end
```

- [ ] **Step 4: Add helpers to PageHTML**

In `lib/newton_web/controllers/page_html.ex`, add:

```elixir
  def format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%B %-d, %Y")
  def format_date(%Date{} = d), do: Calendar.strftime(d, "%B %-d, %Y")

  defdelegate verb(status), to: Newton.Reading
  defdelegate image_url(key), to: Newton.Gallery
```

- [ ] **Step 5: Replace the home template**

Overwrite `lib/newton_web/controllers/page_html/home.html.heex`:

```heex
<Layouts.app flash={@flash}>
  <div class="page">
    <section class="intro">
      <h1 class="intro-heading">Hello, I'm James Newton.</h1>
      <p>
        I'm a software engineer at <a href="https://markos.ai">Mark OS</a> who thinks a lot
        about how we build things and why. This is where I write about the craft — the tools,
        the trade-offs, and the quiet decisions that shape what we make.
      </p>
    </section>

    <.site_nav />

    <.feed heading="Recent">
      <%= for item <- @feed do %>
        <.home_feed_item item={item} />
      <% end %>
    </.feed>
  </div>
</Layouts.app>
```

Note: the `<div class="page">` here conflicts with `app/1` already rendering `<main id="main">`. The prototype's home uses `<main class="page" id="main">`. **Decision:** Since `app/1` renders `<main id="main">`, change the home wrapper to a plain `<div class="page">` as above — but `.page` sets `max-width`/centering that `<main>` doesn't. Confirm the `.page` styles apply to this inner div. Because `.page` in `site.css` targets `.page` by class (not element), the inner `<div class="page">` gets the container styling. Good. (Other pages use `.post` for the same effect.)

- [ ] **Step 6: Add the home_feed_item component**

In `lib/newton_web/controllers/page_html.ex`, add a function component that renders each feed kind. Add at the top of the module after `use NewtonWeb, :html`:

```elixir
  attr :item, :map, required: true

  def home_feed_item(%{item: %{kind: :post}} = assigns) do
    ~H"""
    <.feed_item href={~p"/posts/#{@item.payload.slug}"} date={format_date(@item.payload.published_at)}>
      <h3 class="feed-item-title">{@item.payload.title}</h3>
      <p class="feed-item-excerpt">{@item.payload.excerpt}</p>
    </.feed_item>
    """
  end

  def home_feed_item(%{item: %{kind: :book}} = assigns) do
    ~H"""
    <.feed_item href={~p"/reading##{Newton.Slug.slugify(@item.payload.title)}"} variant="book" date={format_date(@item.date)}>
      <p class="feed-item-book">
        {verb(@item.payload.status)} <cite>{@item.payload.title}</cite> by {@item.payload.author}
      </p>
    </.feed_item>
    """
  end

  def home_feed_item(%{item: %{kind: :photo}} = assigns) do
    assigns = assign(assigns, :first, List.first(assigns.item.payload.photos))

    ~H"""
    <.feed_item
      href={~p"/photos##{@item.payload.slug}"}
      variant="photo"
      date={format_date(@item.date)}
      aria-label={"Photos from #{@item.payload.title}, #{format_date(@item.date)}"}
    >
      <img :if={@first} class="feed-item-photo" src={image_url(@first.image_key)} alt="" />
    </.feed_item>
    """
  end
```

- [ ] **Step 7: Confirm tests pass + visual check**

Run: `mix test test/newton_web/controllers/page_controller_test.exs`
Expected: PASS.

Run `mix phx.server`, open `/` (after seeds). Confirm intro, nav, and an interleaved feed of posts/books/photo. Stop server.

- [ ] **Step 8: Commit**

```bash
git add lib/newton_web/controllers/page_controller.ex lib/newton_web/controllers/page_html.ex lib/newton_web/controllers/page_html/home.html.heex test/newton_web/controllers/page_controller_test.exs
git commit -m "Add home page with merged feed"
```

---

## Task 18: Seeds

**Files:**
- Modify: `priv/repo/seeds.exs`

- [ ] **Step 1: Write the seeds**

Replace `priv/repo/seeds.exs`. Seeds are idempotent (delete-all then insert, so re-running is safe in dev). Use the prototype content. Reading entries and photo groups are fully specified below; posts are transcribed from the prototype HTML.

```elixir
alias Newton.{Repo, Blog, Reading, Gallery}
alias Newton.Blog.Post
alias Newton.Reading.Entry
alias Newton.Gallery.{PhotoGroup, Photo}

# Idempotent reset (dev/placeholder content only)
Repo.delete_all(Photo)
Repo.delete_all(PhotoGroup)
Repo.delete_all(Entry)
Repo.delete_all(Post)

# --- Posts ---------------------------------------------------------------
# Transcribe each prototype post's HTML body into Markdown. Full Markdown for
# "Three Ways to Retry" is provided; transcribe "The Quiet Shift" from
# $PROTO/posts/the-quiet-shift-software-engineering-in-the-age-of-ai.html
# the same way (prose paragraphs become Markdown paragraphs).

three_ways = """
Retry logic is one of those small utilities every codebase eventually needs. The network flakes. A database is briefly unreachable. An upstream service returns a `503` and a polite suggestion to try again. We reach for a helper, and — if we're lucky — one already exists.

What's interesting isn't the logic itself. [Exponential backoff with jitter](https://en.wikipedia.org/wiki/Exponential_backoff) is more or less a solved problem. What's interesting is how different the *shape* of the solution looks in different languages.

## The problem

Let's pick a concrete target. We want a helper that:

- Takes a function that might fail
- Retries up to `n` times with exponential backoff
- Gives up on errors that are clearly not transient
- Returns the successful value — or the final error

## Python: decorators and duck typing

```python
import time
import random
from functools import wraps

def retry(attempts=3, base_delay=0.5):
    def decorator(fn):
        @wraps(fn)
        def wrapper(*args, **kwargs):
            last_error = None
            for attempt in range(attempts):
                try:
                    return fn(*args, **kwargs)
                except TransientError as e:
                    last_error = e
                    delay = base_delay * (2 ** attempt) + random.random() * 0.1
                    time.sleep(delay)
            raise last_error
        return wrapper
    return decorator
```

## What the shapes reveal

> The same idea becomes three different objects depending on what the language considers idiomatic: a decorator, a higher-order function, a generic loop.

None of these is wrong. They reflect different values.
"""

{:ok, _} =
  Blog.create_post(%{
    slug: "three-ways-to-retry",
    title: "Three Ways to Retry",
    body_markdown: three_ways,
    published_at: ~U[2026-04-17 12:00:00Z]
  })

quiet_shift = """
There was a time when writing software felt like building a cathedral. Every function was a brick laid with intention, every module an arch designed to bear weight. The craft demanded patience.

<!-- Transcribe the rest of the body from
     $PROTO/posts/the-quiet-shift-software-engineering-in-the-age-of-ai.html -->
"""

{:ok, _} =
  Blog.create_post(%{
    slug: "the-quiet-shift-software-engineering-in-the-age-of-ai",
    title: "The Quiet Shift: Software Engineering in the Age of AI",
    body_markdown: quiet_shift,
    published_at: ~U[2026-04-14 12:00:00Z]
  })

# --- Reading -------------------------------------------------------------
reading = [
  %{title: "A Philosophy of Software Design", author: "John Ousterhout", status: :read, finished_at: ~D[2026-04-18], note: "The argument for deep modules stuck with me. I don't fully agree, but I keep returning to it."},
  %{title: "Working in Public", author: "Nadia Eghbal", status: :listened, finished_at: ~D[2026-04-13]},
  %{title: "The Pragmatic Programmer", author: "Hunt and Thomas", status: :read, finished_at: ~D[2026-03-15]},
  %{title: "Designing Data-Intensive Applications", author: "Martin Kleppmann", status: :read, finished_at: ~D[2026-02-22], note: "The kind of book you read a chapter at a time, put down, and notice it quietly reshaping how you think about the system you work on."},
  %{title: "Four Thousand Weeks", author: "Oliver Burkeman", status: :read, finished_at: ~D[2026-01-18], note: "I don't know if I believed all of it. I kept putting it down to think."},
  %{title: "The Mythical Man-Month", author: "Fred Brooks", status: :read, finished_at: ~D[2025-12-08]},
  %{title: "The Creative Act", author: "Rick Rubin", status: :listened, finished_at: ~D[2025-11-10], note: "Rubin reads the audiobook himself, which is the right call. A good one for a long walk."},
  %{title: "Atomic Habits", author: "James Clear", status: :read, finished_at: ~D[2025-10-03]},
  %{title: "Shop Class as Soulcraft", author: "Matthew B. Crawford", status: :read, finished_at: ~D[2025-09-14]},
  %{title: "Zen and the Art of Motorcycle Maintenance", author: "Robert Pirsig", status: :listened, finished_at: ~D[2025-08-06], note: "Most of it went past me. The pages about caring for a machine did not."}
]

Enum.each(reading, fn attrs -> {:ok, _} = Reading.create_entry(attrs) end)

# --- Photos --------------------------------------------------------------
# Dev uses remote placeholder URLs as image_key (image_url/1 passes them through).
photo_groups = [
  %{
    slug: "eastern-sierra", title: "Eastern Sierra", taken_on: ~D[2025-06-01],
    caption: "Four days of granite and alpine water, on the route up from Onion Valley I'd been circling for a year.",
    photos: [
      {"https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=800&q=80", "Morning light breaking over a mountain ridge"},
      {"https://images.unsplash.com/photo-1470071459604-3b5ec3a7fe05?w=800&q=80", "Still alpine lake reflecting distant peaks"},
      {"https://images.unsplash.com/photo-1454496522488-7a8e488e8606?w=800&q=80", "Stone cabin at the edge of a mountain lake"},
      {"https://images.unsplash.com/photo-1475924156734-496f6cac6ec1?w=800&q=80", "Snow-dusted peaks above a quiet lake"}
    ]
  },
  %{
    slug: "olympic-coast", title: "Olympic Coast", taken_on: ~D[2025-03-01],
    caption: "Fog kept rewriting the shoreline as overlapping silhouettes — which, it turns out, is the thing I came back for.",
    photos: [
      {"https://images.unsplash.com/photo-1486870591958-9b9d0d1dda99?w=800&q=80", "Fog rolling between forested ridgelines"},
      {"https://images.unsplash.com/photo-1472214103451-9374bd1c798e?w=800&q=80", "Evergreen forest shrouded in morning mist"},
      {"https://images.unsplash.com/photo-1513836279014-a89f7a76ae86?w=800&q=80", "Tall pine trees catching afternoon light"},
      {"https://images.unsplash.com/photo-1519904981063-b0cf448d479e?w=800&q=80", "Dense fog clinging to mountain slopes"}
    ]
  },
  %{
    slug: "julian-alps", title: "Julian Alps", taken_on: ~D[2025-01-01],
    caption: "Lake Bled was still frozen at the edges. The trails around Triglav I kept cutting short for weather.",
    photos: [
      {"https://images.unsplash.com/photo-1508739773434-c26b3d09e071?w=800&q=80", "Winter forest, snow on every branch"},
      {"https://images.unsplash.com/photo-1519681393784-d120267933ba?w=800&q=80", "Night sky over a silhouetted mountain ridge"},
      {"https://images.unsplash.com/photo-1501785888041-af3ef285b470?w=800&q=80", "Lake Bled at dusk with an island chapel"},
      {"https://images.unsplash.com/photo-1433086966358-54859d0ed716?w=800&q=80", "Suspension bridge over a pine-lined gorge"}
    ]
  },
  %{
    slug: "dolomites", title: "Dolomites", taken_on: ~D[2024-09-01],
    caption: "The via ferrata I came for was closed for weather. I spent the week walking between huts instead.",
    photos: [
      {"https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?w=800&q=80", "Snow-capped alpine peaks at sunrise"},
      {"https://images.unsplash.com/photo-1469474968028-56623f02e42e?w=800&q=80", "Sun setting behind layered mountain ridges"},
      {"https://images.unsplash.com/photo-1443890923422-7819ed4101c0?w=800&q=80", "A lone tent pitched beneath a granite wall"},
      {"https://images.unsplash.com/photo-1454372182658-c712e4c5a1db?w=800&q=80", "Narrow valley with a winding river"}
    ]
  }
]

Enum.each(photo_groups, fn %{photos: photos} = attrs ->
  {:ok, group} = Gallery.create_group(Map.delete(attrs, :photos))

  photos
  |> Enum.with_index(1)
  |> Enum.each(fn {{key, alt}, pos} ->
    {:ok, _} = Gallery.add_photo(group, %{image_key: key, alt: alt, position: pos})
  end)
end)

IO.puts("Seeded #{Repo.aggregate(Post, :count)} posts, #{Repo.aggregate(Entry, :count)} reading entries, #{Repo.aggregate(PhotoGroup, :count)} photo groups.")
```

- [ ] **Step 2: Transcribe the second post**

Open `$PROTO/posts/the-quiet-shift-software-engineering-in-the-age-of-ai.html`, convert its `.post-body` prose to Markdown, and replace the `quiet_shift` placeholder body with the real content.

- [ ] **Step 3: Run the seeds**

Run: `mix run priv/repo/seeds.exs`
Expected: prints `Seeded 2 posts, 10 reading entries, 4 photo groups.`

- [ ] **Step 4: Full visual pass**

Run `mix phx.server`. Walk `/`, `/posts`, `/posts/three-ways-to-retry`, `/reading`, `/photos`, `/resume`. Confirm design fidelity against the prototype (palette, type, feed variants, code highlighting, masonry, lightbox, view transitions on navigation). Stop server.

- [ ] **Step 5: Commit**

```bash
git add priv/repo/seeds.exs
git commit -m "Seed placeholder content from the prototype"
```

---

## Task 19: Carry over docs and the rerender task

**Files:**
- Create: `lib/mix/tasks/newton.posts.rerender.ex`
- Create: `docs/design.md`, `docs/tone.md`, `docs/agents/accessibility.md` (carried from prototype)
- Test: `test/mix/tasks/newton_posts_rerender_test.exs`

- [ ] **Step 1: Failing test for the rerender task**

Create `test/mix/tasks/newton_posts_rerender_test.exs`:

```elixir
defmodule Mix.Tasks.Newton.Posts.RerenderTest do
  use Newton.DataCase
  alias Newton.{Blog, Repo}
  alias Newton.Blog.Post

  test "re-renders all posts' body_html from body_markdown" do
    {:ok, post} = Blog.create_post(%{slug: "x", title: "X", body_markdown: "## Hi", published_at: ~U[2026-01-01 00:00:00Z]})

    # Corrupt the cached HTML directly, bypassing the changeset.
    Repo.update_all(Post, set: [body_html: "STALE"])
    assert Repo.get!(Post, post.id).body_html == "STALE"

    Mix.Tasks.Newton.Posts.Rerender.run([])

    assert Repo.get!(Post, post.id).body_html =~ "<h2"
  end
end
```

- [ ] **Step 2: Run, confirm fail**

Run: `mix test test/mix/tasks/newton_posts_rerender_test.exs` → FAIL.

- [ ] **Step 3: Implement the task**

Create `lib/mix/tasks/newton.posts.rerender.ex`:

```elixir
defmodule Mix.Tasks.Newton.Posts.Rerender do
  @shortdoc "Re-renders all posts' cached HTML/excerpt/reading_time from Markdown"
  use Mix.Task
  alias Newton.{Repo, Blog}
  alias Newton.Blog.Post

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    Post
    |> Repo.all()
    |> Enum.each(fn post ->
      {:ok, _} = Blog.update_post(post, %{body_markdown: post.body_markdown})
    end)

    Mix.shell().info("Re-rendered #{Repo.aggregate(Post, :count)} posts.")
  end
end
```

Note: passing the same `body_markdown` as a change forces `render_derived_fields/1` to fire. Because `excerpt` is preserved when already set, re-rendering will not overwrite a custom excerpt; the HTML and reading_time always refresh.

- [ ] **Step 4: Run test**

Run: `mix test test/mix/tasks/newton_posts_rerender_test.exs`
Expected: PASS.

- [ ] **Step 5: Carry over the docs**

Copy `$PROTO/docs/design.md`, `$PROTO/docs/tone.md`, and `$PROTO/docs/agents/accessibility.md` into this repo under `docs/`. Apply the Task 11 Step 5 edit to `docs/design.md` (replace the highlight.js/`.hljs-*` description with MDEx/Lumis `:html_linked` server-side rendering). Update `docs/design.md`'s cache-busting / `?v=N` note to reference Phoenix `mix phx.digest` fingerprinting instead.

- [ ] **Step 6: Commit**

```bash
git add lib/mix/tasks/newton.posts.rerender.ex test/mix/tasks/newton_posts_rerender_test.exs docs/
git commit -m "Add posts rerender task and carry over design/tone/a11y docs"
```

---

## Task 20: Full suite, precommit, and cleanup

**Files:**
- Modify: `lib/newton_web/controllers/error_html.ex` (optional 404 styling — only if time permits)

- [ ] **Step 1: Remove the stray crash dump if present**

If `erl_crash.dump` exists in the repo root, delete it: `rm -f erl_crash.dump` and ensure `.gitignore` ignores `erl_crash.dump` (the default Phoenix `.gitignore` already does).

- [ ] **Step 2: Run the full suite**

Run: `mix test`
Expected: all tests pass (markdown, blog, reading, gallery, feed, slug, controllers, rerender task).

- [ ] **Step 3: Run precommit**

Run: `mix precommit`
Expected: compiles warnings-as-errors, no unused deps, formatted, tests green. Fix anything it flags.

- [ ] **Step 4: Final visual regression vs prototype**

Run `mix phx.server`. Side-by-side with the prototype (`python3 $PROTO/serve.py` or open the static files), confirm each page matches. Pay attention to: header→content gap (2rem), code badges, blockquote left border, table header tracking, photo masonry breakpoints, lightbox focus trap, dark mode flip.

- [ ] **Step 5: Commit any final fixes**

```bash
git add -A
git commit -m "Final pass: full suite green and design parity verified"
```

---

## Notes & Risks

- **MDEx highlighting markup (Task 11) is the main unknown.** The exact Lumis `:html_linked` class names and whether the language label survives drive the highlight CSS and the language-badge selectors. Task 11 captures real output in IEx before writing CSS — do not skip that step or guess class names.
- **Database is Postgres** (scaffold default, unchanged). `Ecto.Adapters.SQL.Sandbox` supports async test cases.
- **`Plug.Static` media root uses `compile_env`.** Prod's `/data/images` is a compile-time default; this is fine because the Fly volume mount path is a fixed deploy constant. If you later need a runtime-configurable path, replace the endpoint plug with a small wrapper plug that reads `Application.get_env/2` at init.
- **Raw HTML in post bodies is stripped** (`unsafe: false`). The prototype's `<figure>/<figcaption>` won't survive Markdown conversion; seed bodies use plain Markdown images. This matches the spec's safety-by-default decision.
- **daisyUI/Tailwind remain installed but unused publicly** — kept for a future admin surface per the spec. Don't delete them.
- **View transitions** come entirely from `@view-transition { navigation: auto; }` in `site.css` plus real `<a href>`/`~p` links. No JS. Verify by navigating between pages and watching the cross-fade.
