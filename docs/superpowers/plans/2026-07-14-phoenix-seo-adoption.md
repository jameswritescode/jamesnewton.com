# phoenix_seo Adoption Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the hand-rolled og/twitter meta with phoenix_seo 0.3.0-rc protocol items — keeping the SocialCard image pipeline — gaining canonicals and Article/WebSite/Person JSON-LD, then deliberate per-page items for the non-post pages.

**Architecture:** One `NewtonWeb.SEO` module holds site defaults (as arity-1 config functions, so URLs use verified routes at render time); protocol `defimpl`s for `Newton.Blog.Post` and a small `NewtonWeb.SEO.Page` struct drive per-page tags; `<SEO.juice>` replaces the layout's title + og/twitter block. The og-image *generation* pipeline (`SocialCard`, `OgImageController`) is untouched.

**Tech Stack:** phoenix_seo 0.3.0-rc.0 (Elixir ≥1.17 required — met), its `:seo_jsonld` Mix compiler, Jason.

**Spec:** `docs/superpowers/specs/2026-07-14-phoenix-seo-adoption-design.md`

## Global Constraints

- Dependency pinned `{:phoenix_seo, "~> 0.3.0-rc.0"}`; compilers gain `[:seo_jsonld]`; `config :phoenix_seo, json_ld_types: [SEO.JSONLD.Article, SEO.JSONLD.WebSite, SEO.JSONLD.Person]` (NOT `:all`, NOT the `:google` default).
- **Parity is the gate:** existing og/twitter tag *values* must survive the swap byte-for-byte (the controller runs a before/after head-meta diff outside the tasks). Known-accepted additions: `<link rel="canonical">`, `og:image:width/height`, `og:image:alt`, `og:url` on non-post pages? — NO: og:url stays post-only in phase (a) (parity first; Page items add page URLs in phase b).
- Layout lines that STAY untouched: charset/viewport/csrf, theme-color, color-scheme comment+meta, favicons, `page_robots`, fonts, app.css/app.js, the anti-FOUC script. Only the `<.live_title>` block and the og/twitter meta block are replaced by `<SEO.juice>`.
- Title behavior preserved exactly: default "James Newton", dev `[DEV]` prefix via `NewtonWeb.Layouts.title_prefix/0`, page titles from `assigns[:page_title]`.
- Unpublished/preview posts keep the static `og-default.png` image (the on-demand card endpoint only serves published posts) and keep `page_robots` noindex.
- `Newton.SocialCard` and `NewtonWeb.OgImageController` are not modified.
- No narrating comments (AGENTS.md). Tests assert behaviors/contract values.
- Finish with `mix precommit`.

## File Structure

| File | Responsibility |
|---|---|
| `mix.exs` | dep + compilers |
| `config/config.exs` | `json_ld_types` |
| `lib/newton_web/seo.ex` | `NewtonWeb.SEO` (defaults) + `NewtonWeb.SEO.Page` struct + all `defimpl`s |
| `lib/newton_web/components/layouts/root.html.heex` | the swap |
| `lib/newton_web/controllers/post_controller.ex` | `put_og` → `SEO.assign` |
| six public controllers | phase (b) Page items |
| `test/newton_web/seo_test.exs` | protocol/build contracts |
| `test/newton_web/controllers/seo_meta_test.exs` | rendered-page contracts |

---

### Task 1: Wiring, `NewtonWeb.SEO`, and the Post implementation

**Files:**
- Modify: `mix.exs` (deps + `compilers:` in `project/0`)
- Modify: `config/config.exs`
- Create: `lib/newton_web/seo.ex`
- Test: `test/newton_web/seo_test.exs`

**Interfaces:**
- Produces: `NewtonWeb.SEO` (usable as `config={NewtonWeb.SEO.config()}`); `defimpl`s for `Newton.Blog.Post` of `SEO.OpenGraph.Build`, `SEO.Site.Build`, `SEO.Twitter.Build`, `SEO.JSONLD.Build`; struct `%NewtonWeb.SEO.Page{title: String.t(), description: String.t(), path: String.t()}` with the same four `defimpl`s (used by Tasks 2–3; Task 2 uses Post, Task 3 uses Page).

- [ ] **Step 1: Add the dependency and compiler**

In `mix.exs` `project/0`, add `compilers: [:seo_jsonld] ++ Mix.compilers(),` (alongside the existing keys); in `deps/0` add `{:phoenix_seo, "~> 0.3.0-rc.0"},`. In `config/config.exs` add:

```elixir
config :phoenix_seo,
  json_ld_types: [SEO.JSONLD.Article, SEO.JSONLD.WebSite, SEO.JSONLD.Person]
```

Run: `mix deps.get && mix compile`
Expected: compiles; the `:seo_jsonld` compiler generates the three types (+ auto-pulled ancestors) into `_build`.

- [ ] **Step 2: Write the failing tests**

Create `test/newton_web/seo_test.exs`:

```elixir
defmodule NewtonWeb.SEOTest do
  use NewtonWeb.ConnCase, async: true

  alias Newton.Blog

  defp post_fixture(attrs \\ %{}) do
    {:ok, post} =
      attrs
      |> Enum.into(%{
        slug: "seo-post-#{System.unique_integer([:positive])}",
        title: "SEO Post",
        body_markdown: "First paragraph as excerpt.",
        published_at: ~U[2026-04-17 12:00:00Z]
      })
      |> Blog.create_post()

    post
  end

  test "a published post builds article open graph with the live card image", %{conn: conn} do
    post = post_fixture()
    og = SEO.OpenGraph.Build.build(post, conn)

    assert og.title == post.title
    assert og.description == post.excerpt
    assert %SEO.OpenGraph.Article{} = og.detail
    assert og.detail.published_time
    assert og.url =~ "/posts/#{post.slug}"
    assert og.image.url =~ "/og/posts/#{post.slug}"
    assert og.image.width == 1200
    assert og.image.height == 630
    assert og.image.alt == post.title
  end

  test "an unpublished post falls back to the static default card", %{conn: conn} do
    post = post_fixture(%{published_at: nil, slug: "seo-draft"})
    og = SEO.OpenGraph.Build.build(post, conn)

    assert og.image.url =~ "/og-default.png"
  end

  test "a post's site build carries the clean canonical", %{conn: conn} do
    post = post_fixture()
    site = SEO.Site.Build.build(post, conn)

    assert site.canonical_url =~ "/posts/#{post.slug}"
    assert site.title == post.title
  end

  test "a post's JSON-LD is an Article with an embedded Person author", %{conn: conn} do
    post = post_fixture()
    [article] = List.wrap(SEO.JSONLD.Build.build(post, conn))

    assert article.headline == post.title
    assert article.author.name == "James Newton"
  end

  test "a Page item builds titled, self-canonical tags", %{conn: conn} do
    page = %NewtonWeb.SEO.Page{
      title: "Photos",
      description: "Photography from hikes and travels.",
      path: "/photos"
    }

    og = SEO.OpenGraph.Build.build(page, conn)
    site = SEO.Site.Build.build(page, conn)

    assert og.title == "Photos"
    assert og.description == "Photography from hikes and travels."
    assert site.canonical_url =~ "/photos"
  end

  test "the home Page emits WebSite and Person JSON-LD", %{conn: conn} do
    page = %NewtonWeb.SEO.Page{title: "James Newton", description: "d", path: "/"}
    modules = page |> SEO.JSONLD.Build.build(conn) |> List.wrap() |> Enum.map(& &1.__struct__)
    assert SEO.JSONLD.WebSite in modules
    assert SEO.JSONLD.Person in modules
  end
end
```

(If the generated JSON-LD builders return maps rather than structs, adjust the two JSON-LD tests to match on `"@type"` / `:headline` keys accordingly and note it in your report.)

- [ ] **Step 3: Run tests to verify they fail**

Run: `mix test test/newton_web/seo_test.exs`
Expected: FAIL — `NewtonWeb.SEO` / defimpls undefined.

- [ ] **Step 4: Implement**

Create `lib/newton_web/seo.ex`:

```elixir
defmodule NewtonWeb.SEO do
  use NewtonWeb, :verified_routes

  use SEO,
    json_library: Jason,
    site: &__MODULE__.site_config/1,
    open_graph: &__MODULE__.open_graph_config/1,
    twitter: &__MODULE__.twitter_config/1

  def site_config(_conn) do
    SEO.Site.build(
      default_title: "James Newton",
      title_prefix: NewtonWeb.Layouts.title_prefix(),
      description: "Software & Photography"
    )
  end

  def open_graph_config(_conn) do
    SEO.OpenGraph.build(
      site_name: "James Newton",
      type: :website,
      image: SEO.OpenGraph.Image.build(url: url(~p"/og-default.png"))
    )
  end

  def twitter_config(_conn) do
    SEO.Twitter.build(
      card: :summary_large_image,
      title: "James Newton",
      description: "Software & Photography",
      image: url(~p"/og-default.png")
    )
  end
end

defmodule NewtonWeb.SEO.Page do
  defstruct [:title, :description, :path, json_ld: []]
end

defimpl SEO.OpenGraph.Build, for: Newton.Blog.Post do
  use NewtonWeb, :verified_routes

  def build(post, _conn) do
    SEO.OpenGraph.build(
      title: post.title,
      description: post.excerpt,
      url: url(~p"/posts/#{post.slug}"),
      detail: SEO.OpenGraph.Article.build(published_time: post.published_at),
      image: image(post)
    )
  end

  defp image(%{published_at: nil}) do
    SEO.OpenGraph.Image.build(url: url(~p"/og-default.png"))
  end

  defp image(post) do
    SEO.OpenGraph.Image.build(
      url: url(~p"/og/posts/#{post.slug}"),
      width: 1200,
      height: 630,
      alt: post.title
    )
  end
end

defimpl SEO.Site.Build, for: Newton.Blog.Post do
  use NewtonWeb, :verified_routes

  def build(post, _conn) do
    SEO.Site.build(
      title: post.title,
      description: post.excerpt,
      canonical_url: url(~p"/posts/#{post.slug}")
    )
  end
end

defimpl SEO.Twitter.Build, for: Newton.Blog.Post do
  def build(post, _conn) do
    SEO.Twitter.build(title: post.title, description: post.excerpt)
  end
end

defimpl SEO.JSONLD.Build, for: Newton.Blog.Post do
  use NewtonWeb, :verified_routes

  def build(post, _conn) do
    SEO.JSONLD.Article.build(%{
      headline: post.title,
      description: post.excerpt,
      date_published: post.published_at,
      author: SEO.JSONLD.Person.build(%{name: "James Newton", url: url(~p"/")}),
      main_entity_of_page: url(~p"/posts/#{post.slug}")
    })
  end
end

defimpl SEO.OpenGraph.Build, for: NewtonWeb.SEO.Page do
  use NewtonWeb, :verified_routes

  def build(page, _conn) do
    SEO.OpenGraph.build(title: page.title, description: page.description)
  end
end

defimpl SEO.Site.Build, for: NewtonWeb.SEO.Page do
  use NewtonWeb, :verified_routes

  def build(page, _conn) do
    SEO.Site.build(
      title: page.title,
      description: page.description,
      canonical_url: url(new_uri(), page.path)
    )
  end

  defp new_uri, do: %URI{}
end

defimpl SEO.Twitter.Build, for: NewtonWeb.SEO.Page do
  def build(page, _conn) do
    SEO.Twitter.build(title: page.title, description: page.description)
  end
end

defimpl SEO.JSONLD.Build, for: NewtonWeb.SEO.Page do
  use NewtonWeb, :verified_routes

  def build(%{path: "/"} = page, _conn) do
    person = SEO.JSONLD.Person.build(%{name: "James Newton", url: url(~p"/")})

    [
      SEO.JSONLD.WebSite.build(%{
        name: "James Newton",
        url: url(~p"/"),
        description: page.description
      }),
      person
    ]
  end

  def build(_page, _conn), do: nil
end
```

Implementation notes for the transcriber (resolve, don't guess):
- `SEO.Site.build/1`'s title-prefix field: confirm the exact key by reading
  `deps/phoenix_seo/lib/seo/site.ex` (`:title_prefix` per the 0.3.0-rc source's
  render, which calls `<.live_title prefix={@item.title_prefix} ...>`). If the
  struct key differs, use the struct's actual key and note it.
- The Page canonical: `url(new_uri(), page.path)` is a sketch — verified
  routes' `url/1` + string path won't compose that way. Use
  `NewtonWeb.Endpoint.url() <> page.path` (or `Phoenix.VerifiedRoutes.url/2`
  correctly) — whatever produces `https://host/photos`. Assert via the test.
- If `SEO.JSONLD.*.build/1` takes keyword lists instead of maps, adapt; the
  tests define the contract (headline/author/name reachable).

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/newton_web/seo_test.exs`
Expected: 6 tests, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add mix.exs mix.lock config/config.exs lib/newton_web/seo.ex test/newton_web/seo_test.exs
git commit -m "Add phoenix_seo wiring, site defaults, and Post/Page SEO builders"
```

---

### Task 2: The swap (layout + post controller) with contract tests

**Files:**
- Modify: `lib/newton_web/components/layouts/root.html.heex`
- Modify: `lib/newton_web/controllers/post_controller.ex`
- Test: `test/newton_web/controllers/seo_meta_test.exs` (create)

**Interfaces:**
- Consumes: Task 1's `NewtonWeb.SEO.config/0-1` and the Post defimpls; `SEO.assign/2`, `SEO.juice` component.

- [ ] **Step 1: Write the failing tests**

Create `test/newton_web/controllers/seo_meta_test.exs`:

```elixir
defmodule NewtonWeb.SeoMetaTest do
  use NewtonWeb.ConnCase, async: true

  alias Newton.Blog

  defp published_post do
    {:ok, post} =
      Blog.create_post(%{
        slug: "seo-meta-post",
        title: "SEO Meta Post",
        body_markdown: "The excerpt paragraph.",
        published_at: ~U[2026-04-17 12:00:00Z]
      })

    post
  end

  defp meta(html, property) do
    case Regex.run(~r/<meta[^>]*property="#{property}"[^>]*content="([^"]*)"/, html) do
      [_, content] -> content
      _ -> nil
    end
  end

  test "a post page emits the full article tag set", %{conn: conn} do
    post = published_post()
    html = conn |> get(~p"/posts/#{post.slug}") |> html_response(200)

    assert meta(html, "og:title") == post.title
    assert meta(html, "og:description") == post.excerpt
    assert meta(html, "og:type") == "article"
    assert meta(html, "og:url") =~ "/posts/#{post.slug}"
    assert meta(html, "og:image") =~ "/og/posts/#{post.slug}"
    assert meta(html, "og:image:width") == "1200"
    assert html =~ ~r/<link rel="canonical" href="[^"]*\/posts\/#{post.slug}"/
    assert html =~ ~s(<title)
    assert html =~ post.title
  end

  test "a post page emits parseable Article JSON-LD despite the strict CSP", %{conn: conn} do
    post = published_post()
    html = conn |> get(~p"/posts/#{post.slug}") |> html_response(200)

    [_, json] = Regex.run(~r/<script type="application\/ld\+json"[^>]*>(.*?)<\/script>/s, html)
    decoded = Jason.decode!(json)
    article = if is_list(decoded), do: Enum.find(decoded, &(&1["@type"] == "Article")), else: decoded
    assert article["@type"] == "Article"
    assert article["headline"] == post.title
  end

  test "non-post pages emit the site defaults", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert meta(html, "og:title") || meta(html, "og:site_name") == "James Newton"
    assert meta(html, "og:image") =~ "/og-default.png"
    assert html =~ ~r/<meta[^>]*name="twitter:card"[^>]*content="summary_large_image"/
  end

  test "a preview URL keeps noindex and the clean canonical", %{conn: conn} do
    {:ok, post} =
      Blog.create_post(%{slug: "preview-post", title: "Preview", body_markdown: "Draft body."})

    {:ok, post} = Blog.enable_preview(post)
    html = conn |> get(~p"/posts/#{post.slug}?p=#{post.preview_token}") |> html_response(200)

    assert html =~ ~r/<meta[^>]*name="robots"[^>]*content="noindex"/
    assert html =~ ~r/<link rel="canonical" href="[^"]*\/posts\/preview-post"/
    refute html =~ "?p="
  end
end
```

(The `refute html =~ "?p="` may be too broad if the body echoes the URL — scope it to the canonical link line if it misfires. `enable_preview` exists in `Newton.Blog`; check its return shape and the token field name — `preview_token` — before relying on it.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/newton_web/controllers/seo_meta_test.exs`
Expected: FAIL — no canonical/JSON-LD; og tags come from the old layout block (some may pass; the canonical/JSON-LD assertions must fail).

- [ ] **Step 3: The layout swap**

In `lib/newton_web/components/layouts/root.html.heex`, replace ONLY these regions:

1. The title block:
```heex
    <.live_title default="James Newton" prefix={title_prefix()}>
      {assigns[:page_title]}
    </.live_title>
```
2. The og/twitter meta block (the `og:type`/`og:site_name`/`og:title`/`og:description`/`og:url`/`og:image` and four `twitter:*` meta lines).

Both are replaced by a single:

```heex
    <SEO.juice conn={@conn} config={NewtonWeb.SEO.config()} page_title={assigns[:page_title]} />
```

Everything else in the head stays byte-identical: charset/viewport/csrf, theme-color + color-scheme, favicons, `page_robots` meta, font preconnects/stylesheet, app.css/app.js, the anti-FOUC script.

- [ ] **Step 4: The controller swap**

In `lib/newton_web/controllers/post_controller.ex`: delete `put_og/2` entirely; both `show/2` branches replace `|> put_og(post)` with `|> SEO.assign(post)`. Nothing else changes (the preview branch keeps `page_robots`).

- [ ] **Step 5: Run the tests**

Run: `mix test test/newton_web/controllers/seo_meta_test.exs test/newton_web/controllers/`
Expected: the new file passes; every pre-existing controller test passes unchanged (the links/og-image suites don't assert the old meta).

- [ ] **Step 6: Commit**

```bash
git add lib/newton_web/components/layouts/root.html.heex lib/newton_web/controllers/post_controller.ex test/newton_web/controllers/seo_meta_test.exs
git commit -m "Serve og/twitter/canonical/JSON-LD through phoenix_seo"
```

**Controller gate (not the implementer's step):** the session controller runs the before/after head-meta parity diff across the seven public routes here and reviews it line-by-line before Task 3 dispatches.

---

### Task 3: Phase (b) — deliberate per-page items

**Files:**
- Modify: `lib/newton_web/controllers/page_controller.ex` (home, resume)
- Modify: `lib/newton_web/controllers/post_controller.ex` (index)
- Modify: `lib/newton_web/controllers/reading_controller.ex`
- Modify: `lib/newton_web/controllers/photo_controller.ex`
- Modify: `lib/newton_web/controllers/links_controller.ex`
- Test: `test/newton_web/controllers/seo_meta_test.exs` (extend)

**Interfaces:**
- Consumes: `%NewtonWeb.SEO.Page{}` + its defimpls (Task 1), `SEO.assign/2`.

- [ ] **Step 1: Write the failing tests**

Append to `test/newton_web/controllers/seo_meta_test.exs`:

```elixir
  for {path, fragment} <- [
        {"/", "thinks a lot about how we build"},
        {"/photos", "Photography from"},
        {"/reading", "reading"},
        {"/links", "elsewhere"},
        {"/resume", "resume"},
        {"/posts", "Writing"}
      ] do
    test "#{path} emits a deliberate description and canonical", %{conn: conn} do
      html = conn |> get(unquote(path)) |> html_response(200)

      description =
        Regex.run(~r/<meta[^>]*property="og:description"[^>]*content="([^"]*)"/, html)

      assert description, "no og:description on #{unquote(path)}"
      [_, content] = description
      assert content =~ ~r/#{unquote(fragment)}/i
      assert html =~ ~r/<link rel="canonical" href="[^"]*#{Regex.escape(unquote(path))}"/
    end
  end
```

(Adjust the expected fragments to the final copy below if wording shifts; the assertions pin *deliberateness* — each page's description differs from the bare site tagline — plus a self-canonical.)

- [ ] **Step 2: Run to verify they fail**

Run: `mix test test/newton_web/controllers/seo_meta_test.exs`
Expected: the six new tests FAIL (pages emit the default description, no page canonical).

- [ ] **Step 3: Assign Page items**

The copy (James approves at tophat; adjust tests if he edits):

| Page | title | description |
|---|---|---|
| `/` | James Newton | Software engineer at Mark OS who thinks a lot about how we build things and why — the tools, the trade-offs, and the quiet decisions. |
| `/posts` | Posts | Writing on software: the tools, the trade-offs, and the craft. |
| `/reading` | Reading | Books read and listened to, with occasional notes. |
| `/photos` | Photos | Photography from hikes and travels — lakes, coasts, and mountains. |
| `/links` | Links | Where to find me elsewhere on the internet. |
| `/resume` | Resume | Experience and work history. |

Each controller action gains one pipe before `render`, e.g. for photos:

```elixir
    conn
    |> SEO.assign(%NewtonWeb.SEO.Page{
      title: "Photos",
      description: "Photography from hikes and travels — lakes, coasts, and mountains.",
      path: "/photos"
    })
    |> render(:index, ...existing args...)
```

Home (`page_controller.ex` `home/2`) uses the `/` Page — which also triggers the `WebSite` + `Person` JSON-LD from Task 1's defimpl. Read each controller before editing; keep existing `page_title` args (juice prefers the item title, and both are set consistently here).

- [ ] **Step 4: Run tests, full gate**

Run: `mix test test/newton_web/`
Expected: all pass.

Run: `mix precommit`
Expected: clean.

- [ ] **Step 5: Commit**

```bash
git add lib/newton_web/controllers test/newton_web/controllers/seo_meta_test.exs
git commit -m "Give every public page a deliberate SEO item"
```

---

## Post-plan notes

- The controller's parity artifacts live in `tmp/seo-parity/` (before/after per route); the reviewed diff is the phase-(a) exit gate.
- James's tophat: unfurl a post URL in Slack/iMessage; approve the phase-(b) copy.
- Deploy scope: `fly deploy` ships the working tree; confirm with James.
