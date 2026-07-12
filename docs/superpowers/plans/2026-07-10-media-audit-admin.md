# Media Audit in the Admin — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A read-only `ImageAudit` engine powering an `/admin/media` page (orphan list with guarded delete, missing-file list linking to posts) and a dashboard drift notice — surviving the planned deletion of the adopt-only backfill.

**Architecture:** Split today's `Newton.Blog.ImageBackfill` into `Newton.Blog.ImageAudit` (read-only: missing/strays/stray?/delete_stray, owns the `/media/<key>` extraction) and a slimmed adoption-only backfill that consumes it. A new `NewtonWeb.Admin.MediaLive` computes the audit live on mount; `DashboardLive` shows a notice only when drift exists.

**Tech Stack:** Phoenix 1.8 LiveView, Ecto, existing `Newton.Gallery.Storage`. No JS changes, no new tables.

**Spec:** `docs/superpowers/specs/2026-07-10-media-audit-admin-design.md`

## Global Constraints

- **COMMIT HOLD:** James has instructed that nothing be committed until he says otherwise. Leave every "Commit" step unchecked; do not run `git commit`.
- **No narrating comments** (AGENTS.md): comments only for constraints the code cannot express.
- **`@spec` on every public function** under `lib/newton/**` (domain layer), matching `lib/newton/blog.ex` style.
- The post body field is **`body_markdown`**.
- A **stray** is a volume file owned by neither `photos` (image_key/thumb_key) nor `post_images` AND referenced by no post body — `run/0`'s stray list and `stray?/1` use the same predicate.
- Volume listing **excludes dotfiles** (`.keep`).
- `ImageBackfill` + its mix task must remain deletable without touching the admin page (the page depends only on `ImageAudit`).
- Tests assert behaviors via DOM ids and context functions, not markup structure.
- Test media root: `Path.join(System.tmp_dir!(), "newton_test_media")` (config/test.exs).
- Finish the whole plan with `mix precommit`.

## File Structure

| File | Responsibility |
|---|---|
| `lib/newton/blog/image_audit.ex` | read-only audit engine + guarded stray deletion |
| `lib/newton/blog/image_backfill.ex` | adoption only (slimmed); consumes ImageAudit |
| `lib/mix/tasks/newton.post_images.backfill.ex` | prints adoption + audit report |
| `lib/newton_web/live/admin/media_live.ex` | the /admin/media page |
| `lib/newton_web/router.ex` | one new route in the `:admin` live_session |
| `lib/newton_web/components/admin/layouts.ex` | "Media" nav section |
| `lib/newton_web/live/admin/dashboard_live.ex` | drift notice |
| `test/newton/blog/image_audit_test.exs` | audit engine tests |
| `test/newton/blog/image_backfill_test.exs` | updated for the slimmed return |
| `test/newton_web/live/admin/media_live_test.exs` | page behavior tests |
| `test/newton_web/live/admin/dashboard_drift_test.exs` | drift-notice tests (new, async: false) |

---

### Task 1: `Newton.Blog.ImageAudit` — the read-only engine

**Files:**
- Create: `lib/newton/blog/image_audit.ex`
- Test: `test/newton/blog/image_audit_test.exs`

**Interfaces:**
- Consumes: `Newton.Blog.Post` (`body_markdown`, `slug`), `Newton.Blog.PostImage`, `Newton.Gallery.Photo` (`image_key`, `thumb_key`), `Newton.Gallery.Storage.delete/1`, `:media_root` config.
- Produces (later tasks rely on these exactly): `ImageAudit.run/0` → `%{missing: [{slug :: String.t(), key :: String.t()}], strays: [String.t()]}`; `ImageAudit.stray?(key)` → `boolean`; `ImageAudit.delete_stray(key)` → `:ok | {:error, :not_stray}`; `ImageAudit.extract_keys(body_or_nil)` → `[String.t()]` (unique, document order).

- [ ] **Step 1: Write the failing tests**

Create `test/newton/blog/image_audit_test.exs`:

```elixir
defmodule Newton.Blog.ImageAuditTest do
  use Newton.DataCase
  alias Newton.Blog
  alias Newton.Blog.ImageAudit

  defp media_root, do: Application.fetch_env!(:newton, :media_root)

  defp stored_file(key) do
    File.mkdir_p!(media_root())
    path = Path.join(media_root(), key)
    File.write!(path, "img-bytes")
    path
  end

  defp post_with_body(body) do
    {:ok, post} =
      Blog.create_post(%{
        slug: "post-#{System.unique_integer([:positive])}",
        title: "A Post",
        body_markdown: body
      })

    post
  end

  setup do
    File.rm_rf!(media_root())
    File.mkdir_p!(media_root())
    :ok
  end

  test "extract_keys pulls unique /media/ keys from a body, nil-safe" do
    body = "![](/media/a.png) text ![](/media/b.jpg) again ![](/media/a.png)"
    assert ImageAudit.extract_keys(body) == ["a.png", "b.jpg"]
    assert ImageAudit.extract_keys(nil) == []
  end

  test "run reports missing keys and unowned strays" do
    post = post_with_body("![](/media/ghost.png)")
    stored_file("stray.png")

    assert %{missing: [{slug, "ghost.png"}], strays: ["stray.png"]} = ImageAudit.run()
    assert slug == post.slug
  end

  test "run ignores dotfiles on the volume" do
    stored_file(".keep")
    assert %{strays: []} = ImageAudit.run()
  end

  test "run does not list ledgered, gallery-owned, or body-referenced files as strays" do
    post = post_with_body("![](/media/ledgered.png) ![](/media/referenced.png)")
    {:ok, _} = Blog.attach_image(post, "ledgered.png", nil)

    group = Newton.GalleryFixtures.group_fixture()
    photo = Newton.GalleryFixtures.photo_fixture(group)

    stored_file("ledgered.png")
    stored_file("referenced.png")
    stored_file(photo.image_key)

    assert %{strays: []} = ImageAudit.run()
  end

  test "delete_stray removes a true stray's file" do
    path = stored_file("stray.png")

    assert :ok = ImageAudit.delete_stray("stray.png")
    refute File.exists?(path)
  end

  test "delete_stray refuses owned or referenced keys" do
    post = post_with_body("![](/media/referenced.png)")
    {:ok, _} = Blog.attach_image(post, "ledgered.png", nil)
    referenced = stored_file("referenced.png")
    ledgered = stored_file("ledgered.png")

    assert {:error, :not_stray} = ImageAudit.delete_stray("referenced.png")
    assert {:error, :not_stray} = ImageAudit.delete_stray("ledgered.png")
    assert File.exists?(referenced)
    assert File.exists?(ledgered)
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/newton/blog/image_audit_test.exs`
Expected: FAIL — `Newton.Blog.ImageAudit` is undefined.

- [ ] **Step 3: Implement**

Create `lib/newton/blog/image_audit.ex`:

```elixir
defmodule Newton.Blog.ImageAudit do
  @moduledoc """
  Read-only audit of the media volume against its owners (gallery photos,
  the post-images ledger, and post bodies), plus guarded deletion of true
  strays. Never touches owned or referenced files.
  """
  import Ecto.Query
  alias Newton.Blog.{Post, PostImage}
  alias Newton.Gallery.Photo
  alias Newton.Gallery.Storage
  alias Newton.Repo

  @media_url ~r{/media/([A-Za-z0-9_-]+\.[A-Za-z0-9]+)}

  @spec run() :: %{missing: [{String.t(), String.t()}], strays: [String.t()]}
  def run do
    posts = Repo.all(from p in Post, order_by: p.id, select: {p.slug, p.body_markdown})
    volume = volume_keys()
    referenced = MapSet.new(Enum.flat_map(posts, fn {_slug, body} -> extract_keys(body) end))
    owned = MapSet.union(ledger_keys(), photo_keys())

    missing =
      for {slug, body} <- posts,
          key <- extract_keys(body),
          not MapSet.member?(volume, key),
          do: {slug, key}

    strays =
      volume
      |> MapSet.difference(owned)
      |> MapSet.difference(referenced)
      |> Enum.sort()

    %{missing: missing, strays: strays}
  end

  @spec stray?(String.t()) :: boolean()
  def stray?(key) do
    key in run().strays
  end

  @spec delete_stray(String.t()) :: :ok | {:error, :not_stray}
  def delete_stray(key) do
    if stray?(key) do
      Storage.delete(key)
    else
      {:error, :not_stray}
    end
  end

  @spec extract_keys(String.t() | nil) :: [String.t()]
  def extract_keys(body) do
    @media_url
    |> Regex.scan(body || "")
    |> Enum.map(fn [_, key] -> key end)
    |> Enum.uniq()
  end

  @spec ledger_keys() :: MapSet.t(String.t())
  def ledger_keys do
    MapSet.new(Repo.all(from i in PostImage, select: i.key))
  end

  @spec photo_keys() :: MapSet.t(String.t())
  def photo_keys do
    Repo.all(from p in Photo, select: {p.image_key, p.thumb_key})
    |> Enum.flat_map(fn {a, b} -> [a, b] end)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  @spec volume_keys() :: MapSet.t(String.t())
  def volume_keys do
    root = Application.fetch_env!(:newton, :media_root)

    case File.ls(root) do
      {:ok, entries} ->
        entries
        |> Enum.reject(&String.starts_with?(&1, "."))
        |> Enum.filter(&File.regular?(Path.join(root, &1)))
        |> MapSet.new()

      {:error, _} ->
        MapSet.new()
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/newton/blog/image_audit_test.exs`
Expected: 6 tests, 0 failures.

- [ ] **Step 5: Commit** *(skip while the commit hold stands)*

```bash
git add lib/newton/blog/image_audit.ex test/newton/blog/image_audit_test.exs
git commit -m "Add the read-only media audit with guarded stray deletion"
```

---

### Task 2: Slim `ImageBackfill` to adoption-only

**Files:**
- Modify: `lib/newton/blog/image_backfill.ex` (whole file — new version below)
- Modify: `lib/mix/tasks/newton.post_images.backfill.ex`
- Test: `test/newton/blog/image_backfill_test.exs` (adjust)

**Interfaces:**
- Consumes: `ImageAudit.extract_keys/1`, `ImageAudit.ledger_keys/0`, `ImageAudit.photo_keys/0`, `ImageAudit.volume_keys/0` (Task 1), `PostImage.create_changeset/2` (post_id set on the struct, never cast).
- Produces: `ImageBackfill.run/0` → `%{adopted: [String.t()]}`. This module + the mix task remain the complete deletable set for the post-backfill removal deploy.

- [ ] **Step 1: Adjust the tests**

In `test/newton/blog/image_backfill_test.exs`: the missing/strays behavior moved to `ImageAuditTest`. Update the reporting test and return-shape assertions:

- Delete the test `"reports referenced-but-missing keys and unowned volume strays"` (now covered by `ImageAuditTest`).
- In the remaining tests, every `report.adopted` / `%{adopted: ...}` assertion stays as-is; remove any reference to `report.missing` or `report.strays`.

The file keeps: "adopts referenced on-volume files, skipping already-tracked ones", "never adopts gallery photo keys", "is idempotent".

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/newton/blog/image_backfill_test.exs`
Expected: still green at this point (return shape not yet changed) — this step establishes the baseline; the shape change lands next.

- [ ] **Step 3: Replace the module**

Replace `lib/newton/blog/image_backfill.ex` with:

```elixir
defmodule Newton.Blog.ImageBackfill do
  @moduledoc """
  One-time adoption of untracked inline post images into the post_images
  ledger. Delete this module (and its mix task) after the production run;
  ongoing drift visibility lives in `Newton.Blog.ImageAudit` and /admin/media.
  """
  import Ecto.Query
  alias Newton.Blog.{ImageAudit, Post, PostImage}
  alias Newton.Repo

  @spec run() :: %{adopted: [String.t()]}
  def run do
    tracked = ImageAudit.ledger_keys()
    photo_keys = ImageAudit.photo_keys()
    volume = ImageAudit.volume_keys()

    adopted =
      Repo.all(from p in Post, order_by: p.id)
      |> Enum.reduce([], fn post, acc -> adopt_post(post, tracked, photo_keys, volume, acc) end)

    %{adopted: Enum.reverse(adopted)}
  end

  defp adopt_post(post, tracked, photo_keys, volume, adopted) do
    post.body_markdown
    |> ImageAudit.extract_keys()
    |> Enum.reduce(adopted, fn key, acc ->
      cond do
        MapSet.member?(tracked, key) or MapSet.member?(photo_keys, key) or key in acc ->
          acc

        MapSet.member?(volume, key) ->
          {:ok, _} =
            %PostImage{post_id: post.id}
            |> PostImage.create_changeset(%{key: key})
            |> Repo.insert()

          [key | acc]

        true ->
          acc
      end
    end)
  end
end
```

Update `lib/mix/tasks/newton.post_images.backfill.ex`'s `run/1` body to print adoption plus the audit:

```elixir
  @impl Mix.Task
  def run(_args) do
    %{adopted: adopted} = Newton.Blog.ImageBackfill.run()
    %{missing: missing, strays: strays} = Newton.Blog.ImageAudit.run()

    Mix.shell().info("adopted: #{length(adopted)}")
    Enum.each(adopted, &Mix.shell().info("  + #{&1}"))

    Mix.shell().info("missing from volume: #{length(missing)}")
    Enum.each(missing, fn {slug, key} -> Mix.shell().info("  ! #{slug}: #{key}") end)

    Mix.shell().info("unowned volume files: #{length(strays)}")
    Enum.each(strays, &Mix.shell().info("  ? #{&1}"))
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/newton/blog/image_backfill_test.exs test/newton/blog/image_audit_test.exs`
Expected: all pass.

- [ ] **Step 5: Commit** *(skip while the commit hold stands)*

```bash
git add lib/newton/blog/image_backfill.ex lib/mix/tasks/newton.post_images.backfill.ex test/newton/blog/image_backfill_test.exs
git commit -m "Slim the backfill to adoption-only atop the shared audit"
```

---

### Task 3: The `/admin/media` page

**Files:**
- Create: `lib/newton_web/live/admin/media_live.ex`
- Modify: `lib/newton_web/router.ex` (one line in the `:admin` live_session, after the `/photos` routes)
- Modify: `lib/newton_web/components/admin/layouts.ex` (`@sections` list)
- Test: `test/newton_web/live/admin/media_live_test.exs`

**Interfaces:**
- Consumes: `ImageAudit.run/0`, `ImageAudit.delete_stray/1` (Task 1), `Newton.Gallery.image_url/1`, `Blog` post lookup by slug.
- Produces: route `/admin/media`; DOM ids `#media-strays`, `#media-stray-<Path.rootname(key)>`, `#media-missing` (Task 4's notice links here).

- [ ] **Step 1: Write the failing tests**

Create `test/newton_web/live/admin/media_live_test.exs`:

```elixir
defmodule NewtonWeb.Admin.MediaLiveTest do
  # async: false + a private media root: the audit scans the volume directory,
  # and the globally shared tmp root accumulates files from other suites
  # (editor uploads), which would make clean-state assertions flaky.
  use NewtonWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Newton.AccountsFixtures

  setup %{conn: conn} do
    previous = Application.fetch_env!(:newton, :media_root)
    private = Path.join(System.tmp_dir!(), "newton_media_live_#{System.unique_integer([:positive])}")
    File.mkdir_p!(private)
    Application.put_env(:newton, :media_root, private)

    on_exit(fn ->
      Application.put_env(:newton, :media_root, previous)
      File.rm_rf!(private)
    end)

    %{conn: log_in_user(conn, user_fixture())}
  end

  defp media_root, do: Application.fetch_env!(:newton, :media_root)

  defp stored_file(key) do
    File.mkdir_p!(media_root())
    path = Path.join(media_root(), key)
    File.write!(path, "img-bytes")
    path
  end

  test "deleting a stray removes the file and its row", %{conn: conn} do
    path = stored_file("stray-one.png")

    {:ok, view, _html} = live(conn, ~p"/admin/media")
    assert has_element?(view, "#media-stray-stray-one")

    view |> element("#media-stray-stray-one button", "Delete") |> render_click()

    refute has_element?(view, "#media-stray-stray-one")
    refute File.exists?(path)
  end

  test "a forged delete for a referenced file is refused", %{conn: conn} do
    {:ok, _post} =
      Newton.Blog.create_post(%{
        slug: "with-image",
        title: "With Image",
        body_markdown: "![](/media/kept.png)"
      })

    path = stored_file("kept.png")

    {:ok, view, _html} = live(conn, ~p"/admin/media")
    render_click(view, "delete_stray", %{"key" => "kept.png"})

    assert File.exists?(path)
  end

  test "a missing file links to the post that references it", %{conn: conn} do
    {:ok, post} =
      Newton.Blog.create_post(%{
        slug: "broken-post",
        title: "Broken",
        body_markdown: "![](/media/gone.png)"
      })

    {:ok, view, _html} = live(conn, ~p"/admin/media")
    assert has_element?(view, "#media-missing")

    view
    |> element("#media-missing a", "broken-post")
    |> render_click()

    assert_redirect(view, "/admin/posts/#{post.id}/edit")
  end

  test "clean volume renders both empty states", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/media")

    assert render(view) =~ "No orphaned files"
    assert render(view) =~ "No missing files"
  end
end
```

The private-media-root setup above is what makes the "clean volume" test deterministic; do not switch this module to `async: true` (Application env is global).

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/newton_web/live/admin/media_live_test.exs`
Expected: FAIL — route `/admin/media` does not exist.

- [ ] **Step 3: Implement**

Router — add inside the `:admin` live_session, after the `/photos` lines:

```elixir
      live "/media", MediaLive, :index
```

Nav — in `lib/newton_web/components/admin/layouts.ex`, extend `@sections`:

```elixir
  @sections [
    %{key: :dashboard, label: "Dashboard", path: "/admin"},
    %{key: :posts, label: "Posts", path: "/admin/posts"},
    %{key: :reading, label: "Reading", path: "/admin/reading"},
    %{key: :photos, label: "Photos", path: "/admin/photos"},
    %{key: :media, label: "Media", path: "/admin/media"}
  ]
```

Create `lib/newton_web/live/admin/media_live.ex`:

```elixir
defmodule NewtonWeb.Admin.MediaLive do
  use NewtonWeb, :live_view

  alias Newton.Blog.ImageAudit
  alias Newton.Gallery
  alias NewtonWeb.Admin.Layouts

  @impl true
  def mount(_params, _session, socket) do
    {:ok, load_audit(socket)}
  end

  @impl true
  def handle_event("delete_stray", %{"key" => key}, socket) do
    ImageAudit.delete_stray(key)
    {:noreply, load_audit(socket)}
  end

  defp load_audit(socket) do
    audit = ImageAudit.run()
    slugs = audit.missing |> Enum.map(fn {slug, _key} -> slug end) |> Enum.uniq()

    post_ids =
      Map.new(Newton.Repo.all(
        from p in Newton.Blog.Post, where: p.slug in ^slugs, select: {p.slug, p.id}
      ))

    socket
    |> assign(:strays, Enum.map(audit.strays, &stray_entry/1))
    |> assign(:missing, audit.missing)
    |> assign(:post_ids, post_ids)
  end

  defp stray_entry(key) do
    root = Application.fetch_env!(:newton, :media_root)

    size =
      case File.stat(Path.join(root, key)) do
        {:ok, %{size: size}} -> size
        {:error, _} -> 0
      end

    %{key: key, dom_id: "media-stray-#{Path.rootname(key)}", size: size}
  end

  defp format_bytes(bytes) when bytes >= 1_000_000, do: "#{Float.round(bytes / 1_000_000, 1)} MB"
  defp format_bytes(bytes) when bytes >= 1_000, do: "#{div(bytes, 1_000)} KB"
  defp format_bytes(bytes), do: "#{bytes} B"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current={:media}>
      <h1 class="mb-6 text-[1.35rem] font-semibold tracking-tight">Media</h1>

      <section id="media-strays" class="mb-8">
        <h2 class="mb-3 text-[0.78rem] uppercase tracking-wide text-(--admin-text-subtle)">
          Orphaned files
        </h2>
        <p :if={@strays == []} class="text-[0.85rem] text-(--admin-text-muted)">
          No orphaned files.
        </p>
        <ul :if={@strays != []} class="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <li
            :for={stray <- @strays}
            id={stray.dom_id}
            class="rounded-lg border border-(--admin-border) bg-(--admin-surface) p-2"
          >
            <img src={Gallery.image_url(stray.key)} alt="" class="h-24 w-full rounded object-cover" />
            <div class="mt-2 flex items-center justify-between gap-2 text-[0.72rem] text-(--admin-text-subtle)">
              <span class="truncate">{stray.key} · {format_bytes(stray.size)}</span>
              <button
                type="button"
                phx-click="delete_stray"
                phx-value-key={stray.key}
                data-confirm="Delete this file? Nothing references it, and this cannot be undone."
                class="shrink-0 text-red-400 hover:text-red-300"
              >
                Delete
              </button>
            </div>
          </li>
        </ul>
      </section>

      <section id="media-missing">
        <h2 class="mb-3 text-[0.78rem] uppercase tracking-wide text-(--admin-text-subtle)">
          Missing files
        </h2>
        <p :if={@missing == []} class="text-[0.85rem] text-(--admin-text-muted)">
          No missing files.
        </p>
        <ul :if={@missing != []} class="flex flex-col gap-1.5">
          <li :for={{slug, key} <- @missing} class="text-[0.85rem] text-(--admin-text)">
            <span class="font-mono text-[0.78rem]">{key}</span>
            referenced by
            <.link
              :if={@post_ids[slug]}
              navigate={~p"/admin/posts/#{@post_ids[slug]}/edit"}
              class="text-(--admin-accent)"
            >
              {slug}
            </.link>
            <span :if={!@post_ids[slug]}>{slug}</span>
          </li>
        </ul>
      </section>
    </Layouts.admin>
    """
  end
end
```

Add `import Ecto.Query` to the module's top (needed by `load_audit`'s query), alongside the aliases.

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/newton_web/live/admin/media_live_test.exs`
Expected: 4 tests, 0 failures. Also run `mix test test/newton_web/live/admin/admin_shell_test.exs` — the nav change must not break the shell tests.

- [ ] **Step 5: Commit** *(skip while the commit hold stands)*

```bash
git add lib/newton_web/live/admin/media_live.ex lib/newton_web/router.ex lib/newton_web/components/admin/layouts.ex test/newton_web/live/admin/media_live_test.exs
git commit -m "Add /admin/media: orphaned-file cleanup and missing-file visibility"
```

---

### Task 4: Dashboard drift notice

**Files:**
- Modify: `lib/newton_web/live/admin/dashboard_live.ex`
- Test: `test/newton_web/live/admin/dashboard_drift_test.exs` (new file — the existing
  `dashboard_live_test.exs` stays untouched; drift tests need the private-media-root,
  `async: false` setup and must not impose it on the existing suite)

**Interfaces:**
- Consumes: `ImageAudit.run/0` (Task 1); route `/admin/media` (Task 3).
- Produces: DOM id `#media-drift` (present only when drift exists).

- [ ] **Step 1: Write the failing tests**

Create `test/newton_web/live/admin/dashboard_drift_test.exs` with the SAME `use NewtonWeb.ConnCase, async: false` + private-media-root `setup` block as Task 3's `MediaLiveTest` (copy it, including the module comment and `stored_file/1` helper, with directory prefix `newton_dashboard_drift_`), then:

```elixir
  test "shows a media drift notice when the volume disagrees with the ledger", %{conn: conn} do
    stored_file("dash-stray.png")

    {:ok, view, _html} = live(conn, ~p"/admin")
    assert has_element?(view, "#media-drift")

    view |> element("#media-drift") |> render_click()
    assert_redirect(view, "/admin/media")
  end

  test "no drift notice when volume and ledger agree", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin")
    refute has_element?(view, "#media-drift")
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/newton_web/live/admin/dashboard_drift_test.exs`
Expected: the two new tests FAIL (no `#media-drift` ever renders / element not found).

- [ ] **Step 3: Implement**

In `lib/newton_web/live/admin/dashboard_live.ex`:

a) Alias + mount assign:

```elixir
  alias Newton.Blog.ImageAudit
```

In `mount/3`, add to the pipeline:

```elixir
     |> assign(:media_drift, media_drift())
```

with:

```elixir
  defp media_drift do
    case ImageAudit.run() do
      %{missing: [], strays: []} -> nil
      audit -> audit
    end
  end
```

b) In `render/1`, after the closing `</div>` of the cards grid:

```elixir
      <.link
        :if={@media_drift}
        id="media-drift"
        navigate={~p"/admin/media"}
        class="mt-4 block rounded-xl border border-amber-500/40 bg-(--admin-surface) p-4 text-[0.85rem] text-(--admin-text) no-underline hover:border-amber-500/70"
      >
        {drift_summary(@media_drift)} →
      </.link>
```

with:

```elixir
  defp drift_summary(%{strays: strays, missing: missing}) do
    [
      count_phrase(length(strays), "orphaned file"),
      count_phrase(length(missing), "missing image")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp count_phrase(0, _noun), do: nil
  defp count_phrase(1, noun), do: "1 #{noun}"
  defp count_phrase(n, noun), do: "#{n} #{noun}s"
end
```

(`count_phrase` clauses go above the module's final `end`; adjust placement to keep the file's private-helpers-last convention.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/newton_web/live/admin/dashboard_drift_test.exs test/newton_web/live/admin/dashboard_live_test.exs test/newton_web/live/admin/media_live_test.exs`
Expected: all pass (including the untouched existing dashboard suite).

- [ ] **Step 5: Full gate**

Run: `mix precommit`
Expected: clean (compile --warnings-as-errors, format, credo --strict, full ExUnit, vitest, dialyzer).

- [ ] **Step 6: Commit** *(skip while the commit hold stands)*

```bash
git add lib/newton_web/live/admin/dashboard_live.ex test/newton_web/live/admin/dashboard_drift_test.exs
git commit -m "Surface media drift on the admin dashboard"
```

---

## Post-plan notes

- The post-backfill **removal deploy** deletes exactly: `lib/newton/blog/image_backfill.ex`, `lib/mix/tasks/newton.post_images.backfill.ex`, `test/newton/blog/image_backfill_test.exs`. Nothing in the admin depends on them.
- Deploy scope reminder: `fly deploy` ships the working tree; confirm scope with James before any deploy.
