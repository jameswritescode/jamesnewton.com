# OG / Twitter Preview Cards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Note:** Task 1 (the spike) and Task 2 (card visual design) involve judgment/iteration and are best executed inline.

**Goal:** Rich link previews — OG/Twitter meta tags on every public page, a **per-post card image rendered on demand** at `GET /og/posts/:slug` (title + excerpt + date · reading time), and a static default card for every other page.

**Architecture:** A `Newton.SocialCard` renderer (libvips via the `image` lib) draws 1200×630 PNGs using a repo-bundled Lora font resolved through fontconfig. A thin `NewtonWeb.OgImageController` loads the published post by slug and streams a freshly rendered PNG with HTTP cache headers — no stored image, no database column, no background job, never stale. Non-post pages reference a committed `priv/static/og-default.png`. The public layout emits OG/Twitter tags from per-page assigns.

**Tech Stack:** `image` 0.69 (vix/libvips, Pango text), fontconfig + an in-repo Lora TTF, a Phoenix controller with `Cache-Control`/`ETag`, HEEx meta tags.

**Reference spec:** `docs/superpowers/specs/2026-06-21-og-preview-cards-design.md`

**Architecture note (supersedes earlier draft):** An earlier version of this plan stored a generated PNG per post (`og_image_key` column + `Task.Supervisor` async regeneration on title/date change + `Gallery.Storage`). We replaced it with the on-demand endpoint below: simpler (no migration/field/job/storage/cleanup), and never stale because the card is rendered from the live post at request time. OG images are fetched by crawlers when a link is *shared* — rare and not user-facing — so per-request render cost (tens of ms) is a non-issue, and HTTP caching covers repeat fetches. The `Task.Supervisor` added in Task 1 for the old approach is now unused and is removed in Task 5.

**Session constraints:** Commit signed (1Password; if it fails, `--no-gpg-sign` then re-sign later). Trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`. Don't modify `config/dev.exs`. Servers on PORT=4001.

---

## Task 1: Feasibility spike — render Lora text to a PNG  ✅ done (committed)

**Goal:** prove `image`/vix can render Lora text in this environment before building anything. This was a **decision gate** — it passed; the `image` renderer is in use.

**Files:**
- Modify: `mix.exs` (`{:image, "~> 0.69"}`)
- Create: `priv/fonts/Lora.ttf` (committed — runtime font), `priv/fonts/fonts.conf`
- Modify: `config/runtime.exs` (fontconfig env), `lib/newton/application.ex`

What shipped (commit `Add image lib, bundled Lora font, and a Task.Supervisor for social cards`):

- `mix.exs` deps gained `{:image, "~> 0.69"}` (pulls `vix`).
- `priv/fonts/Lora.ttf` (Lora variable font) + `priv/fonts/fonts.conf` committed so the font ships in the release.
- `config/runtime.exs` writes a `FONTCONFIG_FILE` pointing at the repo font dir **before vix initializes**.
- `lib/newton/application.ex` gained `{Task.Supervisor, name: Newton.TaskSupervisor}` — **now unused** (was for the abandoned async approach); removed in Task 5.

**Decision-gate outcome:** vix/`Image.Text` renders Lora correctly. Font resolution diverges by OS — macOS dev uses CoreText (font installed at `~/Library/Fonts/` for local rendering), Linux/prod uses fontconfig + the bundled font via `FONTCONFIG_FILE`. The Pango font string must be `font: "Lora"` + a separate `font_size:` integer (a combined `"Lora SemiBold 84"` string falls back to sans). The Node `fontkit`+`sharp` fallback was not needed.

---

## Task 2: The card renderer (`Newton.SocialCard`) + pick a palette

**Files:**
- Create: `lib/newton/social_card.ex`
- Test: `test/newton/social_card_test.exs`

**Status:** renderer written, tuned against the user's Figma mockups, and matched to them; 3 tests pass; **not yet committed**. Palette is **locked to dark** (`@default_palette :dark`) — the site is going dark-only (see "Related work" at the bottom). `default_card/1` was **removed** (the static card is a committed export now — see Task 4). The renderer is now `post_card/2` only.

Final design (dark): bg `#151311`, all-cream text `#eed3ba`, muted secondary `#ad9987`. Layout: "James Newton" brand mark (50px) top-left at (80, 80); length-scaled title (75 / 64 / 52 by byte length, wrapping to a second line) at (80, 150); excerpt (30px, muted) below it tracking the title height; `date · reading time` (24px, muted) bottom-left at (80, 526); and a **20px full-width cream accent stripe** along the bottom edge (`y=610`). Date uses `Newton.Format.format_date/1` (full month, e.g. "April 17, 2026"). `@palettes` still carries `red` + `dark` and `post_card/2` accepts a palette arg, but only dark is used — the renderer keeps the parameter for the editor preview / future flexibility (candidate to strip if it stays unused).

- [x] **Step 1–4: tests + renderer** — `test/newton/social_card_test.exs` pins the behavioral contract (returns PNG magic bytes + 1200×630; long titles wrap and nil excerpts don't crash/overflow). `lib/newton/social_card.ex` implements it. The renderer file is the source of truth; key tunables are the module attributes (`@pad 80`, `@title_top 150`, `@excerpt_max_chars 160`, `@stripe_height 20`) and `title_size/1` (75/64/52). The `text/2` helper uses `font: "Lora"` + integer `font_size:` (the spike-proven Pango form), `align: :left`, optional `width:` for wrapping.

- [x] **Step 4b: De-duplicate `format_date`** — the date format (`%B %-d, %Y`) already lived in `NewtonWeb.Helpers.format_date`. To avoid a domain→web layering inversion, the canonical formatter moved to a neutral `Newton.Format.format_date/2` (handles `DateTime`/`Date`/`nil` + `:on_nil`); `NewtonWeb.Helpers.format_date` now `defdelegate`s to it (no call sites change), and `Newton.SocialCard` calls `Newton.Format.format_date/1`.

- [x] **Step 5: Palette — resolved to dark.** (Decided visually against the mockups.)

- [ ] **Step 6: Run tests + commit**

```bash
mix test test/newton/social_card_test.exs   # 3 passing
git add lib/newton/social_card.ex test/newton/social_card_test.exs lib/newton/format.ex lib/newton_web/helpers.ex
git commit -m "$(cat <<'EOF'
Add the social card renderer

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: The on-demand OG image endpoint

**Files:**
- Create: `lib/newton_web/controllers/og_image_controller.ex`
- Modify: `lib/newton_web/router.ex` (a new `/og` scope)
- Test: `test/newton_web/controllers/og_image_controller_test.exs`

**Why a dedicated scope (not `:browser`):** the `:browser` pipeline runs `plug :accepts, ["html", "json"]`. An image crawler requesting the PNG with `Accept: image/png` would get a 406 from that plug. The `/og` route therefore uses **no pipeline** — it needs no session, CSRF, or layout — and the controller sets the content type and cache headers explicitly.

- [ ] **Step 1: Write the failing test**

`test/newton_web/controllers/og_image_controller_test.exs`:
```elixir
defmodule NewtonWeb.OgImageControllerTest do
  use NewtonWeb.ConnCase, async: true

  alias Newton.Blog

  defp publish!(slug, title) do
    {:ok, post} =
      Blog.create_post(%{
        slug: slug,
        title: title,
        body_markdown: "Some body text for the excerpt.",
        published_at: ~U[2026-01-01 00:00:00Z]
      })

    post
  end

  test "renders a 1200x630 PNG card for a published post", %{conn: conn} do
    publish!("og-endpoint", "Endpoint Card")

    conn = get(conn, ~p"/og/posts/og-endpoint")

    assert response_content_type(conn, :png)
    body = response(conn, 200)
    assert <<0x89, "PNG", _::binary>> = body

    {:ok, img} = Image.from_binary(body)
    assert {Image.width(img), Image.height(img)} == {1200, 630}
  end

  test "sets a public cache-control header", %{conn: conn} do
    publish!("og-cache", "Cache Me")

    conn = get(conn, ~p"/og/posts/og-cache")

    assert ["public" <> _] = get_resp_header(conn, "cache-control")
  end

  test "404s for an unknown or unpublished slug", %{conn: conn} do
    assert_error_sent 404, fn -> get(conn, ~p"/og/posts/does-not-exist") end
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/newton_web/controllers/og_image_controller_test.exs` — FAIL (no route/controller).

- [ ] **Step 3: Add the route**

In `lib/newton_web/router.ex`, after the main public `scope "/"` block, add a pipeline-less scope:
```elixir
  # Social card images. No :browser pipeline — these are PNGs, so we skip
  # accepts/session/CSRF and let the controller set content-type + caching.
  scope "/og", NewtonWeb do
    get "/posts/:slug", OgImageController, :show
  end
```

- [ ] **Step 4: Implement the controller**

`lib/newton_web/controllers/og_image_controller.ex`:
```elixir
defmodule NewtonWeb.OgImageController do
  @moduledoc """
  Renders a post's Open Graph card on demand. The card is generated from the
  live post each request (never stale) and cached at the edge/browser via
  HTTP headers, since crawlers refetch rarely.
  """
  use NewtonWeb, :controller

  alias Newton.Blog
  alias Newton.SocialCard

  @cache_control "public, max-age=3600"

  def show(conn, %{"slug" => slug}) do
    post = Blog.get_published_post!(slug)

    case SocialCard.post_card(%{
           title: post.title,
           excerpt: post.excerpt,
           published_on: post.published_at && DateTime.to_date(post.published_at),
           reading_time: post.reading_time || 1
         }) do
      {:ok, png} ->
        conn
        |> put_resp_content_type("image/png")
        |> put_resp_header("cache-control", @cache_control)
        |> send_resp(200, png)

      {:error, _reason} ->
        # Rendering should not fail in practice; fall back to the static card
        # rather than 500 so the crawler still gets an image.
        conn
        |> put_resp_content_type("image/png")
        |> put_resp_header("cache-control", @cache_control)
        |> send_file(200, Path.join(:code.priv_dir(:newton), "static/og-default.png"))
    end
  end
end
```
`Blog.get_published_post!/1` raises `Ecto.NoResultsError` for unknown or unpublished slugs → Phoenix renders a 404 (matching the test). The static fallback only triggers if `og-default.png` exists — it's committed in Task 4 Step 1 (the Figma export); the happy path doesn't need it.

- [ ] **Step 5: Run the tests**

Run: `mix test test/newton_web/controllers/og_image_controller_test.exs` — PASS.
(If `response_content_type(conn, :png)` doesn't resolve the mime, assert the header directly: `assert ["image/png" <> _] = get_resp_header(conn, "content-type")`.)

- [ ] **Step 6: Commit**

```bash
git add lib/newton_web/controllers/og_image_controller.ex lib/newton_web/router.ex test/newton_web/controllers/og_image_controller_test.exs
git commit -m "$(cat <<'EOF'
Render post OG cards on demand at /og/posts/:slug

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Meta tags + default card + controller assigns

**Files:**
- Create (committed Figma export): `priv/static/og-default.png`
- Modify: `lib/newton_web.ex` (`static_paths`), `lib/newton_web/components/layouts/root.html.heex`, `lib/newton_web/controllers/post_controller.ex`
- Test: `test/newton_web/controllers/post_controller_test.exs`, `test/newton_web/controllers/page_controller_test.exs`

- [ ] **Step 1: Commit the default card (Figma export)**

The default/site card is a fixed brand image (the "JN" monogram lockup — "James Newton" / "Software & Photography" — on the dark bg with the cream stripe), so it isn't rendered: copy the committed Figma export into place rather than generating it.

```bash
cp "$HOME/Downloads/Frame 6.png" priv/static/og-default.png   # 1200×630, dark
```

Add `"og-default.png"` to `static_paths/0` in `lib/newton_web.ex`. (If the source export moves, it's the 1200×630 dark monogram card the user supplied during design.)

- [ ] **Step 2: Write the failing controller tests**

In `test/newton_web/controllers/post_controller_test.exs` (a published post exists in setup):
```elixir
  test "a published post head has OG/Twitter tags pointing at its card", %{conn: conn} do
    html = conn |> get(~p"/posts/three-ways-to-retry") |> html_response(200)
    assert html =~ ~s(property="og:title")
    assert html =~ "Three Ways to Retry"
    assert html =~ ~s(property="og:type" content="article")
    assert html =~ ~s(name="twitter:card" content="summary_large_image")
    assert html =~ "/og/posts/three-ways-to-retry"
    assert html =~ ~r{property="og:image" content="https?://}
  end
```
In `test/newton_web/controllers/page_controller_test.exs`:
```elixir
  test "the home page uses the default OG image and website type", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)
    assert html =~ "og-default.png"
    assert html =~ ~s(property="og:type" content="website")
  end
```

- [ ] **Step 3: Run them to verify they fail**

Run those two test files — FAIL (no meta tags).

- [ ] **Step 4: Add the meta tags to the public layout**

In `lib/newton_web/components/layouts/root.html.heex` `<head>`, after the favicon links, add (absolute URLs):
```heex
    <meta property="og:type" content={assigns[:og_type] || "website"} />
    <meta property="og:site_name" content="James Newton" />
    <meta property="og:title" content={assigns[:og_title] || "James Newton"} />
    <meta
      property="og:description"
      content={assigns[:og_description] || "Software, writing, and the occasional photo."}
    />
    <meta property="og:url" content={assigns[:og_url] || Phoenix.Controller.current_url(@conn)} />
    <meta property="og:image" content={assigns[:og_image] || url(~p"/og-default.png")} />
    <meta name="twitter:card" content="summary_large_image" />
    <meta name="twitter:title" content={assigns[:og_title] || "James Newton"} />
    <meta
      name="twitter:description"
      content={assigns[:og_description] || "Software, writing, and the occasional photo."}
    />
    <meta name="twitter:image" content={assigns[:og_image] || url(~p"/og-default.png")} />
```
(`@conn` is present in the controller-rendered public layout. `url(~p"/...")` yields the absolute URL via the endpoint host.)

- [ ] **Step 5: Set the post OG assigns**

In `lib/newton_web/controllers/post_controller.ex` `show/2`, set OG assigns for both branches. Published posts point `og:image` at the live endpoint; drafts/previews (noindex) fall back to the default static card via `nil`:
```elixir
  defp put_og(conn, post, og_image) do
    conn
    |> assign(:og_type, "article")
    |> assign(:og_title, post.title)
    |> assign(:og_description, post.excerpt)
    |> assign(:og_url, url(~p"/posts/#{post.slug}"))
    |> assign(:og_image, og_image)
  end
```
Call it before `render(...)` in each branch:
- published branch: `conn = put_og(conn, post, url(~p"/og/posts/#{post.slug}"))`
- preview branch: `conn = put_og(conn, post, url(~p"/og-default.png"))`

(`current_url`/defaults cover non-post controllers automatically; no changes needed there.)

- [ ] **Step 6: Run the tests + precommit**

Run the two test files → PASS. Run `mix precommit` → green.

- [ ] **Step 7: Commit**

```bash
git add priv/static/og-default.png lib/newton_web.ex lib/newton_web/components/layouts/root.html.heex lib/newton_web/controllers/post_controller.ex test/newton_web/controllers/post_controller_test.exs test/newton_web/controllers/page_controller_test.exs
git commit -m "$(cat <<'EOF'
Emit OG/Twitter meta tags with per-post card images

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Card preview in the post editor

A live preview of the social card inside the editor's "Settings" (publish) drawer,
rendered from the **current form state** so it works for drafts and unsaved edits
(the public `/og/posts/:slug` endpoint only serves published posts). Rendered as a
base64 `data:image/png` URI when the drawer opens — no extra public route, behind
the existing admin auth. Render-on-open only (the drawer overlays the title field,
so there's nothing to live-update while it's open); reopening re-renders from the
latest state.

**Files:**
- Modify: `lib/newton_web/live/admin/post_live/editor.ex` (alias, mount assign, `toggle_drawer`, a render helper, drawer template)
- Test: `test/newton_web/live/admin/post_editor_live_test.exs`

**Depends on:** Task 2 (`Newton.SocialCard.post_card/2`). Independent of Tasks 3–4.

- [ ] **Step 1: Write the failing test**

In `test/newton_web/live/admin/post_editor_live_test.exs` (uses the existing
`setup` login + `open_draft/2` helper):
```elixir
  test "the settings drawer renders a social card preview", %{conn: conn} do
    {view, _post} = open_draft(conn, %{title: "Card In Editor"})

    refute has_element?(view, "#og-card-preview")

    view |> element("button", "Settings") |> render_click()

    assert has_element?(view, "#og-card-preview[src^='data:image/png;base64,']")
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/newton_web/live/admin/post_editor_live_test.exs` — FAIL (no `#og-card-preview`).

- [ ] **Step 3: Render the card when the drawer opens**

In `lib/newton_web/live/admin/post_live/editor.ex`:

Add the alias (near the others): `alias Newton.SocialCard`.

In `mount/3`, add `|> assign(:card_preview, nil)` to the socket pipeline.

Replace `handle_event("toggle_drawer", ...)` so opening renders the preview:
```elixir
  def handle_event("toggle_drawer", _params, socket) do
    open? = !socket.assigns.drawer_open
    socket = assign(socket, :drawer_open, open?)
    {:noreply, if(open?, do: put_card_preview(socket), else: socket)}
  end
```

Add the render helper (builds card attrs from the current changeset / publish
state; blank title falls back so `Image.Text` never gets an empty string):
```elixir
  defp put_card_preview(socket) do
    changeset = socket.assigns.form.source
    title = Ecto.Changeset.get_field(changeset, :title)

    attrs = %{
      title: if(title in [nil, ""], do: "Untitled post", else: title),
      excerpt: Ecto.Changeset.get_field(changeset, :excerpt),
      published_on: socket.assigns.published_at && DateTime.to_date(socket.assigns.published_at),
      reading_time: socket.assigns.post.reading_time || 1
    }

    case SocialCard.post_card(attrs) do
      {:ok, png} -> assign(socket, :card_preview, "data:image/png;base64," <> Base.encode64(png))
      {:error, _reason} -> assign(socket, :card_preview, nil)
    end
  end
```

- [ ] **Step 4: Add the preview to the drawer template**

In the `Components.drawer` block (e.g. after the "Reading time · View on site" row),
add a social-card section:
```heex
        <div :if={@card_preview} class="border-t border-(--admin-border) pt-3">
          <div class="mb-2 text-[0.78rem] font-medium text-(--admin-text)">Social card</div>
          <img
            id="og-card-preview"
            src={@card_preview}
            alt="Social card preview"
            class="w-full rounded-lg border border-(--admin-border)"
          />
        </div>
```

- [ ] **Step 5: Run the test + suite**

Run: `mix test test/newton_web/live/admin/post_editor_live_test.exs` — PASS. Then `mix test` — green.

- [ ] **Step 6: Commit**

```bash
git add lib/newton_web/live/admin/post_live/editor.ex test/newton_web/live/admin/post_editor_live_test.exs
git commit -m "$(cat <<'EOF'
Preview the social card in the post editor drawer

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Cleanup + end-to-end verification

- [ ] **Step 1: Remove the now-unused Task.Supervisor** — the on-demand endpoint does no background work, so drop `{Task.Supervisor, name: Newton.TaskSupervisor}` (and its comment) from `lib/newton/application.ex`. `grep -rn "Newton.TaskSupervisor" lib test` returns nothing afterwards.

```bash
git add lib/newton/application.ex
git commit -m "$(cat <<'EOF'
Drop the unused Task.Supervisor (OG cards render on demand)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 2: precommit** — `mix precommit` green (format, compile, credo strict, dialyzer, tests, JS).

- [ ] **Step 3: Real-render check (PORT=4001)** — build assets, start the server, publish a post, then:
  - `curl -sI http://localhost:4001/og/posts/<slug>` → `200`, `content-type: image/png`, `cache-control: public…`.
  - `curl -s http://localhost:4001/og/posts/<slug> -o /tmp/og.png` → confirm 1200×630 PNG; open it and confirm it reads well.
  - `curl -s http://localhost:4001/posts/<slug>` → `og:image` is the absolute `/og/posts/<slug>` URL, `og:type=article`.
  - `curl -s http://localhost:4001/` → `og:image` is the absolute `/og-default.png`, `og:type=website`.
  - In the admin editor, open a post and click **Settings** → the drawer shows the rendered social card; reopening after editing the title reflects the change.

- [ ] **Step 4: Deploy/font note** — confirm `priv/fonts/Lora.ttf` + `priv/fonts/fonts.conf` ship in the release (they're under `priv/`) so Lora resolves on Linux/prod via `FONTCONFIG_FILE`. No Dockerfile font install needed.

- [ ] **Step 5: Commit any verification fixes** (only if needed):
```bash
git add -A
git commit -m "$(cat <<'EOF'
Fix issues found verifying OG cards

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Self-review notes

- **Spec coverage:** spike (Task 1, done); renderer + palette pick (Task 2); on-demand endpoint (Task 3); meta tags + default card + per-post assigns (Task 4); editor card preview (Task 5); cleanup + verification incl. the deploy/font note (Task 6). The stored-image/async machinery from the original spec is intentionally dropped — see the Architecture note and the spec's revised Section 3. The editor preview is an addition beyond the original spec (reuses `SocialCard.post_card/2`, no new public surface).
- **Consistency:** `Newton.SocialCard.post_card/2` is the only renderer entry point now (`default_card/1` removed); the endpoint, the editor preview, and the controller all pass `title`, `excerpt`, `published_on`, `reading_time`. The `/og/posts/:slug` route name matches between Task 3 (definition) and Task 4 (the `og:image` URL + post-controller test). `og-default.png` matches across the committed export, `static_paths`, the layout default, and the controller fallback. `Blog.get_published_post!/1` is the real Blog API (raises → 404). Date formatting is centralized in `Newton.Format.format_date/2`.

---

## Related work (separate from this plan)

The user is making the **main public site dark-only** — commenting out its light-mode theme support while **keeping light/dark in the admin**. This is why the cards locked to the dark palette. It's tracked separately from the OG-cards plan (its own change to the site's theme system); noted here only for context.
- **Risk handling:** the rendering-feasibility risk was retired in Task 1. The 406-on-image-Accept risk is handled by giving `/og` its own pipeline-less scope (Task 3). Render failure falls back to the static card rather than 500.
