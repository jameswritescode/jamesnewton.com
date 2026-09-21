# Admin Pages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a **Pages** section to the admin — editable, markdown-authored standalone pages served at top-level `/:slug` — as a new content type alongside posts, reading, and photos.

**Architecture:** A dedicated `Newton.Pages` context with its own `Page`/`PageImage` mirror tables, a public catch-all `PageContentController`, and a lean `PageLive.Editor`. Genuinely shared behavior is extracted into shared modules that the **post** editor is refactored to consume *first* (behind its existing green tests), and the page editor then builds on the same shared code — never a fork of the post editor.

**Tech Stack:** Phoenix 1.8 / LiveView, Ecto/Postgres, CodeMirror colocated JS hook (already generic), Tailwind v4.

**Spec:** `docs/superpowers/specs/2026-09-18-admin-pages-design.md` (read it alongside this plan).

## Global Constraints

- **Autosave sharing decision (locked):** Extract only the *clean core* of the autosave engine into a shared module both editors call; each editor keeps its own thin persist function and its own gate (posts gate on `published_at == nil`, pages gate on `published == false`). Do **not** parameterize a single engine over the post-only concerns (autofill, `PublicationNotifier`, preview tokens).
- **Every extraction lands behind the existing post tests first.** Refactor posts to consume the shared version and keep the whole suite green *before* pages uses it. The post tests are the regression guard for the refactor.
- **`body_html` is `NOT NULL` and is never cast.** The page changeset must coerce a missing `body_markdown` to `""` (`ensure_body`) and render `body_html` from it, exactly as `Post.changeset/2` does, or empty-draft inserts fail.
- **`page_images.page_id` FK uses `on_delete: :delete_all`.** App code sweeps image *files* only; ledger rows cascade at the DB.
- **Fields set programmatically are never in `cast`.** `page_id` on `PageImage` is set on the struct, never cast (same posture as `PostImage`).
- **Run `mix precommit`** when all changes are done; fix everything it reports.
- **Assets use `pnpm`**, never `npm`. (No JS changes are expected — the `MarkdownEditor`/`UnsavedGuard` hooks are already generic.)
- **No narrating comments.** Reserve comments for constraints the code cannot express.
- **Test behavior, not markup.** Assert on outcomes (renders, 404s, persistence, form errors), reference element IDs, never static template details.
- **Local test server on `PORT=4001`** — never kill the user's 4000.
- Test config already provides `config :newton, :media_root, Path.join(System.tmp_dir!(), "newton_test_media")`.

---

## File Structure

**New files:**
- `lib/newton/storage.ex` — lifted media file store (`store/2`, `delete/1`, `url/1`).
- `lib/newton/images.ex` — pure `referenced?/2` shared by Blog and Pages.
- `lib/newton_web/live/admin/inline_image_upload.ex` — shared inline-image upload flow + upload constants + draft-on-first-image.
- `lib/newton_web/live/admin/autosave.ex` — shared autosave core (debounce, save_state, param staging, conflict flow).
- `lib/newton_web/components/content_components.ex` — shared public `content_article/1`.
- `lib/newton/pages.ex` — the Pages context.
- `lib/newton/pages/page.ex` — the Page schema + changeset + reserved-slug list.
- `lib/newton/pages/page_image.ex` — the PageImage schema (mirror of PostImage).
- `lib/newton_web/controllers/page_content_controller.ex` — public `/:slug` render.
- `lib/newton_web/controllers/page_content_html.ex` + `page_content_html/show.html.heex` — public page template.
- `lib/newton_web/live/admin/page_live/index.ex` — admin list.
- `lib/newton_web/live/admin/page_live/editor.ex` — admin new/edit editor.
- Migrations: `create_pages`, `create_page_images`.
- Tests: `test/newton/storage_test.exs` (renamed), `test/newton/images_test.exs`, `test/newton/pages_test.exs`, `test/newton/pages/page_images_test.exs`, `test/newton_web/controllers/page_content_controller_test.exs`, `test/newton_web/live/admin/page_index_live_test.exs`, `test/newton_web/live/admin/page_editor_live_test.exs`.

**Modified files:**
- Delete `lib/newton/gallery/storage.ex` (moved to `lib/newton/storage.ex`).
- `lib/newton/gallery.ex` — `thumb_url` calls `Newton.Storage.url`; drop `image_url` (moved to `Newton.Storage.url`); alias `Newton.Storage`.
- `lib/newton/blog.ex` — alias `Newton.Storage`; `image_referenced?` delegates to `Newton.Images.referenced?/2`.
- `lib/newton/blog/image_audit.ex` — alias `Newton.Storage`.
- `lib/newton_web/live/admin/gallery_live/show.ex` — alias `Newton.Storage`; `Newton.Storage.url`.
- `lib/newton_web/live/admin/media_live.ex` — `Newton.Storage.url`.
- `lib/newton_web/live/admin/post_live/editor.ex` — consume the shared upload flow + autosave core.
- `lib/newton_web/controllers/post_html/show.html.heex` — render `content_article/1`.
- `lib/newton_web/router.ex` — admin Pages routes + public catch-all scope at the end.
- `lib/newton_web/components/admin/layouts.ex` — add Pages to `@sections`.
- `lib/newton_web/live/admin/dashboard_live.ex` — Pages count card.
- `lib/newton_web/components/content_security_policy.ex` — comment reference to `Gallery.image_url` (cosmetic; update text).
- `test/newton/gallery_test.exs`, `test/newton/gallery/storage_test.exs` — renamed references.
- `lib/newton_web.ex` — import `NewtonWeb.ContentComponents` into `html_helpers`.

---

# Phase A — Shared foundations (behind green post tests)

## Task 0: Lift `Newton.Gallery.Storage` → `Newton.Storage`

**Files:**
- Create: `lib/newton/storage.ex`
- Delete: `lib/newton/gallery/storage.ex`
- Modify: `lib/newton/gallery.ex`, `lib/newton/blog.ex`, `lib/newton/blog/image_audit.ex`, `lib/newton_web/live/admin/gallery_live/show.ex`, `lib/newton_web/live/admin/media_live.ex`, `lib/newton_web/live/admin/post_live/editor.ex`, `lib/newton_web/components/content_security_policy.ex`
- Test: rename `test/newton/gallery/storage_test.exs` → `test/newton/storage_test.exs`; update `test/newton/gallery_test.exs`

**Interfaces:**
- Produces: `Newton.Storage.store/2`, `Newton.Storage.delete/1`, `Newton.Storage.url/1`.

- [ ] **Step 1: Move the file and rename the module.** Move `lib/newton/gallery/storage.ex` to `lib/newton/storage.ex`. Change the first line to `defmodule Newton.Storage do`. Leave `store/2`, `delete/1`, and the private `image_extension`/`extension_for`/`contained_path`/`media_root` bodies unchanged. Add a `url/1` function (moved from `Newton.Gallery.image_url/1`):

```elixir
  @doc "Resolve an image key to a URL. Absolute URLs pass through; keys map to /media."
  @spec url(String.t()) :: String.t()
  def url("http://" <> _ = value), do: value
  def url("https://" <> _ = value), do: value
  def url(key) when is_binary(key), do: "/media/" <> key
```

- [ ] **Step 2: Update `Newton.Gallery`.** Change the alias line 4 from `alias Newton.Gallery.{Photo, PhotoGroup, Storage, Thumbnail}` to `alias Newton.Gallery.{Photo, PhotoGroup, Thumbnail}` and add `alias Newton.Storage`. Delete the `image_url/1` function (lines ~150-154). Change `thumb_url/1` to call `Storage.url`:

```elixir
  @spec thumb_url(%Photo{}) :: String.t()
  def thumb_url(%Photo{thumb_key: thumb_key, image_key: image_key}),
    do: Storage.url(thumb_key || image_key)
```

`store_thumbnail/1` and the `delete_group/1`/`delete_photo/1` `Storage.delete` callsites keep working because `Storage` now aliases `Newton.Storage`.

- [ ] **Step 3: Update the remaining aliases and callsites.**
  - `lib/newton/blog.ex:6` — `alias Newton.Gallery.Storage` → `alias Newton.Storage`.
  - `lib/newton/blog/image_audit.ex:10` — `alias Newton.Gallery.Storage` → `alias Newton.Storage`.
  - `lib/newton_web/live/admin/gallery_live/show.ex:7` — `alias Newton.Gallery.Storage` → `alias Newton.Storage`; line 327 `Gallery.image_url(...)` → `Newton.Storage.url(...)`.
  - `lib/newton_web/live/admin/media_live.ex:72` — `Gallery.image_url(stray.key)` → `Newton.Storage.url(stray.key)`.
  - `lib/newton_web/live/admin/post_live/editor.ex:9` — `alias Newton.Gallery.Storage` → `alias Newton.Storage`; lines 59 and 814 `Gallery.image_url(...)` → `Newton.Storage.url(...)`.
  - `lib/newton_web/components/content_security_policy.ex:38` — update the comment text `Gallery.image_url/1` → `Newton.Storage.url/1`.

- [ ] **Step 4: Update the tests.** Rename `test/newton/gallery/storage_test.exs` → `test/newton/storage_test.exs`; change `defmodule Newton.Gallery.StorageTest` → `defmodule Newton.StorageTest` and `alias Newton.Gallery.Storage` → `alias Newton.Storage`. In `test/newton/gallery_test.exs:4` change `alias Newton.Gallery.Storage` → `alias Newton.Storage`; lines 8 and 12 update `Gallery.image_url(...)` assertions to `Newton.Storage.url(...)` (the URL contract is unchanged: `"/media/" <> key`).

- [ ] **Step 5: Run the full suite — no behavior change expected.**

Run: `mix test`
Expected: PASS (green, same count as before).

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "$(cat <<'EOF'
Lift Gallery.Storage to Newton.Storage

Media file store and the image-key→URL helper are shared by Gallery,
Blog, and (soon) Pages, so they belong at the top level, not inside a
single content context. Pure rename + move; no behavior change.
EOF
)"
```

---

## Task 1: Extract pure `Newton.Images.referenced?/2`

**Files:**
- Create: `lib/newton/images.ex`, `test/newton/images_test.exs`
- Modify: `lib/newton/blog.ex`

**Interfaces:**
- Produces: `Newton.Images.referenced?(body_markdown :: String.t() | nil, key :: String.t()) :: boolean()`.
- Consumed by: `Blog.delete_image/1` now, `Pages.delete_image/1` in Task 8.

- [ ] **Step 1: Write the failing test.**

```elixir
defmodule Newton.ImagesTest do
  use ExUnit.Case, async: true
  alias Newton.Images

  test "referenced? is true when the body contains the key" do
    assert Images.referenced?("see ![](/media/abc.png)", "abc.png")
  end

  test "referenced? is false when the body does not contain the key" do
    refute Images.referenced?("no images here", "abc.png")
  end

  test "referenced? treats a nil body as empty" do
    refute Images.referenced?(nil, "abc.png")
  end
end
```

- [ ] **Step 2: Run it — fails (module undefined).**

Run: `mix test test/newton/images_test.exs`
Expected: FAIL, `Newton.Images.referenced?/2` undefined.

- [ ] **Step 3: Implement.**

```elixir
defmodule Newton.Images do
  @moduledoc "Pure helpers over image references inside markdown bodies."

  @spec referenced?(String.t() | nil, String.t()) :: boolean()
  def referenced?(body_markdown, key) when is_binary(key) do
    String.contains?(body_markdown || "", key)
  end
end
```

- [ ] **Step 4: Refactor `Blog` to delegate.** In `lib/newton/blog.ex`, replace the `image_referenced?/2` private helper body so it calls `Newton.Images.referenced?/2`:

```elixir
  defp image_referenced?(%Post{} = post, %PostImage{} = image) do
    Newton.Images.referenced?(post.body_markdown, image.key)
  end
```

- [ ] **Step 5: Run the images test and the blog image tests — all pass.**

Run: `mix test test/newton/images_test.exs test/newton/blog/post_images_test.exs`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "Extract pure Newton.Images.referenced?/2, shared by Blog and Pages"
```

---

## Task 2: Extract the shared inline-image upload flow

**Files:**
- Create: `lib/newton_web/live/admin/inline_image_upload.ex`
- Modify: `lib/newton_web/live/admin/post_live/editor.ex`
- Test: existing `test/newton_web/live/admin/post_editor_live_test.exs` is the regression guard (do not weaken it).

**Interfaces:**
- Produces:
  - `NewtonWeb.Admin.InlineImageUpload.accept() :: [String.t()]` → `~w(.jpg .jpeg .png .webp .gif)`
  - `.max_entries() :: pos_integer()` → `10`
  - `.max_file_size() :: pos_integer()` → `50_000_000`
  - `.split_token(client_name :: String.t()) :: {token :: String.t() | nil, filename :: String.t()}`
  - `.handle_progress(entry, socket, opts) :: {:noreply, Phoenix.LiveView.Socket.t()}` where `opts` is a map with `:name` (the upload key atom, e.g. `:inline_images`), `:ensure` (a 1-arity fn `socket -> {socket, owner_record}` that creates a draft on first upload and returns the record), and `:attach` (a 3-arity fn `owner_record, key, filename -> {:ok, _} | {:error, _}`).
- Consumed by: post editor now, page editor in Task 11.

**Context — the current post-editor flow being extracted** (from `editor.ex`): `handle_inline_upload/3` checks `entry.done?`, calls `ensure_post`, splits the client name into `{token, filename}`, `consume_uploaded_entry` calling `Newton.Storage.store/2`, on `{:ok, key}` calls `Blog.attach_image(post, key, filename)` and yields `{:ok, Newton.Storage.url(key)}`, on error `Logger.warning` + `{:ok, nil}`, then `push_event("insert_image", %{url:, alt: "", name:, token:})` or a flash error.

- [ ] **Step 1: Confirm the guard is green before touching anything.**

Run: `PORT=4001 mix test test/newton_web/live/admin/post_editor_live_test.exs`
Expected: PASS.

- [ ] **Step 2: Write the shared module** (move the generic logic in verbatim, parameterized by `opts`):

```elixir
defmodule NewtonWeb.Admin.InlineImageUpload do
  @moduledoc """
  The inline-image upload flow shared by the post and page editors: store the
  file, record it on the owner's image ledger, and push `insert_image` back to
  the CodeMirror hook. The owner (post vs page) is supplied via `opts`.
  """
  import Phoenix.LiveView, only: [consume_uploaded_entry: 3, push_event: 3, put_flash: 3]
  require Logger

  @accept ~w(.jpg .jpeg .png .webp .gif)
  @max_entries 10
  @max_file_size 50_000_000

  def accept, do: @accept
  def max_entries, do: @max_entries
  def max_file_size, do: @max_file_size

  @doc "Split a `token::filename` client name into `{token, filename}` (token may be nil)."
  def split_token(client_name) do
    case String.split(client_name, "::", parts: 2) do
      [token, filename] -> {token, filename}
      [filename] -> {nil, filename}
    end
  end

  def handle_progress(entry, socket, opts) do
    if entry.done? do
      {socket, record} = opts.ensure.(socket)
      {token, filename} = split_token(entry.client_name)

      url =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          case Newton.Storage.store(path, filename) do
            {:ok, key} ->
              opts.attach.(record, key, filename)
              {:ok, Newton.Storage.url(key)}

            {:error, reason} ->
              Logger.warning("inline image store failed: #{inspect(reason)}")
              {:ok, nil}
          end
        end)

      case url do
        url when is_binary(url) ->
          {:noreply,
           push_event(socket, "insert_image", %{
             url: url,
             alt: "",
             name: filename,
             token: token
           })}

        nil ->
          {:noreply, put_flash(socket, :error, "Could not store that image.")}
      end
    else
      {:noreply, socket}
    end
  end
end
```

> Note: if the post editor's current `split_upload_token/1` uses a different delimiter than `::`, match its exact behavior here and adjust the `@doc`. Read `editor.ex` for the current delimiter before finalizing.

- [ ] **Step 3: Refactor the post editor to consume it.**
  - Remove the `@upload_accept`/`@upload_max_entries`/`@upload_max_file_size` module attrs and reference the shared getters in `allow_upload`:

```elixir
    |> allow_upload(:inline_images,
      accept: NewtonWeb.Admin.InlineImageUpload.accept(),
      max_entries: NewtonWeb.Admin.InlineImageUpload.max_entries(),
      max_file_size: NewtonWeb.Admin.InlineImageUpload.max_file_size(),
      auto_upload: true,
      progress: &handle_inline_upload/3
    )
```

  - Replace the body of `handle_inline_upload/3` with a delegation that supplies the post-specific `ensure`/`attach`:

```elixir
  defp handle_inline_upload(:inline_images, entry, socket) do
    NewtonWeb.Admin.InlineImageUpload.handle_progress(entry, socket, %{
      name: :inline_images,
      ensure: &ensure_post/1,
      attach: fn %Post{} = post, key, filename -> Blog.attach_image(post, key, filename) end
    })
  end
```

  - Change `ensure_post/1` so it returns `{socket, post}` (the shared flow needs the record). It currently creates the draft, assigns, and `push_patch`es; have it return the tuple. If `ensure_post/1` already returns the socket, wrap the return as `{socket, socket.assigns.post}`.
  - Keep the `data-upload-*` template attributes; point them at the shared getters (they currently read the removed module attrs). Also keep the `<.live_file_input upload={@uploads.inline_images} .../>` and the `MarkdownEditor` markup unchanged.

- [ ] **Step 4: Run the post editor tests — still green.**

Run: `PORT=4001 mix test test/newton_web/live/admin/post_editor_live_test.exs`
Expected: PASS — in particular "an upload lands on the post's image ledger" (asserts `insert_image` push with `url == "/media/" <> key`).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "Extract the shared inline-image upload flow; post editor consumes it"
```

---

## Task 3: Extract the shared autosave core

**Files:**
- Create: `lib/newton_web/live/admin/autosave.ex`
- Modify: `lib/newton_web/live/admin/post_live/editor.ex`
- Test: existing `test/newton_web/live/admin/post_editor_live_test.exs` is the regression guard.

**Interfaces:**
- Produces:
  - `NewtonWeb.Admin.Autosave.debounce_ms() :: 1500`
  - `.keys(fields :: [String.t()]) :: [String.t()]` → the fields plus their `"_unused_" <> field` twins.
  - `.content_params(params :: map(), keys :: [String.t()]) :: map()` → `Map.take(params, keys)`.
  - `.schedule(timer :: reference() | nil) :: reference()` → cancels an existing timer and returns a fresh `Process.send_after(self(), :autosave, debounce_ms())` ref.
  - `.dirty?(staged :: map() | nil, applied :: map() | nil) :: boolean()`
- Consumed by: post editor now (Option 1: the post editor keeps its own `persist_autosave`, `published_at` gate, and identity-autofill), page editor in Task 11.

**Context — what is generic vs. post-specific** (from `editor.ex`): generic = the debounce timer (`Process.send_after`/`Process.cancel_timer`), the `save_state` atoms (`:saved`/`:unsaved`/`:error`/`:conflict`), `content_params/1` (= `Map.take(params, @autosave_keys)`), `@autosave_keys` construction, `dirty?/2`, `reschedule_autosave_timer/1`, and the optimistic-lock conflict flow (`conflict_load_latest`, `conflict_keep_mine`, `recover`, `deleted_elsewhere/1`). Post-specific (stays in `editor.ex`) = `persist_autosave/3` (create/update with `never_blank_identity`, `{:error, :stale}` → conflict), the `published_at == nil` gate in `handle_info(:autosave, ...)`, `backfill_new`, `next_untitled_slug`, and the slug/excerpt autofill.

- [ ] **Step 1: Confirm the guard is green.**

Run: `PORT=4001 mix test test/newton_web/live/admin/post_editor_live_test.exs`
Expected: PASS (incl. "editing a draft auto-saves without a manual save").

- [ ] **Step 2: Write the shared core (pure/timer helpers).**

```elixir
defmodule NewtonWeb.Admin.Autosave do
  @moduledoc """
  The debounce + param-staging core shared by the post and page editors. Each
  editor keeps its own persist function and its own gate (posts on published_at,
  pages on the published boolean); this module owns only the generic mechanics.
  """
  @debounce_ms 1500

  def debounce_ms, do: @debounce_ms

  @doc "Autosave field names plus their `_unused_` twins (LiveView drops unchanged params)."
  def keys(fields) when is_list(fields) do
    fields ++ Enum.map(fields, &("_unused_" <> &1))
  end

  @doc "The subset of `params` that participates in autosave."
  def content_params(params, keys), do: Map.take(params, keys)

  @doc "Cancel any pending timer and arm a fresh one; returns the new ref."
  def schedule(timer) do
    if is_reference(timer), do: Process.cancel_timer(timer)
    Process.send_after(self(), :autosave, @debounce_ms)
  end

  @doc "Have the staged params diverged from what was last applied?"
  def dirty?(staged, applied), do: staged != nil and staged != applied
end
```

> The exact bodies of `dirty?/2` and the `_unused_` handling in the current post editor take precedence — read `editor.ex` and preserve its behavior. If the current `dirty?` compares specific keys rather than whole maps, replicate that logic here rather than the `!=` shown above.

- [ ] **Step 3: Refactor the post editor to consume the core.**
  - Replace `@autosave_debounce_ms 1500` usage with `Autosave.debounce_ms()` and `@autosave_keys` with `Autosave.keys(@autosave_fields)` (keep `@autosave_fields ~w(title slug excerpt body_markdown)` — that list is post-specific).
  - Replace `content_params/1` calls with `Autosave.content_params(params, Autosave.keys(@autosave_fields))`.
  - Replace `reschedule_autosave_timer/1`'s timer arithmetic with `Autosave.schedule(socket.assigns.autosave_timer)`.
  - Leave `persist_autosave/3`, the `published_at == nil` gate in `handle_info(:autosave, ...)`, `never_blank_identity`, `backfill_new`, `next_untitled_slug`, and the conflict handlers (`conflict_load_latest`/`conflict_keep_mine`/`recover`) in `editor.ex` unchanged — Option 1 keeps these post-specific.
  - Add `alias NewtonWeb.Admin.Autosave` at the top.

- [ ] **Step 4: Run the post editor tests — still green.**

Run: `PORT=4001 mix test test/newton_web/live/admin/post_editor_live_test.exs`
Expected: PASS (autosave, autosave_now hook flush, and conflict cases all still pass).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "Extract the shared autosave core; post editor consumes it"
```

---

## Task 4: Extract the public `content_article/1` component

**Files:**
- Create: `lib/newton_web/components/content_components.ex`
- Modify: `lib/newton_web.ex` (import into `html_helpers`), `lib/newton_web/controllers/post_html/show.html.heex`
- Test: existing post show controller test is the guard; add nothing that asserts markup.

**Interfaces:**
- Produces: `content_article/1` with `attr :title`, `attr :body_html`, and a `:byline` slot.

- [ ] **Step 1: Write the component.**

```elixir
defmodule NewtonWeb.ContentComponents do
  @moduledoc "Shared public content chrome (the article/body skeleton)."
  use Phoenix.Component

  attr :title, :string, required: true
  attr :body_html, :string, required: true
  slot :byline

  def content_article(assigns) do
    ~H"""
    <article class="post">
      <header>
        <h1 class="post-title">{@title}</h1>
        {render_slot(@byline)}
      </header>

      <section class="post-body">
        {Phoenix.HTML.raw(@body_html)}
      </section>
    </article>
    """
  end
end
```

- [ ] **Step 2: Import it app-wide.** In `lib/newton_web.ex`, inside the `html_helpers` block (where the app-wide imports live), add `import NewtonWeb.ContentComponents`.

- [ ] **Step 3: Refactor post show to use it.** Replace the `<article class="post">…</article>` block in `post_html/show.html.heex` with:

```heex
  <.content_article title={@post.title} body_html={@post.body_html}>
    <:byline>
      <p class="post-byline">
        {format_date(@post.published_at, on_nil: "Unpublished")} · {format_reading_time(@post.reading_time)}
      </p>
    </:byline>
  </.content_article>
```

Keep the `<div :if={@preview} class="preview-banner">…</div>` and the `<Layouts.app>` wrapper as they are.

- [ ] **Step 4: Run the post show test — still green.**

Run: `PORT=4001 mix test test/newton_web/controllers/post_controller_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "Extract public content_article component; post show consumes it"
```

---

# Phase B — Pages domain

## Task 5: `Newton.Pages.Page` schema + migration

**Files:**
- Create: `lib/newton/pages/page.ex`
- Create migration via `mix ecto.gen.migration create_pages`
- Test: `test/newton/pages_test.exs` (schema-level cases via the context in Task 7; this task adds the changeset unit test)

**Interfaces:**
- Produces: `Newton.Pages.Page` schema; `Page.changeset/2`; `Page.reserved_slugs/0`.

- [ ] **Step 1: Generate and write the migration.**

Run: `mix ecto.gen.migration create_pages`

```elixir
defmodule Newton.Repo.Migrations.CreatePages do
  use Ecto.Migration

  def change do
    create table(:pages) do
      add :slug, :string, null: false
      add :title, :string, null: false
      add :body_markdown, :text, null: false
      add :body_html, :text, null: false
      add :meta_description, :string
      add :published, :boolean, null: false, default: false
      add :lock_version, :integer, null: false, default: 1
      timestamps(type: :utc_datetime)
    end

    create unique_index(:pages, [:slug])
    create index(:pages, [:published])
  end
end
```

- [ ] **Step 2: Write a failing changeset test.**

```elixir
defmodule Newton.PagesTest do
  use Newton.DataCase
  alias Newton.Pages.Page

  test "changeset renders body_html from markdown and requires slug/title" do
    cs = Page.changeset(%Page{}, %{slug: "about", title: "About", body_markdown: "## Hi"})
    assert cs.valid?
    assert Ecto.Changeset.get_change(cs, :body_html) =~ "<h2"
  end

  test "changeset coerces a missing body to an empty string" do
    cs = Page.changeset(%Page{}, %{slug: "about", title: "About"})
    assert cs.valid?
    assert Ecto.Changeset.get_field(cs, :body_markdown) == ""
  end

  test "changeset rejects a reserved slug" do
    cs = Page.changeset(%Page{}, %{slug: "admin", title: "Nope", body_markdown: ""})
    refute cs.valid?
    assert %{slug: [_ | _]} = errors_on(cs)
  end

  test "changeset requires title" do
    cs = Page.changeset(%Page{}, %{slug: "about", body_markdown: ""})
    refute cs.valid?
    assert %{title: [_ | _]} = errors_on(cs)
  end
end
```

- [ ] **Step 3: Run — fails (module undefined).**

Run: `mix test test/newton/pages_test.exs`
Expected: FAIL, `Newton.Pages.Page` undefined.

- [ ] **Step 4: Implement the schema.**

```elixir
defmodule Newton.Pages.Page do
  use Ecto.Schema
  import Ecto.Changeset
  alias Newton.Markdown

  @reserved_slugs ~w(posts blog reading photos links resume admin oauth mcp og
                     login logout dev sitemap.xml robots.txt .well-known)

  schema "pages" do
    field :slug, :string
    field :title, :string
    field :body_markdown, :string
    field :body_html, :string
    field :meta_description, :string
    field :published, :boolean, default: false
    field :lock_version, :integer, default: 1
    has_many :images, Newton.Pages.PageImage
    timestamps(type: :utc_datetime)
  end

  @spec reserved_slugs() :: [String.t()]
  def reserved_slugs, do: @reserved_slugs

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(page, attrs) do
    page
    |> cast(attrs, [:slug, :title, :body_markdown, :meta_description, :published])
    |> ensure_body()
    |> validate_required([:slug, :title])
    |> validate_exclusion(:slug, @reserved_slugs, message: "is reserved")
    |> unique_constraint(:slug)
    |> optimistic_lock(:lock_version)
    |> render_body_html()
  end

  defp ensure_body(changeset) do
    if is_nil(get_field(changeset, :body_markdown)) do
      put_change(changeset, :body_markdown, "")
    else
      changeset
    end
  end

  defp render_body_html(%Ecto.Changeset{valid?: true} = changeset) do
    case fetch_change(changeset, :body_markdown) do
      {:ok, markdown} -> put_change(changeset, :body_html, Markdown.to_html(markdown))
      :error -> changeset
    end
  end

  defp render_body_html(changeset), do: changeset
end
```

> `has_many :images` references `Newton.Pages.PageImage`, created in Task 6 — the compiler resolves this at runtime, so the reference is fine before that module exists, but run Task 6's migration before any test inserts a page with images.

- [ ] **Step 5: Run — passes.**

Run: `mix test test/newton/pages_test.exs`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "Add Newton.Pages.Page schema, changeset, and pages migration"
```

---

## Task 6: `Newton.Pages.PageImage` schema + migration

**Files:**
- Create: `lib/newton/pages/page_image.ex`
- Create migration via `mix ecto.gen.migration create_page_images`
- Test: covered by Task 8 (`test/newton/pages/page_images_test.exs`).

**Interfaces:**
- Produces: `Newton.Pages.PageImage` schema; `PageImage.create_changeset/2`.

- [ ] **Step 1: Generate and write the migration.**

Run: `mix ecto.gen.migration create_page_images`

```elixir
defmodule Newton.Repo.Migrations.CreatePageImages do
  use Ecto.Migration

  def change do
    create table(:page_images) do
      add :page_id, references(:pages, on_delete: :delete_all), null: false
      add :key, :string, null: false
      add :original_filename, :string
      timestamps(type: :utc_datetime)
    end

    create index(:page_images, [:page_id])
    create unique_index(:page_images, [:key])
  end
end
```

- [ ] **Step 2: Implement the schema** (exact mirror of `PostImage`).

```elixir
defmodule Newton.Pages.PageImage do
  use Ecto.Schema
  import Ecto.Changeset
  alias Newton.Pages.Page

  schema "page_images" do
    field :key, :string
    field :original_filename, :string
    belongs_to :page, Page
    timestamps(type: :utc_datetime)
  end

  @spec create_changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def create_changeset(image, attrs) do
    image
    |> cast(attrs, [:key, :original_filename])
    |> validate_required([:page_id, :key])
    |> unique_constraint(:key)
    |> foreign_key_constraint(:page_id)
  end
end
```

- [ ] **Step 3: Migrate and compile.**

Run: `mix ecto.migrate && mix compile --warnings-as-errors`
Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "Add Newton.Pages.PageImage schema and page_images migration"
```

---

## Task 7: `Newton.Pages` context — CRUD + lookups

**Files:**
- Create: `lib/newton/pages.ex`
- Test: `test/newton/pages_test.exs` (extend the file from Task 5)

**Interfaces:**
- Produces:
  - `list_pages() :: [%Page{}]` (newest-first)
  - `get_page!(id) :: %Page{}`
  - `get_page_by_slug(slug) :: %Page{} | nil` (any state)
  - `get_published_page_by_slug(slug) :: %Page{} | nil` (published only)
  - `create_page(attrs) :: {:ok, %Page{}} | {:error, %Ecto.Changeset{}}`
  - `update_page(page, attrs) :: {:ok, %Page{}} | {:error, %Ecto.Changeset{}} | {:error, :stale}`
  - `delete_page(page) :: {:ok, %Page{}}`
  - `change_page(page, attrs \\ %{}) :: %Ecto.Changeset{}`
  - `count_pages() :: non_neg_integer()`, `count_drafts() :: non_neg_integer()`

- [ ] **Step 1: Add failing context tests.**

```elixir
  describe "context CRUD" do
    @valid %{slug: "about", title: "About", body_markdown: "Hello."}

    test "create_page renders body_html" do
      assert {:ok, page} = Pages.create_page(@valid)
      assert page.body_html =~ "Hello."
    end

    test "create_page enforces slug uniqueness" do
      {:ok, _} = Pages.create_page(@valid)
      assert {:error, cs} = Pages.create_page(@valid)
      assert %{slug: [_ | _]} = errors_on(cs)
    end

    test "get_published_page_by_slug returns published, refuses drafts" do
      {:ok, published} = Pages.create_page(Map.put(@valid, :published, true))
      {:ok, _draft} = Pages.create_page(%{slug: "now", title: "Now", body_markdown: "", published: false})

      assert Pages.get_published_page_by_slug("about").id == published.id
      assert Pages.get_published_page_by_slug("now") == nil
      assert Pages.get_page_by_slug("now").slug == "now"
    end

    test "update_page returns {:error, :stale} on a concurrent edit" do
      {:ok, page} = Pages.create_page(@valid)
      {:ok, _fresh} = Pages.update_page(page, %{title: "Won"})
      assert {:error, :stale} = Pages.update_page(page, %{title: "Lost"})
    end

    test "count_pages and count_drafts" do
      {:ok, _} = Pages.create_page(Map.put(@valid, :published, true))
      {:ok, _} = Pages.create_page(%{slug: "now", title: "Now", body_markdown: "", published: false})
      assert Pages.count_pages() == 2
      assert Pages.count_drafts() == 1
    end
  end
```

- [ ] **Step 2: Run — fails (`Newton.Pages` undefined).**

Run: `mix test test/newton/pages_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement the context.**

```elixir
defmodule Newton.Pages do
  @moduledoc "Standalone markdown pages served at top-level slugs."
  import Ecto.Query
  alias Newton.Repo
  alias Newton.Pages.{Page, PageImage}
  alias Newton.Storage

  @spec list_pages() :: [%Page{}]
  def list_pages do
    Repo.all(from p in Page, order_by: [desc: p.inserted_at, desc: p.id])
  end

  @spec get_page!(term()) :: %Page{}
  def get_page!(id), do: Repo.get!(Page, id)

  @spec get_page_by_slug(String.t()) :: %Page{} | nil
  def get_page_by_slug(slug), do: Repo.get_by(Page, slug: slug)

  @spec get_published_page_by_slug(String.t()) :: %Page{} | nil
  def get_published_page_by_slug(slug), do: Repo.get_by(Page, slug: slug, published: true)

  @spec create_page(map()) :: {:ok, %Page{}} | {:error, %Ecto.Changeset{}}
  def create_page(attrs) do
    %Page{} |> Page.changeset(attrs) |> Repo.insert()
  end

  @spec update_page(%Page{}, map()) :: {:ok, %Page{}} | {:error, %Ecto.Changeset{}} | {:error, :stale}
  def update_page(%Page{} = page, attrs) do
    page |> Page.changeset(attrs) |> Repo.update()
  rescue
    Ecto.StaleEntryError -> {:error, :stale}
  end

  @spec delete_page(%Page{}) :: {:ok, %Page{}} | {:error, %Ecto.Changeset{}}
  def delete_page(%Page{} = page) do
    page |> list_images() |> Enum.each(&Storage.delete(&1.key))
    Repo.delete(page)
  end

  @spec change_page(%Page{}, map()) :: %Ecto.Changeset{}
  def change_page(%Page{} = page, attrs \\ %{}), do: Page.changeset(page, attrs)

  @spec count_pages() :: non_neg_integer()
  def count_pages, do: Repo.aggregate(Page, :count, :id)

  @spec count_drafts() :: non_neg_integer()
  def count_drafts, do: Repo.aggregate(from(p in Page, where: p.published == false), :count, :id)

  # Image ledger — see Task 8 for attach_image/list_images/delete_image.
end
```

- [ ] **Step 4: Run — passes.**

Run: `mix test test/newton/pages_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "Add Newton.Pages context: CRUD, slug lookups, stale handling, counts"
```

---

## Task 8: `Newton.Pages` image ledger — attach / list / delete

**Files:**
- Modify: `lib/newton/pages.ex`
- Test: `test/newton/pages/page_images_test.exs`

**Interfaces:**
- Produces:
  - `attach_image(page, key, original_filename \\ nil) :: {:ok, %PageImage{}} | {:error, %Ecto.Changeset{}}`
  - `list_images(page) :: [%PageImage{}]`
  - `delete_image(image) :: {:ok, %PageImage{}} | {:error, :referenced}`

- [ ] **Step 1: Write failing tests** (mirror `post_images_test.exs`, with a local `stored_file/1`).

```elixir
defmodule Newton.Pages.PageImagesTest do
  use Newton.DataCase
  alias Newton.Pages

  defp page_fixture(attrs \\ %{}) do
    {:ok, page} =
      attrs
      |> Enum.into(%{
        slug: "page-#{System.unique_integer([:positive])}",
        title: "A Page",
        body_markdown: "Some text."
      })
      |> Pages.create_page()

    page
  end

  defp stored_file(key) do
    root = Application.fetch_env!(:newton, :media_root)
    File.mkdir_p!(root)
    path = Path.join(root, key)
    File.write!(path, "img-bytes")
    path
  end

  test "attach_image records an upload against its page" do
    page = page_fixture()
    assert {:ok, image} = Pages.attach_image(page, "abc123.png", "shot.png")
    assert image.page_id == page.id
    assert [%{key: "abc123.png"}] = Pages.list_images(page)
  end

  test "delete_image removes the file and row for an unreferenced image" do
    page = page_fixture()
    {:ok, image} = Pages.attach_image(page, "gone.png", nil)
    path = stored_file("gone.png")
    assert {:ok, _} = Pages.delete_image(image)
    refute File.exists?(path)
    assert Pages.list_images(page) == []
  end

  test "delete_image refuses while the page still references the image" do
    page = page_fixture(%{body_markdown: "![](/media/kept.png)"})
    {:ok, image} = Pages.attach_image(page, "kept.png", nil)
    path = stored_file("kept.png")
    assert {:error, :referenced} = Pages.delete_image(image)
    assert File.exists?(path)
  end

  test "deleting a page cascades its image rows" do
    page = page_fixture()
    {:ok, _} = Pages.attach_image(page, "sweep.png", nil)
    _ = stored_file("sweep.png")
    {:ok, _} = Pages.delete_page(page)
    assert Pages.list_images(page) == []
  end
end
```

- [ ] **Step 2: Run — fails.**

Run: `mix test test/newton/pages/page_images_test.exs`
Expected: FAIL, `attach_image/3` undefined.

- [ ] **Step 3: Implement the image fns** (append to `Newton.Pages`, using `Newton.Images.referenced?/2`).

```elixir
  @spec attach_image(%Page{}, String.t(), String.t() | nil) ::
          {:ok, %PageImage{}} | {:error, %Ecto.Changeset{}}
  def attach_image(%Page{} = page, key, original_filename \\ nil) do
    %PageImage{page_id: page.id}
    |> PageImage.create_changeset(%{key: key, original_filename: original_filename})
    |> Repo.insert()
  end

  @spec list_images(%Page{}) :: [%PageImage{}]
  def list_images(%Page{id: page_id}) do
    Repo.all(from i in PageImage, where: i.page_id == ^page_id, order_by: [asc: i.inserted_at, asc: i.id])
  end

  @spec delete_image(%PageImage{}) :: {:ok, %PageImage{}} | {:error, :referenced}
  def delete_image(%PageImage{} = image) do
    page = get_page!(image.page_id)

    if Newton.Images.referenced?(page.body_markdown, image.key) do
      {:error, :referenced}
    else
      Storage.delete(image.key)
      Repo.delete(image)
    end
  end
```

- [ ] **Step 4: Run — passes.**

Run: `mix test test/newton/pages/page_images_test.exs`
Expected: PASS (including the cascade case).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "Add Pages image ledger: attach/list/delete with reference guard and cascade"
```

---

# Phase C — Public rendering

## Task 9: Public catch-all route + `PageContentController`

**Files:**
- Create: `lib/newton_web/controllers/page_content_controller.ex`, `lib/newton_web/controllers/page_content_html.ex`, `lib/newton_web/controllers/page_content_html/show.html.heex`
- Modify: `lib/newton_web/router.ex`
- Test: `test/newton_web/controllers/page_content_controller_test.exs`

**Interfaces:**
- Consumes: `Pages.get_page_by_slug/1`, `content_article/1`.
- Produces: `GET /:slug` → published for all; draft for logged-in admin (with banner); 404 otherwise.

- [ ] **Step 1: Add the catch-all route as the final `:browser` scope.** In `router.ex`, add — *after* the authentication-routes scope (the last `scope "/", NewtonWeb do pipe_through [:browser]` block that defines `/login`, `/logout`) and outside the `dev_routes` conditionals — a new scope at the very end so no literal single-segment browser route follows it:

```elixir
  # Public standalone pages. MUST be the last :browser scope in the file so the
  # catch-all cannot shadow /login, /logout, /resume, /reading, etc. The
  # reserved-slug list on Page.changeset is the belt to this ordering's braces.
  scope "/", NewtonWeb do
    pipe_through :browser

    get "/:slug", PageContentController, :show
  end
```

- [ ] **Step 2: Write failing controller tests.**

```elixir
defmodule NewtonWeb.PageContentControllerTest do
  use NewtonWeb.ConnCase, async: true
  import Newton.AccountsFixtures

  test "renders a published page at /:slug", %{conn: conn} do
    {:ok, _} = Newton.Pages.create_page(%{slug: "about", title: "About Me", body_markdown: "Hi there.", published: true})
    conn = get(conn, ~p"/about")
    assert html_response(conn, 200) =~ "About Me"
    assert html_response(conn, 200) =~ "Hi there."
  end

  test "a draft 404s for an anonymous visitor", %{conn: conn} do
    {:ok, _} = Newton.Pages.create_page(%{slug: "secret", title: "Secret", body_markdown: "shh", published: false})
    assert_error_sent 404, fn -> get(conn, ~p"/secret") end
  end

  test "a draft renders with a banner for a logged-in admin", %{conn: conn} do
    {:ok, _} = Newton.Pages.create_page(%{slug: "secret", title: "Secret Draft", body_markdown: "shh", published: false})
    conn = conn |> log_in_user(user_fixture()) |> get(~p"/secret")
    assert html_response(conn, 200) =~ "Secret Draft"
    assert html_response(conn, 200) =~ "Draft"
  end

  test "an unknown slug 404s", %{conn: conn} do
    assert_error_sent 404, fn -> get(conn, ~p"/nope-nope") end
  end
end
```

- [ ] **Step 3: Run — fails.**

Run: `PORT=4001 mix test test/newton_web/controllers/page_content_controller_test.exs`
Expected: FAIL, controller undefined.

- [ ] **Step 4: Implement the controller.** (`:browser` supplies `conn.assigns.current_scope`. Mirror the posts convention of raising for a 404.)

```elixir
defmodule NewtonWeb.PageContentController do
  use NewtonWeb, :controller
  alias Newton.Pages
  alias Newton.Pages.Page

  def show(conn, %{"slug" => slug}) do
    page = Pages.get_page_by_slug(slug)
    render_page(conn, page, admin?(conn))
  end

  defp render_page(conn, %Page{published: true} = page, _admin) do
    deliver(conn, page, false)
  end

  defp render_page(conn, %Page{published: false} = page, true) do
    conn |> put_status(:ok) |> assign(:page_robots, "noindex") |> deliver(page, true)
  end

  defp render_page(_conn, _page, _admin), do: raise(Ecto.NoResultsError, queryable: Page)

  defp deliver(conn, %Page{} = page, preview?) do
    render(conn, :show,
      page_title: page.title,
      meta_description: page.meta_description,
      page: page,
      preview: preview?
    )
  end

  defp admin?(conn), do: match?(%{user: %{}}, conn.assigns[:current_scope])
end
```

> The `render_page/3` clause for `%Page{published: false}` matches only when `admin?` is `true`; the final catch-all clause handles both a draft-for-anon and a `nil` page (unknown slug), raising `Ecto.NoResultsError` → the app's 404 path (same mechanism as `Blog.get_published_post!`). Before finalizing SEO, read the posts controller's `SEO.assign/2`; if a generic SEO module exists that can take a title+description, wire it here the same way posts do, keeping `page_title`/`meta_description` as the fallback.

- [ ] **Step 5: Add the HTML module and template.**

`page_content_html.ex`:

```elixir
defmodule NewtonWeb.PageContentHTML do
  use NewtonWeb, :html

  embed_templates "page_content_html/*"
end
```

`page_content_html/show.html.heex`:

```heex
<Layouts.app flash={@flash}>
  <div :if={@preview} class="preview-banner">
    <strong>Draft — not public</strong>
    <span>Only you can see this page until it is published.</span>
  </div>

  <.content_article title={@page.title} body_html={@page.body_html} />
</Layouts.app>
```

- [ ] **Step 6: Run — passes.**

Run: `PORT=4001 mix test test/newton_web/controllers/page_content_controller_test.exs`
Expected: PASS.

- [ ] **Step 7: Guard against route shadowing — run the full web suite.**

Run: `PORT=4001 mix test test/newton_web`
Expected: PASS — confirms `/:slug` did not shadow `/login`, `/posts`, `/reading`, `/photos`, `/links`, `/resume`, `/sitemap.xml`, `/robots.txt`, etc.

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "Serve public pages at /:slug via PageContentController"
```

---

# Phase D — Admin

## Task 10: `PageLive.Index` + admin route + nav entry

**Files:**
- Create: `lib/newton_web/live/admin/page_live/index.ex`
- Modify: `lib/newton_web/router.ex`, `lib/newton_web/components/admin/layouts.ex`
- Test: `test/newton_web/live/admin/page_index_live_test.exs`

**Interfaces:**
- Consumes: `Pages.list_pages/0`, the shared `Components.list`/`list_item`/`page_header`/`button` and `Layouts.status_badge`.

- [ ] **Step 1: Add the admin route.** In the existing `live_session :admin` block in `router.ex`, add (grouped with the other admin lives):

```elixir
      live "/pages", PageLive.Index, :index
      live "/pages/new", PageLive.Editor, :new
      live "/pages/:id/edit", PageLive.Editor, :edit
```

(`PageLive.Editor` is built in Task 11; adding all three routes now keeps the router edit in one place. `PageLive.Editor` must exist before the router compiles — if executing strictly task-by-task, add only the `PageLive.Index` route here and the two editor routes in Task 11.)

- [ ] **Step 2: Add the nav entry.** In `layouts.ex`, add to `@sections` after `:posts`:

```elixir
    %{key: :pages, label: "Pages", path: "/admin/pages"},
```

- [ ] **Step 3: Write failing tests.**

```elixir
defmodule NewtonWeb.Admin.PageIndexLiveTest do
  use NewtonWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Newton.AccountsFixtures

  setup %{conn: conn}, do: %{conn: log_in_user(conn, user_fixture())}

  test "lists existing pages", %{conn: conn} do
    {:ok, _} = Newton.Pages.create_page(%{slug: "about", title: "About", body_markdown: "", published: true})
    {:ok, view, _html} = live(conn, ~p"/admin/pages")
    assert has_element?(view, "#pages")
    assert render(view) =~ "About"
  end

  test "new-page button links to the editor", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/pages")
    assert view |> element("a", "New page") |> render_click()
    assert_patch(view, ~p"/admin/pages/new") |> is_nil() == false
  rescue
    _ -> assert has_element?(view, "a[href='/admin/pages/new']")
  end
end
```

> Keep the second test behavior-focused: assert navigation happens. If the new-page control is a `navigate` link (not a patch), assert `has_element?(view, "a[href='/admin/pages/new']")` and drop the `render_click` — match whatever the `Components.button navigate=` renders.

- [ ] **Step 4: Run — fails.**

Run: `PORT=4001 mix test test/newton_web/live/admin/page_index_live_test.exs`
Expected: FAIL, `PageLive.Index` undefined.

- [ ] **Step 5: Implement the index** (mirror `PostLive.Index`; pages have a `published` boolean, so map it to `status_badge` via `:published`/`:draft`).

```elixir
defmodule NewtonWeb.Admin.PageLive.Index do
  use NewtonWeb, :live_view

  alias NewtonWeb.Admin.Components
  alias NewtonWeb.Admin.Layouts

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :pages, Newton.Pages.list_pages())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current={:pages}>
      <Components.page_header title="Pages">
        <Components.button navigate={~p"/admin/pages/new"}>New page</Components.button>
      </Components.page_header>

      <Components.list id="pages" empty="No pages yet.">
        <Components.list_item
          :for={{id, page} <- @streams.pages}
          id={id}
          navigate={~p"/admin/pages/#{page.id}/edit"}
        >
          {page.title}
          <:inline>
            <span class="text-[0.78rem] text-(--admin-text-subtle)">/{page.slug}</span>
          </:inline>
          <:meta>
            <Layouts.status_badge status={if page.published, do: :published, else: :draft} />
          </:meta>
        </Components.list_item>
      </Components.list>
    </Layouts.admin>
    """
  end
end
```

- [ ] **Step 6: Run — passes.**

Run: `PORT=4001 mix test test/newton_web/live/admin/page_index_live_test.exs`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "Add admin Pages index, route, and nav entry"
```

---

## Task 11: `PageLive.Editor` — lean editor with autosave + inline images

**Files:**
- Create: `lib/newton_web/live/admin/page_live/editor.ex`
- Modify: `lib/newton_web/router.ex` (only if the editor routes were deferred in Task 10)
- Test: `test/newton_web/live/admin/page_editor_live_test.exs`

**Interfaces:**
- Consumes: `Pages.get_page!/1`, `Pages.create_page/1`, `Pages.update_page/2`, `Pages.change_page/2`, `Pages.attach_image/3`, `Pages.delete_page/1`, the shared `NewtonWeb.Admin.InlineImageUpload` and `NewtonWeb.Admin.Autosave`, and the `MarkdownEditor`/`UnsavedGuard` JS hooks (already registered in `admin.js`).

- [ ] **Step 1: Write failing tests** (mirror the post editor's behavior tests; use the shared 1×1 PNG). Autosave for pages gates on `published == false`.

```elixir
defmodule NewtonWeb.Admin.PageEditorLiveTest do
  use NewtonWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Newton.AccountsFixtures

  @png_1x1 <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1,
             8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 10, 73, 68, 65, 84, 120, 156, 99, 0, 1, 0,
             0, 5, 0, 1, 13, 10, 45, 180, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130>>

  setup %{conn: conn}, do: %{conn: log_in_user(conn, user_fixture())}

  defp open_draft(conn, attrs \\ %{}) do
    {:ok, page} =
      Newton.Pages.create_page(Enum.into(attrs, %{title: "Untitled", slug: "untitled-page", body_markdown: ""}))

    {:ok, view, _html} = live(conn, ~p"/admin/pages/#{page.id}/edit")
    {view, page}
  end

  test "editing a draft persists on submit", %{conn: conn} do
    {view, _page} = open_draft(conn)

    view
    |> form("#page-form", page: %{title: "About", slug: "about", body_markdown: "Body copy."})
    |> render_submit()

    page = Newton.Pages.get_page_by_slug("about")
    assert page.body_html =~ "Body copy."
  end

  test "a draft auto-saves without a manual save", %{conn: conn} do
    {view, page} = open_draft(conn)

    view
    |> form("#page-form", page: %{title: "Untitled", slug: "untitled-page", body_markdown: "new body"})
    |> render_change()

    send(view.pid, :autosave)
    _ = :sys.get_state(view.pid)

    assert Newton.Pages.get_page!(page.id).body_html =~ "new body"
  end

  test "an inline upload lands on the page's image ledger and pushes insert_image", %{conn: conn} do
    {view, page} = open_draft(conn)

    image = file_input(view, "#page-form", :inline_images, [%{name: "shot.png", content: @png_1x1, type: "image/png"}])
    render_upload(image, "shot.png")

    assert [attached] = Newton.Pages.list_images(page)
    assert_push_event(view, "insert_image", %{url: url, name: "shot.png"})
    assert url == "/media/" <> attached.key
  end

  test "a reserved slug shows a form error", %{conn: conn} do
    {view, _page} = open_draft(conn)

    html =
      view
      |> form("#page-form", page: %{title: "Nope", slug: "admin", body_markdown: ""})
      |> render_submit()

    assert html =~ "reserved"
  end

  test "delete removes the page and navigates to the index", %{conn: conn} do
    {view, page} = open_draft(conn)
    view |> element("#page-delete") |> render_click()
    assert_raise Ecto.NoResultsError, fn -> Newton.Pages.get_page!(page.id) end
  end
end
```

> `#page-delete` and `#page-form` are the DOM IDs the editor must set. If the delete control triggers a JS confirm, use the same server-side pattern the post editor uses (a `phx-click="delete"` with no native dialog) so the test's `render_click` works.

- [ ] **Step 2: Run — fails.**

Run: `PORT=4001 mix test test/newton_web/live/admin/page_editor_live_test.exs`
Expected: FAIL, `PageLive.Editor` undefined.

- [ ] **Step 3: Implement the editor.** Model it on `PostLive.Editor` but drop the drawer, social card, scheduling, preview token, `PublicationNotifier`, and slug/excerpt autofill. Use `Autosave` for debounce/staging and `InlineImageUpload` for uploads. Autosave gate: `page.published == false`.

```elixir
defmodule NewtonWeb.Admin.PageLive.Editor do
  use NewtonWeb, :live_view

  alias Newton.Pages
  alias Newton.Pages.Page
  alias NewtonWeb.Admin.{Autosave, Components, InlineImageUpload, Layouts}

  @autosave_fields ~w(title slug meta_description body_markdown)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(save_state: :saved, autosave_params: nil, autosave_timer: nil, editor_key: 0)
     |> allow_upload(:inline_images,
       accept: InlineImageUpload.accept(),
       max_entries: InlineImageUpload.max_entries(),
       max_file_size: InlineImageUpload.max_file_size(),
       auto_upload: true,
       progress: &handle_inline_upload/3
     )}
  end

  @impl true
  def handle_params(params, _uri, socket), do: {:noreply, apply_action(socket, socket.assigns.live_action, params)}

  defp apply_action(socket, :new, _params) do
    page = %Page{}
    assign_page(socket, page)
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    page = Pages.get_page!(id)
    assign_page(socket, page)
  end

  defp assign_page(socket, %Page{} = page) do
    socket
    |> assign(:page, page)
    |> assign(:editor_key, socket.assigns.editor_key + 1)
    |> assign_form(Pages.change_page(page))
  end

  defp assign_form(socket, %Ecto.Changeset{} = cs), do: assign(socket, :form, to_form(cs, as: :page))

  @impl true
  def handle_event("validate", %{"page" => params}, socket) do
    cs = socket.assigns.page |> Pages.change_page(params) |> Map.put(:action, :validate)
    staged = Autosave.content_params(params, Autosave.keys(@autosave_fields))

    socket =
      socket
      |> assign_form(cs)
      |> assign(:autosave_params, staged)
      |> maybe_schedule_autosave()

    {:noreply, socket}
  end

  def handle_event("autosave_now", params, socket) do
    staged = Autosave.content_params(params, Autosave.keys(@autosave_fields))
    if socket.assigns.autosave_timer, do: Process.cancel_timer(socket.assigns.autosave_timer)
    send(self(), :autosave)
    {:noreply, assign(socket, autosave_params: staged, autosave_timer: nil)}
  end

  def handle_event("save", %{"page" => params}, socket) do
    case persist(socket, params) do
      {:ok, page} ->
        {:noreply,
         socket
         |> assign(:page, page)
         |> assign(:save_state, :saved)
         |> put_flash(:info, "Saved.")
         |> push_navigate(to: ~p"/admin/pages")}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, assign_form(socket, Map.put(cs, :action, :insert))}

      {:error, :stale} ->
        {:noreply, put_flash(socket, :error, "This page changed elsewhere; reload to continue.")}
    end
  end

  def handle_event("delete", _params, socket) do
    {:ok, _} = Pages.delete_page(socket.assigns.page)
    {:noreply, push_navigate(socket, to: ~p"/admin/pages")}
  end

  @impl true
  def handle_info(:autosave, socket) do
    page = socket.assigns.page

    if page.published == false and socket.assigns.autosave_params do
      case persist(socket, socket.assigns.autosave_params) do
        {:ok, saved} -> {:noreply, socket |> assign(page: saved, save_state: :saved, autosave_params: nil)}
        {:error, :stale} -> {:noreply, assign(socket, :save_state, :conflict)}
        {:error, %Ecto.Changeset{}} -> {:noreply, assign(socket, :save_state, :error)}
      end
    else
      {:noreply, socket}
    end
  end

  defp persist(%{assigns: %{page: %Page{id: nil}}}, params), do: Pages.create_page(params)
  defp persist(%{assigns: %{page: page}}, params), do: Pages.update_page(page, params)

  defp maybe_schedule_autosave(socket) do
    if socket.assigns.page.published == false do
      assign(socket, :autosave_timer, Autosave.schedule(socket.assigns.autosave_timer))
    else
      socket
    end
  end

  defp handle_inline_upload(:inline_images, entry, socket) do
    InlineImageUpload.handle_progress(entry, socket, %{
      name: :inline_images,
      ensure: &ensure_page/1,
      attach: fn %Page{} = page, key, filename -> Pages.attach_image(page, key, filename) end
    })
  end

  defp ensure_page(%{assigns: %{page: %Page{id: nil}}} = socket) do
    {:ok, page} = Pages.create_page(%{title: "Untitled", slug: next_untitled_slug(), body_markdown: ""})

    socket =
      socket
      |> assign(:page, page)
      |> push_patch(to: ~p"/admin/pages/#{page.id}/edit")

    {socket, page}
  end

  defp ensure_page(%{assigns: %{page: page}} = socket), do: {socket, page}

  defp next_untitled_slug do
    "untitled-page-" <> Integer.to_string(System.unique_integer([:positive]))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current={:pages}>
      <Components.page_header title="Edit page">
        <Components.button type="button" variant="danger" id="page-delete" phx-click="delete">
          Delete
        </Components.button>
      </Components.page_header>

      <.form for={@form} id="page-form" phx-submit="save" phx-change="validate" phx-auto-recover="recover">
        <input type="hidden" name="page[lock_version]" value={@page.lock_version} />
        <.input field={@form[:title]} type="text" label="Title" phx-blur="autosave_now" />
        <.input field={@form[:slug]} type="text" label="Slug" phx-blur="autosave_now" />
        <.input field={@form[:meta_description]} type="text" label="Meta description" />
        <.input field={@form[:published]} type="checkbox" label="Published" />

        <div id={"body-editor-#{@editor_key}"} phx-update="ignore">
          <textarea id="page-body-source" name="page[body_markdown]" class="sr-only">{Phoenix.HTML.Form.input_value(@form, :body_markdown)}</textarea>
          <div
            id={"markdown-editor-#{@editor_key}"}
            phx-hook="MarkdownEditor"
            data-input-id="page-body-source"
            data-upload-accept={Enum.join(InlineImageUpload.accept(), ",")}
            data-upload-max-entries={InlineImageUpload.max_entries()}
            data-upload-max-file-size={InlineImageUpload.max_file_size()}
          >
          </div>
        </div>

        <.live_file_input upload={@uploads.inline_images} class="sr-only" />
        <Components.button type="submit">Save</Components.button>
      </.form>

      <div id="unsaved-guard" phx-hook="UnsavedGuard" data-dirty={to_string(@save_state != :saved)}></div>
    </Layouts.admin>
    """
  end

  @impl true
  def handle_event("recover", %{"page" => params}, socket) do
    {:noreply, assign_form(socket, socket.assigns.page |> Pages.change_page(params) |> Map.put(:action, :validate))}
  end
end
```

> This editor mirrors the post editor's structure but is deliberately leaner. Read `post_live/editor.ex` while implementing to match the exact `MarkdownEditor` data-attribute names, the hidden-textarea wiring (`data-input-id`), the `phx-auto-recover` contract, and the `UnsavedGuard` attributes — copy those conventions verbatim so the shared JS hooks behave identically. Do **not** add the drawer, social card, scheduling, preview token, or `PublicationNotifier`.

- [ ] **Step 4: Run — passes.**

Run: `PORT=4001 mix test test/newton_web/live/admin/page_editor_live_test.exs`
Expected: PASS (submit-persist, autosave, inline upload, reserved-slug error, delete).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "Add lean admin Pages editor with shared autosave and inline uploads"
```

---

## Task 12: Dashboard Pages count card

**Files:**
- Modify: `lib/newton_web/live/admin/dashboard_live.ex`
- Test: extend `test/newton_web/live/admin/dashboard_live_test.exs` (or create if absent) with a behavior assertion.

**Interfaces:**
- Consumes: `Pages.count_pages/0`, `Pages.count_drafts/0`.

- [ ] **Step 1: Write a failing test.**

```elixir
  test "dashboard shows the pages count", %{conn: conn} do
    {:ok, _} = Newton.Pages.create_page(%{slug: "about", title: "About", body_markdown: "", published: true})
    {:ok, view, _html} = live(conn, ~p"/admin")
    assert has_element?(view, "#card-pages")
    assert render(view) =~ "Pages"
  end
```

- [ ] **Step 2: Run — fails.**

Run: `PORT=4001 mix test test/newton_web/live/admin/dashboard_live_test.exs`
Expected: FAIL, no `#card-pages`.

- [ ] **Step 3: Implement.** In `dashboard_live.ex` `mount/3`, add:

```elixir
     |> assign(:pages_total, Newton.Pages.count_pages())
     |> assign(:pages_drafts, Newton.Pages.count_drafts())
```

In `render/1`, add a card and widen the grid to hold five (change `xl:grid-cols-4` → `xl:grid-cols-5` on the card grid `div`):

```heex
        <.card id="card-pages" title="Pages" primary={@pages_total} path="/admin/pages">
          {@pages_drafts} draft{if @pages_drafts == 1, do: "", else: "s"}
        </.card>
```

Place it after the Posts card.

- [ ] **Step 4: Run — passes.**

Run: `PORT=4001 mix test test/newton_web/live/admin/dashboard_live_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "Add Pages count card to the admin dashboard"
```

---

## Final: full suite + precommit

- [ ] **Run the entire suite** on the alt port: `PORT=4001 mix test`
- [ ] **Run `mix precommit`** and fix everything it reports.
- [ ] Confirm no route shadowing, no compiler warnings, and the post editor tests still pass (the extraction regression guard).

---

## Self-Review

**Spec coverage:**
- Decision summary (draft/published boolean, `/:slug`, lean editor, URL-only nav, mirror image table, code sharing) → Tasks 5–12 + Phase A. ✅
- Guiding principle — 6 extractions: (1) Storage lift → Task 0 ✅; (2) inline-image upload flow + constants + `referenced?` → Tasks 1–2 ✅; (3) autosave engine (clean core, Option 1) → Task 3 ✅; (4) draft-on-first-image `ensure_record` → folded into Task 2's `ensure`/Task 11's `ensure_page` ✅; (5) public content article component → Task 4 ✅; (6) admin index list/row chrome → already shared `Components.list`; Task 10 consumes it (no new extraction needed — noted) ✅.
- Data model (pages + page_images columns, changeset with `ensure_body`, reserved slugs, `optimistic_lock`, cascade) → Tasks 5–6 ✅.
- Context `Newton.Pages` (list/get/published lookup/create/update-stale/delete/change/images) → Tasks 7–8 ✅.
- Routing (catch-all last, admin routes) → Tasks 9–10 ✅.
- Public `PageContentController` (published/draft-admin/404) → Task 9 ✅.
- Admin index + lean editor + nav + dashboard card → Tasks 10–12 ✅.
- Error handling (404, reserved/dup slug, stale, image store failure) → Tasks 9 (404), 11 (reserved/dup, stale), 2 (store failure flash) ✅.
- Testing (context, public, admin — behavior-focused) → covered per task ✅.
- Out of scope (no auto-nav, no scheduling/preview/social/excerpt, `/resume` untouched, no polymorphic abstraction) → honored; none added. ✅

**Placeholder scan:** The two extraction tasks (2, 3) and the editor (11) carry "read the existing file and match its exact conventions" notes rather than reproducing every private body verbatim — this is deliberate for refactors of subtle existing code guarded by green tests, not a TODO. All *new* modules, schemas, migrations, controller, templates, and tests contain real code. No "add error handling"/"TBD"/"similar to Task N" placeholders.

**Type consistency:** `Newton.Storage.{store/2, delete/1, url/1}`, `Newton.Images.referenced?/2`, `InlineImageUpload.{accept/0, max_entries/0, max_file_size/0, split_token/1, handle_progress/3}`, `Autosave.{debounce_ms/0, keys/1, content_params/2, schedule/1, dirty?/2}`, `Pages.{list_pages/0, get_page!/1, get_page_by_slug/1, get_published_page_by_slug/1, create_page/1, update_page/2, delete_page/1, change_page/2, count_pages/0, count_drafts/0, attach_image/3, list_images/1, delete_image/1}`, `Page.{changeset/2, reserved_slugs/0}`, `PageImage.create_changeset/2` — names are used consistently across producing and consuming tasks. DOM IDs `#page-form`/`#page-delete`/`#pages`/`#card-pages` match between editor/index/dashboard and their tests.
