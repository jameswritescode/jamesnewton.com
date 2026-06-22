# OG / Twitter Preview Cards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Note:** Task 1 (the spike) and Task 2 (card visual design) involve judgment/iteration and are best executed inline.

**Goal:** Rich link previews — OG/Twitter meta tags on every public page, plus a per-post card image (title + date · reading time) regenerated in the background on title/date changes, and a static default card for everything else.

**Architecture:** A `Newton.SocialCard` renderer (libvips via the `image` lib) draws 1200×630 PNGs using a repo-bundled Lora font resolved through fontconfig. Posts gain an `og_image_key`; the Blog context regenerates the card asynchronously (a `Task.Supervisor`) when the title or publish date changes, storing it on the media volume. The public layout emits OG/Twitter tags from per-page assigns.

**Tech Stack:** `image` 0.69 (vix/libvips, Pango text), fontconfig + an in-repo Lora TTF, Ecto, `Task.Supervisor`, `Newton.Gallery.Storage`, HEEx meta tags.

**Reference spec:** `docs/superpowers/specs/2026-06-21-og-preview-cards-design.md`

**Session constraints:** Commit signed (1Password; if it fails, `--no-gpg-sign` then re-sign later). Trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`. Don't modify `config/dev.exs`. Servers on PORT=4001.

---

## Task 1: Feasibility spike — render Lora text to a PNG

**Goal:** prove `image`/vix can render Lora text in this environment before building anything. This task is a **decision gate**.

**Files:**
- Modify: `mix.exs` (add `{:image, "~> 0.69"}`)
- Create: `priv/fonts/Lora.ttf` (committed — runtime font), `priv/fonts/fonts.conf`
- Modify: `config/runtime.exs` (fontconfig env), `lib/newton/application.ex` (Task.Supervisor — added here so it's ready)

- [ ] **Step 1: Add the dependency**

In `mix.exs` deps add `{:image, "~> 0.69"}`. Run `mix deps.get` (pulls `vix`).

- [ ] **Step 2: Ship the Lora font + fontconfig**

Copy the Lora variable font into the repo (it must ship in the release, so it is
committed, not gitignored):

```bash
mkdir -p priv/fonts
curl -fsSL "https://github.com/google/fonts/raw/main/ofl/lora/Lora%5Bwght%5D.ttf" -o priv/fonts/Lora.ttf
```

Create `priv/fonts/fonts.conf` (a fontconfig config that adds the repo font dir and
still includes the system fonts):
```xml
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <dir>FONTS_DIR</dir>
  <include ignore_missing="yes">/etc/fonts/fonts.conf</include>
  <cachedir>/tmp/newton-fontconfig</cachedir>
</fontconfig>
```
(`FONTS_DIR` is replaced with the absolute path at boot — see Step 3.)

- [ ] **Step 3: Point fontconfig at it before vix loads**

vix initializes libvips/fontconfig on first use, so the env must be set early. In
`config/runtime.exs`, near the top (runs before the supervision tree starts), add:
```elixir
# Make the repo-bundled Lora resolvable by libvips/Pango (social card rendering).
fonts_dir = Path.join(:code.priv_dir(:newton), "fonts")
conf_src = Path.join(fonts_dir, "fonts.conf")
conf_out = Path.join(System.tmp_dir!(), "newton-fonts.conf")
File.write!(conf_out, String.replace(File.read!(conf_src), "FONTS_DIR", fonts_dir))
System.put_env("FONTCONFIG_FILE", conf_out)
```
(`:code.priv_dir/1` resolves both in dev and in a release.)

- [ ] **Step 4: Add the Task.Supervisor (used in Task 3)**

In `lib/newton/application.ex`, add to `children` (before `NewtonWeb.Endpoint`):
```elixir
      {Task.Supervisor, name: Newton.TaskSupervisor},
```

- [ ] **Step 5: Spike — render "Hello" in Lora**

In `iex -S mix`:
```elixir
{:ok, canvas} = Image.new(600, 200, color: "#aa4040")
{:ok, text} = Image.Text.text("Hello", font: "Lora", font_size: 80, text_fill_color: "#ffe8d6")
{:ok, composed} = Image.compose(canvas, text, x: 40, y: 50)
Image.write(composed, "/tmp/spike.png")
```
Open `/tmp/spike.png`. **Decision gate:**
- If it renders with a serif (Lora) → vix text works; proceed to Task 2 with the
  `image` renderer.
- If `Image.Text.text` errors (no Pango/text support) or the font is wrong, try
  font strings `"Lora SemiBold"` / `"Lora 600"`; if still broken, **switch the
  renderer plan to the Node fallback**: `Newton.SocialCard` shells to a
  `assets/social_card/render.mjs` (fontkit + sharp, like the favicon) that takes
  title/date/read + palette and emits a PNG. Note the decision in the commit
  message. (Tasks 3–5 are unchanged either way.)

- [ ] **Step 6: Commit**

```bash
git add mix.exs mix.lock priv/fonts/Lora.ttf priv/fonts/fonts.conf config/runtime.exs lib/newton/application.ex
git commit -m "$(cat <<'EOF'
Add image lib, bundled Lora font, and a Task.Supervisor for social cards

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: The card renderer (`Newton.SocialCard`) + pick a palette

**Files:**
- Create: `lib/newton/social_card.ex`
- Test: `test/newton/social_card_test.exs`

- [ ] **Step 1: Write the failing test**

`test/newton/social_card_test.exs`:
```elixir
defmodule Newton.SocialCardTest do
  use ExUnit.Case, async: true
  alias Newton.SocialCard

  defp dims(binary) do
    {:ok, img} = Image.from_binary(binary)
    {Image.width(img), Image.height(img)}
  end

  test "post_card renders a 1200x630 PNG" do
    {:ok, png} = SocialCard.post_card(%{title: "A Short Title", published_on: ~D[2026-04-17], reading_time: 5})
    assert <<0x89, "PNG", _::binary>> = png
    assert dims(png) == {1200, 630}
  end

  test "post_card handles a very long title without overflowing" do
    long = String.duplicate("Resilient ", 30)
    {:ok, png} = SocialCard.post_card(%{title: long, published_on: ~D[2026-04-17], reading_time: 12})
    assert dims(png) == {1200, 630}
  end

  test "default_card renders a 1200x630 PNG" do
    {:ok, png} = SocialCard.default_card()
    assert dims(png) == {1200, 630}
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/newton/social_card_test.exs` — FAIL (module missing).

- [ ] **Step 3: Implement the renderer**

Create `lib/newton/social_card.ex`. Compose a 1200×630 card: background fill, the
title (Lora, wrapped to ~1040px, auto-shrunk for long titles), a secondary
date·reading-time line, and a footer. Palette is a parameter (default chosen in
Step 5).

```elixir
defmodule Newton.SocialCard do
  @moduledoc "Renders 1200x630 Open Graph card PNGs (libvips via the image lib)."

  @width 1200
  @height 630
  @pad 80

  @palettes %{
    red: %{bg: "#aa4040", fg: "#ffe8d6", muted: "#f3c9b0"},
    dark: %{bg: "#151311", fg: "#eed3ba", muted: "#ad9987"}
  }
  @default_palette :red

  @spec post_card(%{title: String.t(), published_on: Date.t() | nil, reading_time: integer()}, atom()) ::
          {:ok, binary()} | {:error, term()}
  def post_card(post, palette \\ @default_palette) do
    p = Map.fetch!(@palettes, palette)
    secondary = [format_date(post.published_on), "#{post.reading_time} min read"] |> Enum.reject(&(&1 == "")) |> Enum.join(" · ")

    with {:ok, canvas} <- Image.new(@width, @height, color: p.bg),
         {:ok, title} <- title_text(post.title, p),
         {:ok, sub} <- Image.Text.text(secondary, font: "Lora", font_size: 30, text_fill_color: p.muted),
         {:ok, foot} <- Image.Text.text("jamesnewton.com", font: "Lora", font_size: 26, text_fill_color: p.muted),
         {:ok, c1} <- Image.compose(canvas, title, x: @pad, y: 150),
         {:ok, c2} <- Image.compose(c1, sub, x: @pad, y: 470),
         {:ok, c3} <- Image.compose(c2, foot, x: @pad, y: @height - @pad - 26) do
      Image.write(c3, :memory, suffix: ".png")
    end
  end

  @spec default_card(atom()) :: {:ok, binary()} | {:error, term()}
  def default_card(palette \\ @default_palette) do
    p = Map.fetch!(@palettes, palette)

    with {:ok, canvas} <- Image.new(@width, @height, color: p.bg),
         {:ok, name} <- Image.Text.text("James Newton", font: "Lora", font_size: 96, text_fill_color: p.fg),
         {:ok, tag} <- Image.Text.text("Software, writing, and the occasional photo.", font: "Lora", font_size: 34, text_fill_color: p.muted),
         {:ok, c1} <- Image.compose(canvas, name, x: @pad, y: 230),
         {:ok, c2} <- Image.compose(c1, tag, x: @pad, y: 360) do
      Image.write(c2, :memory, suffix: ".png")
    end
  end

  # Title: wrap to the content width; auto-shrink the font for long titles so it
  # always fits the card. `Image.Text.text` supports `width:` (wrap) + `height:`.
  defp title_text(title, p) do
    Image.Text.text(title,
      font: "Lora",
      font_weight: 600,
      font_size: title_size(title),
      text_fill_color: p.fg,
      width: @width - 2 * @pad,
      align: :left
    )
  end

  defp title_size(title) when byte_size(title) > 90, do: 52
  defp title_size(title) when byte_size(title) > 50, do: 66
  defp title_size(_), do: 84

  defp format_date(nil), do: ""
  defp format_date(%Date{} = d), do: Calendar.strftime(d, "%b %-d, %Y")
end
```

Note: the exact `Image.Text.text` options (`font_weight`, `width`, `align`,
`:memory` write) are per the `image` 0.69 docs confirmed in the Task-1 spike;
adjust names to match (e.g. wrapping may need `Image.Text` opts or composing onto
a fixed-width box). The behavioral contract (returns a 1200×630 PNG, long titles
fit) is what the tests pin.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/newton/social_card_test.exs` — PASS.

- [ ] **Step 5: Sample both palettes (inline visual — pick the color scheme)**

In `iex -S mix`, render a sample post card in both palettes and the default card:
```elixir
{:ok, r} = Newton.SocialCard.post_card(%{title: "Three Ways to Retry", published_on: ~D[2026-04-17], reading_time: 5}, :red); File.write!("/tmp/card-red.png", r)
{:ok, d} = Newton.SocialCard.post_card(%{title: "Three Ways to Retry", published_on: ~D[2026-04-17], reading_time: 5}, :dark); File.write!("/tmp/card-dark.png", d)
{:ok, df} = Newton.SocialCard.default_card(:red); File.write!("/tmp/card-default.png", df)
```
Send `/tmp/card-red.png`, `/tmp/card-dark.png`, `/tmp/card-default.png` to the
user; they pick the palette. Set `@default_palette` to their choice. Tune layout
(positions/sizes) until it reads well, re-render, re-confirm.

- [ ] **Step 6: Commit**

```bash
git add lib/newton/social_card.ex test/newton/social_card_test.exs
git commit -m "$(cat <<'EOF'
Add the social card renderer

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Data model, storage & async regeneration

**Files:**
- Create: `priv/repo/migrations/*_add_og_image_key_to_posts.exs`
- Modify: `lib/newton/blog/post.ex` (field), `lib/newton/blog.ex` (trigger + regen)
- Test: `test/newton/blog_test.exs`

- [ ] **Step 1: Write the failing test**

Append to `test/newton/blog_test.exs`:
```elixir
  describe "og image regeneration" do
    test "regenerate_og_image stores a card and sets the key" do
      {:ok, post} =
        Blog.create_post(%{slug: "og1", title: "OG One", body_markdown: "Body.", published_at: ~U[2026-01-01 00:00:00Z]})

      {:ok, post} = Blog.regenerate_og_image(post)
      assert is_binary(post.og_image_key)
      assert File.exists?(Path.join(Application.fetch_env!(:newton, :media_root), post.og_image_key))
    end

    test "regenerating replaces and deletes the old key" do
      {:ok, post} =
        Blog.create_post(%{slug: "og2", title: "OG Two", body_markdown: "Body.", published_at: ~U[2026-01-01 00:00:00Z]})

      {:ok, post} = Blog.regenerate_og_image(post)
      old = post.og_image_key
      {:ok, post} = Blog.regenerate_og_image(post)
      refute post.og_image_key == old
      refute File.exists?(Path.join(Application.fetch_env!(:newton, :media_root), old))
    end
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/newton/blog_test.exs` — FAIL (no column/function).

- [ ] **Step 3: Migration + field**

`mix ecto.gen.migration add_og_image_key_to_posts`:
```elixir
def change do
  alter table(:posts) do
    add :og_image_key, :string
  end
end
```
Run `mix ecto.migrate`. In `lib/newton/blog/post.ex` add `field :og_image_key, :string`
(after `:preview_token`); keep it OUT of `cast/2` (server-set only).

- [ ] **Step 4: regenerate_og_image + async trigger**

In `lib/newton/blog.ex` add (alias `Newton.SocialCard` and `Newton.Gallery.Storage`):
```elixir
  @spec regenerate_og_image(%Post{}) :: {:ok, %Post{}} | {:error, term()}
  def regenerate_og_image(%Post{} = post) do
    with {:ok, png} <-
           SocialCard.post_card(%{
             title: post.title,
             published_on: post.published_at && DateTime.to_date(post.published_at),
             reading_time: post.reading_time || 1
           }),
         tmp = Path.join(System.tmp_dir!(), "og-#{System.unique_integer([:positive])}.png"),
         :ok <- File.write(tmp, png),
         {:ok, key} <- Storage.store(tmp, "og.png") do
      old = post.og_image_key
      {:ok, updated} = post |> Ecto.Changeset.change(og_image_key: key) |> Repo.update()
      File.rm(tmp)
      if old, do: Storage.delete(old)
      {:ok, updated}
    end
  end

  # Fire-and-forget OG regen when the public-facing title/date changed.
  defp maybe_regenerate_og(%Post{published_at: nil}, _changeset), do: :ok

  defp maybe_regenerate_og(%Post{} = post, changeset) do
    if Map.has_key?(changeset.changes, :title) or Map.has_key?(changeset.changes, :published_at) or
         is_nil(post.og_image_key) do
      Task.Supervisor.start_child(Newton.TaskSupervisor, fn ->
        try do
          regenerate_og_image(post)
        rescue
          e -> require Logger; Logger.error("OG card regen failed: #{inspect(e)}")
        end
      end)
    end

    :ok
  end
```
Wire it into `create_post`/`update_post` (capture the changeset so changes are visible):
```elixir
  def create_post(attrs) do
    changeset = Post.changeset(%Post{}, attrs)

    with {:ok, post} <- Repo.insert(changeset) do
      maybe_regenerate_og(post, changeset)
      {:ok, post}
    end
  end

  def update_post(%Post{} = post, attrs) do
    changeset = Post.changeset(post, attrs)

    with {:ok, updated} <- Repo.update(changeset) do
      maybe_regenerate_og(updated, changeset)
      {:ok, updated}
    end
  end
```

- [ ] **Step 5: Run the tests + suite**

Run: `mix test test/newton/blog_test.exs` — PASS. Then `mix test` — green. (The
async trigger isn't directly asserted; `regenerate_og_image/1` is tested
synchronously. Confirm the editor tests still pass — `update_post` now also spawns
a task; in test the task runs against the test sandbox, which is fine since the
parent owns the connection. If sandbox ownership errors appear, have
`maybe_regenerate_og` no-op under `:test` env, OR allow the task via
`Ecto.Adapters.SQL.Sandbox.allow`. Prefer: skip the async spawn in tests via
`Application.get_env(:newton, :regenerate_og_async, true)` set false in
`config/test.exs`, and test `regenerate_og_image/1` directly.)

- [ ] **Step 6: Commit**

```bash
git add priv/repo/migrations lib/newton/blog/post.ex lib/newton/blog.ex test/newton/blog_test.exs config/test.exs
git commit -m "$(cat <<'EOF'
Regenerate a post's OG card on title or publish-date change

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Meta tags + default card + controller assigns

**Files:**
- Create (generated, committed): `priv/static/og-default.png`
- Modify: `lib/newton_web.ex` (static_paths), `lib/newton_web/components/layouts/root.html.heex`, `lib/newton_web/controllers/post_controller.ex`
- Test: `test/newton_web/controllers/post_controller_test.exs`, `test/newton_web/controllers/page_controller_test.exs`

- [ ] **Step 1: Generate + commit the default card**

In `iex -S mix` (using the chosen palette): `{:ok, p} = Newton.SocialCard.default_card(); File.write!("priv/static/og-default.png", p)`. Add `og-default.png` to `static_paths/0` in `lib/newton_web.ex`.

- [ ] **Step 2: Write the failing controller tests**

In `test/newton_web/controllers/post_controller_test.exs` (a published post exists in setup):
```elixir
  test "a published post head has OG/Twitter tags", %{conn: conn} do
    html = conn |> get(~p"/posts/three-ways-to-retry") |> html_response(200)
    assert html =~ ~s(property="og:title")
    assert html =~ "Three Ways to Retry"
    assert html =~ ~s(property="og:type" content="article")
    assert html =~ ~s(name="twitter:card" content="summary_large_image")
    assert html =~ ~s(property="og:image")
    assert html =~ "http"  # absolute image url
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

In `lib/newton_web/components/layouts/root.html.heex` `<head>`, after the favicon
links, add (absolute URLs via the endpoint):
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
(`@conn` is present in the controller-rendered public layout. `url(~p"/og-default.png")`
yields the absolute URL via the endpoint host.)

- [ ] **Step 5: Set the post OG assigns**

In `lib/newton_web/controllers/post_controller.ex` `show/2`, add the OG assigns for
both branches (a small private helper):
```elixir
  defp put_og(conn, post) do
    image =
      if post.og_image_key,
        do: NewtonWeb.Endpoint.url() <> "/media/" <> post.og_image_key,
        else: url(~p"/og-default.png")

    conn
    |> assign(:og_type, "article")
    |> assign(:og_title, post.title)
    |> assign(:og_description, post.excerpt)
    |> assign(:og_url, url(~p"/posts/#{post.slug}"))
    |> assign(:og_image, image)
  end
```
and call `put_og(conn, post)` before `render(...)` in each branch (drafts/previews
get the default image via the nil `og_image_key`).

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

## Task 5: End-to-end verification

- [ ] **Step 1: precommit** — `mix precommit` green (format, compile, credo strict, dialyzer, tests, JS).

- [ ] **Step 2: Real-render check (PORT=4001)** — build assets, start the server,
  create/publish a post in the admin, wait for the async task, then `curl` the
  post page and confirm `og:image` points at a `/media/<key>` that returns a
  1200×630 PNG (fetch it, check dims). Confirm a non-post page's `og:image` is the
  default card. Open both card images and confirm they read well.

- [ ] **Step 3: (Optional) deploy note** — confirm `priv/fonts/Lora.ttf` and
  `priv/fonts/fonts.conf` are included in the release (they are, under `priv/`), so
  Lora resolves in prod. No Dockerfile font install needed.

- [ ] **Step 4: Commit any verification fixes** (only if needed):
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

- **Spec coverage:** spike (Task 1); renderer + palette pick (Task 2); og_image_key
  + storage + async title/date trigger (Task 3); meta tags + default card +
  per-post assigns (Task 4); verification incl. the deploy/font note (Task 5).
  Color-scheme decision is resolved in Task 2 Step 5 (visual sample). All spec
  sections covered.
- **Risk handling:** the rendering-feasibility risk is isolated to Task 1 (decision
  gate) with the Node fallback documented; the exact `Image.Text` option names are
  confirmed in the spike before Task 2 relies on them. The test-sandbox interaction
  of the async task is handled in Task 3 Step 5 (disable async in test; test the
  sync core).
- **Consistency:** `Newton.SocialCard.post_card/2`/`default_card/1` signatures are
  identical across Tasks 2–4; `og_image_key` is the same field name in the
  migration, schema, regen, and controller; `Newton.TaskSupervisor` is created in
  Task 1 and used in Task 3; the default image path `og-default.png` matches across
  generation, `static_paths`, and the layout default.
