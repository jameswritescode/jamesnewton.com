# Admin Photos Section Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the admin Photos section — a galleries list with a settings drawer, and an in-gallery manager with drag-drop upload, drag-to-reorder, alt-text editing, and per-photo delete.

**Architecture:** Two LiveViews (`GalleryLive.Index` for the galleries list + settings drawer, `GalleryLive.Show` for the in-gallery manager) plus a `Newton.Gallery.Storage` module that owns all filesystem I/O. Dimensions are captured client-side at upload and pushed to the server; reordering uses a custom sortable JS hook. Reuses the shared `NewtonWeb.Admin.Components` drawer/field and a newly extracted slug-autofill helper.

**Tech Stack:** Phoenix 1.8 LiveView (`allow_upload`, streams), Ecto/Postgres, the admin token theme, two small JS hooks (no external libs), Vitest.

---

## Context for the implementer

Read the spec first: `docs/superpowers/specs/2026-06-11-admin-photos-design.md`.

**Existing code to reuse (do not duplicate):**

- **Schema (migrated, no migration needed):**
  - `lib/newton/gallery/photo_group.ex` — `slug, title, caption, taken_on`, `has_many :photos` (`preload_order: [asc: :position]`); `changeset` requires `slug`+`title`, `unique_constraint(:slug)`.
  - `lib/newton/gallery/photo.ex` — `image_key, alt, position, width, height`, `belongs_to :photo_group` (FK `on_delete: :delete_all`).
- **Context `lib/newton/gallery.ex`** — already has `create_group/1`, `add_photo/2`, `list_groups/0`, `count_groups/0`, `count_photos/0`, `recent_groups/1`, `image_url/1`. This plan ADDS the admin CRUD, `reorder_photos/2`, `next_position/1`, and file-aware deletes.
- **Serving:** `Plug.Static` serves `/media` from `media_root` (config: `priv/media` dev, `/data/images` prod). `Gallery.image_url(key)` → `/media/<key>`. No serving changes.
- **Shared admin components `lib/newton_web/components/admin/components.ex`:** `Components.drawer/1` (slide-over, closes on button/Escape/click-away, animates) and `Components.field/1` (admin-themed `<.input>` wrapper). Reuse both.
- **Patterns to mirror:**
  - URL-backed list + drawer: `lib/newton_web/live/admin/reading_live/index.ex`.
  - Stretched-link rows + delete-above: `lib/newton_web/live/admin/post_live/index.ex`.
  - Slug autofill: `lib/newton_web/live/admin/post_live/editor.ex` (`autofill/5`, `slug_locked?`).
  - Nav `@built` + badges: `lib/newton_web/components/admin/layouts.ex`.
  - JS hook + Vitest: `assets/js/hooks/admin_theme.js` + `admin_theme.test.js`; hooks registered in `assets/js/admin.js`.
  - LiveView test conventions: `test/newton_web/live/admin/reading_live_test.exs` (`log_in_user(user_fixture())`, `form/2`, `assert_patch`).

**Project rules:** pnpm (not npm/npx) in `assets/`. TDD: failing test first. No narrating comments — name helpers well. **Test behaviors, not template structure.** Run `mix precommit` at the end. Screenshots via `cd assets && node screenshot.mjs <path>=<name>` (Playwright; admin login your local admin credentials).

## File structure

| File | Responsibility | Action |
| --- | --- | --- |
| `lib/newton_web/admin/form_helpers.ex` | `autofill/5` slug/derived-field helper (extracted) | Create |
| `lib/newton_web/live/admin/post_live/editor.ex` | Use the extracted helper | Modify |
| `lib/newton/gallery/photo.ex` | Blank-alt default | Modify |
| `lib/newton/gallery/storage.ex` | Filesystem store/delete | Create |
| `lib/newton/gallery.ex` | Admin CRUD, reorder, file-aware deletes | Modify |
| `lib/newton_web/components/admin/layouts.ex` | `@built` adds `:photos` | Modify |
| `lib/newton_web/router.ex` | Photos routes | Modify |
| `lib/newton_web/live/admin/gallery_live/index.ex` | Galleries list + settings drawer | Create |
| `lib/newton_web/live/admin/gallery_live/show.ex` | In-gallery manager | Create |
| `assets/js/hooks/image_dimensions.js` | Read naturalWidth/Height, push to server | Create |
| `assets/js/hooks/sortable_grid.js` | Drag-to-reorder, push ID order | Create |
| `assets/js/admin.js` | Register the two hooks | Modify |
| `test/newton/gallery_test.exs` | Context + reorder + file-aware delete tests | Modify |
| `test/newton/gallery/storage_test.exs` | Storage tests | Create |
| `test/newton_web/live/admin/gallery_index_live_test.exs` | Index tests | Create |
| `test/newton_web/live/admin/gallery_show_live_test.exs` | Show tests | Create |
| `test/support/fixtures/gallery_fixtures.ex` | Gallery/photo test fixtures | Create |
| `assets/js/hooks/image_dimensions.test.js` | Dimension hook unit test | Create |
| `assets/js/hooks/sortable_grid.test.js` | Sortable hook unit test | Create |

---

## Task 1: Extract the slug-autofill helper

**Files:**
- Create: `lib/newton_web/admin/form_helpers.ex`
- Modify: `lib/newton_web/live/admin/post_live/editor.ex`
- Test: `test/newton_web/live/admin/post_editor_live_test.exs` (existing — must stay green)

The post editor's `autofill/5` (derive a field until the user edits it) will be reused by gallery settings. Extract it verbatim into a shared module.

- [ ] **Step 1: Create the helper module**

Create `lib/newton_web/admin/form_helpers.ex`:

```elixir
defmodule NewtonWeb.Admin.FormHelpers do
  @moduledoc "Shared helpers for admin LiveView forms."

  @doc """
  Derive a param field from another until the user takes it over. Returns
  `{params, new_auto}`: when locked, params and the previous auto value pass
  through unchanged; when unlocked, `derive` recomputes the value, writes it into
  params, and becomes the new auto baseline.
  """
  def autofill(params, _field, true, prev_auto, _derive), do: {params, prev_auto}

  def autofill(params, field, false, _prev_auto, derive) do
    value = derive.()
    {Map.put(params, field, value), value}
  end
end
```

- [ ] **Step 2: Use it from the post editor**

In `lib/newton_web/live/admin/post_live/editor.ex`, add the alias after the existing aliases:

```elixir
  alias NewtonWeb.Admin.FormHelpers
```

Replace the two `autofill(...)` call sites in `handle_event("validate", ...)` to call `FormHelpers.autofill(...)`:

```elixir
    {params, slug_auto} =
      FormHelpers.autofill(params, "slug", slug_locked, socket.assigns.slug_auto, fn ->
        Newton.Slug.slugify(params["title"] || "")
      end)

    {params, excerpt_auto} =
      FormHelpers.autofill(params, "excerpt", excerpt_locked, socket.assigns.excerpt_auto, fn ->
        Newton.Markdown.excerpt(params["body_markdown"] || "")
      end)
```

Then delete the now-unused private `autofill/5` clauses from the bottom of the module (the two `defp autofill(...)` definitions).

- [ ] **Step 3: Run the editor tests**

Run: `mix test test/newton_web/live/admin/post_editor_live_test.exs`
Expected: PASS — all 13 tests green (behavior unchanged; the slug/excerpt tests still pass).

- [ ] **Step 4: Commit**

```bash
git add lib/newton_web/admin/form_helpers.ex lib/newton_web/live/admin/post_live/editor.ex
git commit -m "Extract the slug-autofill helper for reuse"
```

---

## Task 2: Photo schema allows blank alt

**Files:**
- Modify: `lib/newton/gallery/photo.ex`
- Test: `test/newton/gallery_test.exs`

- [ ] **Step 1: Write the failing test**

Add to `test/newton/gallery_test.exs` (inside the module, before the final `end`):

```elixir
  test "a photo may be created with blank alt" do
    {:ok, g} = Gallery.create_group(%{slug: "blank-alt", title: "Blank Alt"})
    assert {:ok, photo} = Gallery.add_photo(g, %{image_key: "x.jpg", alt: "", position: 0})
    assert photo.alt == ""
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/newton/gallery_test.exs`
Expected: FAIL — `validate_required(:alt)` rejects the blank alt with "can't be blank".

- [ ] **Step 3: Update the schema**

In `lib/newton/gallery/photo.ex`, default `alt` and drop it from `validate_required`:

```elixir
    field :alt, :string, default: ""
```

and change the changeset's validation line to:

```elixir
    |> validate_required([:image_key, :position])
```

- [ ] **Step 4: Run it to verify it passes**

Run: `mix test test/newton/gallery_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/newton/gallery/photo.ex test/newton/gallery_test.exs
git commit -m "Allow photos to be saved with blank alt text"
```

---

## Task 3: Gallery.Storage (filesystem store/delete)

**Files:**
- Modify: `config/test.exs`
- Create: `lib/newton/gallery/storage.ex`
- Test: `test/newton/gallery/storage_test.exs`

`Storage` is the only module that touches disk. It reads `media_root` from
application config at runtime. Tests use a **constant** test media root (set in
`config/test.exs`) — not per-test `put_env` — so the value is stable under
`async: true`. Files are keyed by UUID, so concurrent tests never collide, and
each test cleans up the specific file it created.

- [ ] **Step 1: Point the test media root at a temp dir**

In `config/test.exs`, add (near the other `config :newton` lines):

```elixir
config :newton, :media_root, Path.join(System.tmp_dir!(), "newton_test_media")
```

This keeps all test image writes out of the repo (`priv/media` stays clean).

- [ ] **Step 2: Write the failing test**

Create `test/newton/gallery/storage_test.exs`:

```elixir
defmodule Newton.Gallery.StorageTest do
  use ExUnit.Case, async: true
  alias Newton.Gallery.Storage

  @root Application.compile_env!(:newton, :media_root)

  setup do
    File.mkdir_p!(@root)
    :ok
  end

  test "store/2 copies the file under media_root and returns a key" do
    src = Path.join(@root, "upload-#{System.unique_integer([:positive])}.tmp")
    File.write!(src, "imagedata")

    assert {:ok, key} = Storage.store(src, "photo.JPG")
    on_exit(fn -> File.rm(Path.join(@root, key)) end)

    assert String.ends_with?(key, ".jpg")
    assert File.read!(Path.join(@root, key)) == "imagedata"
    File.rm(src)
  end

  test "delete/1 removes the file and is idempotent" do
    src = Path.join(@root, "upload-#{System.unique_integer([:positive])}.tmp")
    File.write!(src, "data")
    {:ok, key} = Storage.store(src, "a.png")
    File.rm(src)

    assert :ok = Storage.delete(key)
    refute File.exists?(Path.join(@root, key))
    assert :ok = Storage.delete(key)
  end
end
```

- [ ] **Step 3: Run it to verify it fails**

Run: `mix test test/newton/gallery/storage_test.exs`
Expected: FAIL — `Newton.Gallery.Storage` does not exist.

- [ ] **Step 4: Implement Storage**

Create `lib/newton/gallery/storage.ex`:

```elixir
defmodule Newton.Gallery.Storage do
  @moduledoc "Owns image files on disk under the configured media_root."

  def store(source_path, original_filename) do
    ext = original_filename |> Path.extname() |> String.downcase()
    key = Ecto.UUID.generate() <> ext
    dest = Path.join(media_root(), key)

    with :ok <- File.mkdir_p(Path.dirname(dest)),
         :ok <- File.cp(source_path, dest) do
      {:ok, key}
    end
  end

  def delete(nil), do: :ok

  def delete(key) when is_binary(key) do
    media_root() |> Path.join(key) |> File.rm()
    :ok
  end

  defp media_root, do: Application.fetch_env!(:newton, :media_root)
end
```

- [ ] **Step 5: Run it to verify it passes**

Run: `mix test test/newton/gallery/storage_test.exs`
Expected: PASS — both tests green.

- [ ] **Step 6: Commit**

```bash
git add config/test.exs lib/newton/gallery/storage.ex test/newton/gallery/storage_test.exs
git commit -m "Add Gallery.Storage for image files on disk"
```

---

## Task 4: Gallery admin CRUD + file-aware deletes

**Files:**
- Modify: `lib/newton/gallery.ex`
- Create: `test/support/fixtures/gallery_fixtures.ex`
- Test: `test/newton/gallery_test.exs`

- [ ] **Step 1: Add a gallery fixtures module**

Create `test/support/fixtures/gallery_fixtures.ex`:

```elixir
defmodule Newton.GalleryFixtures do
  alias Newton.Gallery

  def group_fixture(attrs \\ %{}) do
    {:ok, group} =
      attrs
      |> Enum.into(%{slug: "group-#{System.unique_integer([:positive])}", title: "A Gallery"})
      |> Gallery.create_group()

    group
  end

  def photo_fixture(group, attrs \\ %{}) do
    {:ok, photo} =
      Gallery.add_photo(
        group,
        Enum.into(attrs, %{image_key: "k-#{System.unique_integer([:positive])}.jpg", alt: "", position: 0})
      )

    photo
  end
end
```

- [ ] **Step 2: Write the failing tests**

Add to `test/newton/gallery_test.exs` — first add the import at the top (after `alias Newton.Gallery`):

```elixir
  import Newton.GalleryFixtures
```

Then add these tests before the final `end`:

```elixir
  test "get_group!/1, update_group/2, change_group/2" do
    group = group_fixture(%{title: "Orig"})
    assert Gallery.get_group!(group.id).id == group.id
    {:ok, updated} = Gallery.update_group(group, %{title: "New"})
    assert updated.title == "New"
    assert %Ecto.Changeset{} = Gallery.change_group(group)
  end

  test "get_group_by_slug!/1 finds by slug" do
    group = group_fixture(%{slug: "find-me"})
    assert Gallery.get_group_by_slug!("find-me").id == group.id
  end

  test "photo get/update/change" do
    group = group_fixture()
    photo = photo_fixture(group, %{alt: "old"})
    assert Gallery.get_photo!(photo.id).id == photo.id
    {:ok, updated} = Gallery.update_photo(photo, %{alt: "new"})
    assert updated.alt == "new"
    assert %Ecto.Changeset{} = Gallery.change_photo(photo)
  end

  test "next_position/1 returns max position + 1, or 0 when empty" do
    group = group_fixture()
    assert Gallery.next_position(group) == 0
    photo_fixture(group, %{position: 5})
    assert Gallery.next_position(group) == 6
  end

  test "delete_photo/1 removes the row and the file" do
    group = group_fixture()
    key = stored_image()
    photo = photo_fixture(group, %{image_key: key})

    {:ok, _} = Gallery.delete_photo(photo)
    assert_raise Ecto.NoResultsError, fn -> Gallery.get_photo!(photo.id) end
    refute File.exists?(Path.join(media_root(), key))
  end

  test "delete_group/1 removes the group, its photos, and their files" do
    group = group_fixture()
    key = stored_image()
    photo = photo_fixture(group, %{image_key: key})

    {:ok, _} = Gallery.delete_group(group)
    assert_raise Ecto.NoResultsError, fn -> Gallery.get_group!(group.id) end
    assert_raise Ecto.NoResultsError, fn -> Gallery.get_photo!(photo.id) end
    refute File.exists?(Path.join(media_root(), key))
  end
```

Add these two private helpers at the bottom of the test module (before the final `end`). They use the constant test `media_root` from `config/test.exs` (UUID keys mean no cross-test collisions):

```elixir
  defp media_root, do: Application.fetch_env!(:newton, :media_root)

  defp stored_image do
    root = media_root()
    File.mkdir_p!(root)
    src = Path.join(root, "src-#{System.unique_integer([:positive])}.tmp")
    File.write!(src, "data")
    {:ok, key} = Newton.Gallery.Storage.store(src, "p.jpg")
    File.rm(src)
    key
  end
```

- [ ] **Step 3: Run them to verify they fail**

Run: `mix test test/newton/gallery_test.exs`
Expected: FAIL — `Gallery.get_group!/1` (and the other new functions) are undefined.

- [ ] **Step 4: Implement the context functions**

In `lib/newton/gallery.ex`, add `alias Newton.Gallery.Storage` near the top aliases, then add these functions inside the module:

```elixir
  def get_group!(id), do: Repo.get!(PhotoGroup, id) |> Repo.preload(photos: from(p in Photo, order_by: p.position))

  def get_group_by_slug!(slug),
    do: Repo.get_by!(PhotoGroup, slug: slug) |> Repo.preload(photos: from(p in Photo, order_by: p.position))

  def update_group(%PhotoGroup{} = group, attrs),
    do: group |> PhotoGroup.changeset(attrs) |> Repo.update()

  def change_group(%PhotoGroup{} = group, attrs \\ %{}), do: PhotoGroup.changeset(group, attrs)

  def delete_group(%PhotoGroup{} = group) do
    group = Repo.preload(group, :photos)
    Enum.each(group.photos, &Storage.delete(&1.image_key))
    Repo.delete(group)
  end

  def get_photo!(id), do: Repo.get!(Photo, id)

  def update_photo(%Photo{} = photo, attrs), do: photo |> Photo.changeset(attrs) |> Repo.update()

  def change_photo(%Photo{} = photo, attrs \\ %{}), do: Photo.changeset(photo, attrs)

  def delete_photo(%Photo{} = photo) do
    Storage.delete(photo.image_key)
    Repo.delete(photo)
  end

  def next_position(%PhotoGroup{id: group_id}) do
    case Repo.aggregate(from(p in Photo, where: p.photo_group_id == ^group_id), :max, :position) do
      nil -> 0
      max -> max + 1
    end
  end
```

- [ ] **Step 5: Run them to verify they pass**

Run: `mix test test/newton/gallery_test.exs`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/newton/gallery.ex test/support/fixtures/gallery_fixtures.ex test/newton/gallery_test.exs
git commit -m "Add gallery admin CRUD with file-aware deletes"
```

---

## Task 5: reorder_photos/2

**Files:**
- Modify: `lib/newton/gallery.ex`
- Test: `test/newton/gallery_test.exs`

- [ ] **Step 1: Write the failing tests**

Add to `test/newton/gallery_test.exs`:

```elixir
  test "reorder_photos/2 sets position to match the given id order" do
    group = group_fixture()
    a = photo_fixture(group, %{position: 0})
    b = photo_fixture(group, %{position: 1})
    c = photo_fixture(group, %{position: 2})

    :ok = Gallery.reorder_photos(group, [c.id, a.id, b.id])

    ordered = Gallery.get_group!(group.id).photos |> Enum.map(& &1.id)
    assert ordered == [c.id, a.id, b.id]
  end

  test "reorder_photos/2 ignores ids that belong to another gallery" do
    group = group_fixture()
    other = group_fixture()
    a = photo_fixture(group, %{position: 0})
    foreign = photo_fixture(other, %{position: 0})

    :ok = Gallery.reorder_photos(group, [foreign.id, a.id])

    assert Gallery.get_photo!(foreign.id).position == 0
    assert Gallery.get_photo!(a.id).position in 0..1
  end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `mix test test/newton/gallery_test.exs`
Expected: FAIL — `Gallery.reorder_photos/2` is undefined.

- [ ] **Step 3: Implement reorder_photos/2**

In `lib/newton/gallery.ex`, add:

```elixir
  def reorder_photos(%PhotoGroup{id: group_id}, ordered_ids) do
    valid_ids =
      Repo.all(from p in Photo, where: p.photo_group_id == ^group_id, select: p.id) |> MapSet.new()

    ordered_ids
    |> Enum.filter(&MapSet.member?(valid_ids, &1))
    |> Enum.with_index()
    |> Enum.reduce(Ecto.Multi.new(), fn {id, index}, multi ->
      Ecto.Multi.update_all(multi, {:photo, id}, from(p in Photo, where: p.id == ^id),
        set: [position: index]
      )
    end)
    |> Repo.transaction()

    :ok
  end
```

- [ ] **Step 4: Run them to verify they pass**

Run: `mix test test/newton/gallery_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/newton/gallery.ex test/newton/gallery_test.exs
git commit -m "Add Gallery.reorder_photos with a transactional position update"
```

---

## Task 6: Galleries list view + routes + nav

**Files:**
- Create: `lib/newton_web/live/admin/gallery_live/index.ex`
- Modify: `lib/newton_web/router.ex`, `lib/newton_web/components/admin/layouts.ex`
- Test: `test/newton_web/live/admin/gallery_index_live_test.exs`

- [ ] **Step 1: Write the failing test**

Create `test/newton_web/live/admin/gallery_index_live_test.exs`:

```elixir
defmodule NewtonWeb.Admin.GalleryIndexLiveTest do
  use NewtonWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Newton.AccountsFixtures
  import Newton.GalleryFixtures

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture())}
  end

  test "lists galleries", %{conn: conn} do
    group = group_fixture(%{title: "Eastern Sierra"})
    {:ok, view, _html} = live(conn, ~p"/admin/photos")
    assert has_element?(view, "#galleries-#{group.id}", "Eastern Sierra")
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/newton_web/live/admin/gallery_index_live_test.exs`
Expected: FAIL — no route for `/admin/photos`.

- [ ] **Step 3: Add routes**

In `lib/newton_web/router.ex`, inside the `live_session :admin` block after the reading routes:

```elixir
      live "/photos", GalleryLive.Index, :index
      live "/photos/new", GalleryLive.Index, :new
      live "/photos/:id/edit", GalleryLive.Index, :edit
      live "/photos/:id", GalleryLive.Show, :show
      live "/photos/:id/photo/:photo_id", GalleryLive.Show, :photo
```

- [ ] **Step 4: Activate the Photos nav link**

In `lib/newton_web/components/admin/layouts.ex`:

```elixir
  @built [:dashboard, :posts, :reading, :photos]
```

- [ ] **Step 5: Create the list LiveView**

Create `lib/newton_web/live/admin/gallery_live/index.ex`:

```elixir
defmodule NewtonWeb.Admin.GalleryLive.Index do
  use NewtonWeb, :live_view

  alias Newton.Gallery
  alias NewtonWeb.Admin.Layouts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Photos")
     |> stream(:galleries, Gallery.list_groups())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current={:photos}>
      <div class="mb-6 flex items-center justify-between">
        <h1 class="text-[1.35rem] font-semibold tracking-tight">Photos</h1>
        <.link
          patch={~p"/admin/photos/new"}
          class="rounded-md bg-(--admin-accent) px-3 py-1.5 text-[0.8rem] font-medium text-white no-underline hover:bg-(--admin-accent-hover)"
        >
          Add gallery
        </.link>
      </div>

      <div
        id="galleries"
        phx-update="stream"
        class="overflow-hidden rounded-xl border border-(--admin-border)"
      >
        <div
          id="galleries-empty"
          class="hidden p-5 text-[0.85rem] text-(--admin-text-subtle) only:block"
        >
          No galleries yet.
        </div>
        <div
          :for={{id, group} <- @streams.galleries}
          id={id}
          class="relative flex items-center gap-3 border-b border-(--admin-border) bg-(--admin-surface) px-4 py-3 last:border-b-0 hover:bg-(--admin-accent-soft)"
        >
          <div class="size-10 shrink-0 overflow-hidden rounded-md bg-(--admin-bg)">
            <img
              :if={cover = List.first(group.photos)}
              src={Gallery.image_url(cover.image_key)}
              alt=""
              class="size-full object-cover"
            />
          </div>
          <.link
            navigate={~p"/admin/photos/#{group.id}"}
            class="flex-1 text-[0.9rem] font-medium text-(--admin-text) no-underline after:absolute after:inset-0"
          >
            {group.title}
          </.link>
          <span class="text-[0.78rem] text-(--admin-text-subtle)">
            {length(group.photos)} photo{if length(group.photos) == 1, do: "", else: "s"}
          </span>
          <span class="w-24 text-right text-[0.78rem] text-(--admin-text-subtle)">
            {format_date(group.taken_on)}
          </span>
        </div>
      </div>
    </Layouts.admin>
    """
  end

  defp format_date(nil), do: "—"
  defp format_date(%Date{} = d), do: Calendar.strftime(d, "%b %-d, %Y")
end
```

- [ ] **Step 6: Run it to verify it passes**

Run: `mix test test/newton_web/live/admin/gallery_index_live_test.exs`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/newton_web/live/admin/gallery_live/index.ex lib/newton_web/router.ex lib/newton_web/components/admin/layouts.ex test/newton_web/live/admin/gallery_index_live_test.exs
git commit -m "Add the admin galleries list, routes, and nav"
```

---

## Task 7: Gallery settings drawer (create/edit/delete + slug autofill)

**Files:**
- Modify: `lib/newton_web/live/admin/gallery_live/index.ex`
- Test: `test/newton_web/live/admin/gallery_index_live_test.exs`

- [ ] **Step 1: Write the failing tests**

Add to `test/newton_web/live/admin/gallery_index_live_test.exs`:

```elixir
  test "creates a gallery and shows it in the list", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/photos/new")

    view |> form("#gallery-form", group: %{title: "New Gallery"}) |> render_submit()

    assert_patch(view, ~p"/admin/photos")
    assert has_element?(view, "#galleries", "New Gallery")
    assert Enum.any?(Gallery.list_groups(), &(&1.title == "New Gallery"))
  end

  test "slug auto-derives from the title until edited", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/photos/new")
    html = view |> form("#gallery-form", group: %{title: "Hello World", slug: ""}) |> render_change()
    assert html =~ ~s(value="hello-world")
  end

  test "edits a gallery", %{conn: conn} do
    group = group_fixture(%{title: "Old"})
    {:ok, view, _html} = live(conn, ~p"/admin/photos/#{group.id}/edit")

    view |> form("#gallery-form", group: %{title: "Renamed"}) |> render_submit()

    assert_patch(view, ~p"/admin/photos")
    assert Gallery.get_group!(group.id).title == "Renamed"
  end

  test "deletes a gallery from the drawer", %{conn: conn} do
    group = group_fixture()
    {:ok, view, _html} = live(conn, ~p"/admin/photos/#{group.id}/edit")

    view |> element("#gallery-drawer button", "Delete") |> render_click()

    assert_patch(view, ~p"/admin/photos")
    assert_raise Ecto.NoResultsError, fn -> Gallery.get_group!(group.id) end
  end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `mix test test/newton_web/live/admin/gallery_index_live_test.exs`
Expected: FAIL — `#gallery-form` / `#gallery-drawer` don't exist; `/admin/photos/new` renders the list without a drawer.

- [ ] **Step 3: Add `Newton.Gallery` and `Newton.Slug` aliases, plus drawer + handlers**

Replace the whole `lib/newton_web/live/admin/gallery_live/index.ex` with:

```elixir
defmodule NewtonWeb.Admin.GalleryLive.Index do
  use NewtonWeb, :live_view

  alias Newton.Gallery
  alias Newton.Gallery.PhotoGroup
  alias NewtonWeb.Admin.{Components, FormHelpers, Layouts}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :galleries, Gallery.list_groups())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Photos")
    |> assign(:drawer_open, false)
    |> assign(:group, nil)
    |> assign(:form, nil)
    |> assign(:slug_locked, false)
    |> assign(:slug_auto, "")
  end

  defp apply_action(socket, :new, _params) do
    group = %PhotoGroup{}

    socket
    |> assign(:page_title, "New gallery")
    |> assign(:drawer_open, true)
    |> assign(:group, group)
    |> assign(:slug_locked, false)
    |> assign(:slug_auto, "")
    |> assign(:form, to_form(Gallery.change_group(group)))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    group = Gallery.get_group!(id)

    socket
    |> assign(:page_title, "Edit gallery")
    |> assign(:drawer_open, true)
    |> assign(:group, group)
    |> assign(:slug_locked, group.slug != Newton.Slug.slugify(group.title))
    |> assign(:slug_auto, group.slug)
    |> assign(:form, to_form(Gallery.change_group(group)))
  end

  @impl true
  def handle_event("validate", %{"group" => params}, socket) do
    slug_locked = socket.assigns.slug_locked or params["slug"] != socket.assigns.slug_auto

    {params, slug_auto} =
      FormHelpers.autofill(params, "slug", slug_locked, socket.assigns.slug_auto, fn ->
        Newton.Slug.slugify(params["title"] || "")
      end)

    form =
      socket.assigns.group
      |> Gallery.change_group(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply,
     socket
     |> assign(:form, form)
     |> assign(:slug_locked, slug_locked)
     |> assign(:slug_auto, slug_auto)}
  end

  def handle_event("save", %{"group" => params}, socket) do
    save(socket, socket.assigns.group, params)
  end

  def handle_event("close_drawer", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/photos")}
  end

  def handle_event("delete", _params, socket) do
    {:ok, _} = Gallery.delete_group(socket.assigns.group)

    {:noreply,
     socket
     |> put_flash(:info, "Gallery deleted")
     |> stream(:galleries, Gallery.list_groups(), reset: true)
     |> push_patch(to: ~p"/admin/photos")}
  end

  defp save(socket, %PhotoGroup{id: nil}, params) do
    case Gallery.create_group(params) do
      {:ok, _group} ->
        {:noreply,
         socket
         |> put_flash(:info, "Gallery created")
         |> stream(:galleries, Gallery.list_groups(), reset: true)
         |> push_patch(to: ~p"/admin/photos")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save(socket, %PhotoGroup{} = group, params) do
    case Gallery.update_group(group, params) do
      {:ok, _group} ->
        {:noreply,
         socket
         |> put_flash(:info, "Gallery saved")
         |> stream(:galleries, Gallery.list_groups(), reset: true)
         |> push_patch(to: ~p"/admin/photos")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current={:photos}>
      <div class="mb-6 flex items-center justify-between">
        <h1 class="text-[1.35rem] font-semibold tracking-tight">Photos</h1>
        <.link
          patch={~p"/admin/photos/new"}
          class="rounded-md bg-(--admin-accent) px-3 py-1.5 text-[0.8rem] font-medium text-white no-underline hover:bg-(--admin-accent-hover)"
        >
          Add gallery
        </.link>
      </div>

      <div
        id="galleries"
        phx-update="stream"
        class="overflow-hidden rounded-xl border border-(--admin-border)"
      >
        <div
          id="galleries-empty"
          class="hidden p-5 text-[0.85rem] text-(--admin-text-subtle) only:block"
        >
          No galleries yet.
        </div>
        <div
          :for={{id, group} <- @streams.galleries}
          id={id}
          class="relative flex items-center gap-3 border-b border-(--admin-border) bg-(--admin-surface) px-4 py-3 last:border-b-0 hover:bg-(--admin-accent-soft)"
        >
          <div class="size-10 shrink-0 overflow-hidden rounded-md bg-(--admin-bg)">
            <img
              :if={cover = List.first(group.photos)}
              src={Gallery.image_url(cover.image_key)}
              alt=""
              class="size-full object-cover"
            />
          </div>
          <.link
            navigate={~p"/admin/photos/#{group.id}"}
            class="flex-1 text-[0.9rem] font-medium text-(--admin-text) no-underline after:absolute after:inset-0"
          >
            {group.title}
          </.link>
          <span class="text-[0.78rem] text-(--admin-text-subtle)">
            {length(group.photos)} photo{if length(group.photos) == 1, do: "", else: "s"}
          </span>
          <span class="w-24 text-right text-[0.78rem] text-(--admin-text-subtle)">
            {format_date(group.taken_on)}
          </span>
        </div>
      </div>

      <Components.drawer :if={@drawer_open} id="gallery-drawer" on_close="close_drawer">
        <:title>{if @group.id, do: "Edit gallery", else: "New gallery"}</:title>

        <.form
          for={@form}
          id="gallery-form"
          phx-change="validate"
          phx-submit="save"
          class="flex flex-col gap-3"
        >
          <Components.field field={@form[:title]} label="Title" />
          <Components.field field={@form[:slug]} label="Slug" />
          <Components.field field={@form[:caption]} type="textarea" label="Caption" rows="2" />
          <Components.field field={@form[:taken_on]} type="date" label="Taken on" />

          <div class="mt-2 flex items-center gap-2">
            <button
              :if={@group.id}
              type="button"
              phx-click="delete"
              data-confirm="Delete this gallery and all its photos?"
              class="rounded-md border border-(--admin-border) px-3 py-1.5 text-[0.78rem] text-(--admin-accent) hover:bg-(--admin-accent-soft)"
            >
              Delete
            </button>
            <div class="flex-1"></div>
            <.link
              patch={~p"/admin/photos"}
              class="rounded-md px-3 py-1.5 text-[0.78rem] text-(--admin-text-muted) no-underline hover:text-(--admin-text)"
            >
              Cancel
            </.link>
            <button
              type="submit"
              class="rounded-md bg-(--admin-accent) px-3 py-1.5 text-[0.78rem] font-medium text-white hover:bg-(--admin-accent-hover)"
            >
              Save
            </button>
          </div>
        </.form>
      </Components.drawer>
    </Layouts.admin>
    """
  end

  defp format_date(nil), do: "—"
  defp format_date(%Date{} = d), do: Calendar.strftime(d, "%b %-d, %Y")
end
```

- [ ] **Step 4: Run them to verify they pass**

Run: `mix test test/newton_web/live/admin/gallery_index_live_test.exs`
Expected: PASS — all five Index tests green.

- [ ] **Step 5: Commit**

```bash
git add lib/newton_web/live/admin/gallery_live/index.ex test/newton_web/live/admin/gallery_index_live_test.exs
git commit -m "Add the gallery settings drawer with slug autofill"
```

---

## Task 8: Gallery Show skeleton (header + photo grid + needs-alt badge)

**Files:**
- Create: `lib/newton_web/live/admin/gallery_live/show.ex`
- Test: `test/newton_web/live/admin/gallery_show_live_test.exs`

- [ ] **Step 1: Write the failing tests**

Create `test/newton_web/live/admin/gallery_show_live_test.exs`:

```elixir
defmodule NewtonWeb.Admin.GalleryShowLiveTest do
  use NewtonWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Newton.AccountsFixtures
  import Newton.GalleryFixtures

  alias Newton.Gallery

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture())}
  end

  test "shows the gallery title and its photos", %{conn: conn} do
    group = group_fixture(%{title: "Trip"})
    photo = photo_fixture(group, %{alt: "A boat"})

    {:ok, view, _html} = live(conn, ~p"/admin/photos/#{group.id}")

    assert has_element?(view, "h1", "Trip")
    assert has_element?(view, "#photo-#{photo.id}")
  end

  test "flags photos that are missing alt text", %{conn: conn} do
    group = group_fixture()
    blank = photo_fixture(group, %{alt: ""})
    described = photo_fixture(group, %{alt: "Described"})

    {:ok, view, _html} = live(conn, ~p"/admin/photos/#{group.id}")

    assert has_element?(view, "#photo-#{blank.id} [data-role=needs-alt]")
    refute has_element?(view, "#photo-#{described.id} [data-role=needs-alt]")
  end
end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `mix test test/newton_web/live/admin/gallery_show_live_test.exs`
Expected: FAIL — `GalleryLive.Show` is undefined (route points at a missing module).

- [ ] **Step 3: Create the Show LiveView**

Create `lib/newton_web/live/admin/gallery_live/show.ex`:

```elixir
defmodule NewtonWeb.Admin.GalleryLive.Show do
  use NewtonWeb, :live_view

  alias Newton.Gallery
  alias NewtonWeb.Admin.Layouts

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    group = Gallery.get_group!(id)

    {:ok,
     socket
     |> assign(:page_title, group.title)
     |> assign(:group, group)
     |> stream(:photos, group.photos, dom_id: &"photo-#{&1.id}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current={:photos}>
      <div class="mb-4 flex items-center gap-3">
        <.link
          navigate={~p"/admin/photos"}
          class="text-[0.8rem] text-(--admin-text-subtle) no-underline hover:text-(--admin-text)"
        >
          ← Photos
        </.link>
        <h1 class="text-[1.35rem] font-semibold tracking-tight">{@group.title}</h1>
        <div class="flex-1"></div>
        <.link
          patch={~p"/admin/photos/#{@group.id}/edit"}
          class="rounded-md border border-(--admin-border) px-3 py-1.5 text-[0.8rem] text-(--admin-text) no-underline hover:bg-(--admin-accent-soft)"
        >
          Settings
        </.link>
      </div>

      <div
        id="photos"
        phx-update="stream"
        class="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4"
      >
        <div
          id="photos-empty"
          class="col-span-full hidden rounded-xl border border-dashed border-(--admin-border) p-8 text-center text-[0.85rem] text-(--admin-text-subtle) only:block"
        >
          No photos yet — drag images here to start.
        </div>
        <div
          :for={{id, photo} <- @streams.photos}
          id={id}
          class="group relative aspect-square overflow-hidden rounded-lg border border-(--admin-border) bg-(--admin-bg)"
        >
          <img src={Gallery.image_url(photo.image_key)} alt={photo.alt} class="size-full object-cover" />
          <span
            :if={photo.alt == ""}
            data-role="needs-alt"
            class="absolute left-1.5 top-1.5 rounded bg-(--admin-accent) px-1.5 py-0.5 text-[0.65rem] font-medium text-white"
          >
            needs alt
          </span>
        </div>
      </div>
    </Layouts.admin>
    """
  end
end
```

The `dom_id: &"photo-#{&1.id}"` on the stream makes each tile's DOM id read
`photo-<id>` (the default would be `photos-<id>`), matching the tests.

- [ ] **Step 4: Run them to verify they pass**

Run: `mix test test/newton_web/live/admin/gallery_show_live_test.exs`
Expected: PASS — both tests green.

- [ ] **Step 5: Commit**

```bash
git add lib/newton_web/live/admin/gallery_live/show.ex test/newton_web/live/admin/gallery_show_live_test.exs
git commit -m "Add the in-gallery photo grid with a needs-alt badge"
```

---

## Task 9: Photo upload (allow_upload + dimension capture + consume)

**Files:**
- Modify: `lib/newton_web/live/admin/gallery_live/show.ex`
- Create: `assets/js/hooks/image_dimensions.js`
- Modify: `assets/js/admin.js`
- Test: `test/newton_web/live/admin/gallery_show_live_test.exs`

Dimensions are reported by a JS hook keyed by filename and stored in a
`:dimensions` assign; `consume_uploaded_entries` looks them up by
`entry.client_name`. In tests, the hook doesn't run, so the test pushes the
`"set_dimensions"` event directly.

- [ ] **Step 1: Write the failing test**

Add to `test/newton_web/live/admin/gallery_show_live_test.exs`:

```elixir
  test "uploading a photo adds it to the gallery with captured dimensions", %{conn: conn} do
    group = group_fixture()
    {:ok, view, _html} = live(conn, ~p"/admin/photos/#{group.id}")

    photo =
      file_input(view, "#upload-form", :photos, [
        %{name: "shot.jpg", content: "fakeimage", type: "image/jpeg"}
      ])

    render_hook(view, "set_dimensions", %{"name" => "shot.jpg", "width" => 1200, "height" => 800})
    render_upload(photo, "shot.jpg")
    view |> element("#upload-form") |> render_submit()

    [created] = Gallery.get_group!(group.id).photos
    assert created.width == 1200
    assert created.height == 800
    assert has_element?(view, "#photo-#{created.id}")
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/newton_web/live/admin/gallery_show_live_test.exs`
Expected: FAIL — there is no `#upload-form` / `:photos` upload.

- [ ] **Step 3: Add the upload to the LiveView**

In `lib/newton_web/live/admin/gallery_live/show.ex`, update `mount/3` to allow uploads and seed `:dimensions`:

```elixir
  @impl true
  def mount(%{"id" => id}, _session, socket) do
    group = Gallery.get_group!(id)

    {:ok,
     socket
     |> assign(:page_title, group.title)
     |> assign(:group, group)
     |> assign(:dimensions, %{})
     |> stream(:photos, group.photos, dom_id: &"photo-#{&1.id}")
     |> allow_upload(:photos,
       accept: ~w(.jpg .jpeg .png .webp),
       max_entries: 20,
       max_file_size: 50_000_000
     )}
  end
```

Add `alias Newton.Gallery.Storage` to the module's alias lines (alongside the existing `alias Newton.Gallery`).

Add the event handlers (place after `mount/3`, before `render/1`):

```elixir
  @impl true
  def handle_event("set_dimensions", %{"name" => name, "width" => w, "height" => h}, socket) do
    {:noreply, update(socket, :dimensions, &Map.put(&1, name, {w, h}))}
  end

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :photos, ref)}
  end

  def handle_event("save_upload", _params, socket) do
    group = socket.assigns.group
    dimensions = socket.assigns.dimensions
    base = Gallery.next_position(group)

    uploaded =
      consume_uploaded_entries(socket, :photos, fn %{path: path}, entry ->
        {:ok, key} = Storage.store(path, entry.client_name)
        {w, h} = Map.get(dimensions, entry.client_name, {nil, nil})
        {:ok, {key, w, h}}
      end)

    photos =
      uploaded
      |> Enum.with_index(base)
      |> Enum.map(fn {{key, w, h}, position} ->
        {:ok, photo} =
          Gallery.add_photo(group, %{image_key: key, alt: "", position: position, width: w, height: h})

        photo
      end)

    {:noreply, stream(socket, :photos, photos, at: -1)}
  end
```

Add the upload form + dropzone to `render/1`, immediately before the `#photos` grid div:

```elixir
      <form
        id="upload-form"
        phx-submit="save_upload"
        phx-change="validate"
        phx-hook="ImageDimensions"
        class="mb-5"
      >
        <label
          class="flex cursor-pointer flex-col items-center justify-center rounded-xl border border-dashed border-(--admin-border) bg-(--admin-surface) px-6 py-8 text-center text-[0.85rem] text-(--admin-text-subtle) hover:border-(--admin-border-strong)"
          phx-drop-target={@uploads.photos.ref}
        >
          <.icon name="hero-arrow-up-tray" class="mb-2 size-6 text-(--admin-text-muted)" />
          Drag images here, or click to choose
          <.live_file_input upload={@uploads.photos} class="sr-only" />
        </label>

        <div :for={entry <- @uploads.photos.entries} class="mt-3 flex items-center gap-3 text-[0.8rem]">
          <span class="flex-1 truncate text-(--admin-text)">{entry.client_name}</span>
          <div class="h-1.5 w-32 overflow-hidden rounded-full bg-(--admin-bg)">
            <div class="h-full bg-(--admin-accent)" style={"width: #{entry.progress}%"}></div>
          </div>
          <button
            type="button"
            phx-click="cancel_upload"
            phx-value-ref={entry.ref}
            aria-label="Cancel"
            class="text-(--admin-text-subtle) hover:text-(--admin-accent)"
          >
            <.icon name="hero-x-mark-mini" class="size-4" />
          </button>
        </div>

        <p :for={err <- upload_errors(@uploads.photos)} class="mt-1 text-[0.78rem] text-(--admin-accent)">
          {upload_error_to_string(err)}
        </p>

        <button
          :if={@uploads.photos.entries != []}
          type="submit"
          class="mt-3 rounded-md bg-(--admin-accent) px-3 py-1.5 text-[0.8rem] font-medium text-white hover:bg-(--admin-accent-hover)"
        >
          Upload {length(@uploads.photos.entries)} photo{if length(@uploads.photos.entries) == 1, do: "", else: "s"}
        </button>
      </form>
```

Add the error-string helper at the bottom of the module:

```elixir
  defp upload_error_to_string(:too_large), do: "File is too large (max 50MB)."
  defp upload_error_to_string(:too_many_files), do: "Too many files (max 20)."
  defp upload_error_to_string(:not_accepted), do: "That file type isn't allowed."
  defp upload_error_to_string(_), do: "Upload error."
```

- [ ] **Step 4: Create the dimension hook**

Create `assets/js/hooks/image_dimensions.js`:

```javascript
// Reads each picked image's natural width/height in the browser and pushes them
// to the server keyed by filename, so dimensions are known when the upload is
// consumed. Listens on the file input inside the upload form.
export const ImageDimensions = {
  mounted() {
    this.el.addEventListener("input", (e) => {
      if (e.target.type !== "file") return
      for (const file of e.target.files) {
        const url = URL.createObjectURL(file)
        const img = new Image()
        img.onload = () => {
          this.pushEvent("set_dimensions", {
            name: file.name,
            width: img.naturalWidth,
            height: img.naturalHeight,
          })
          URL.revokeObjectURL(url)
        }
        img.src = url
      }
    })
  },
}
```

- [ ] **Step 5: Register the hook**

In `assets/js/admin.js`, add the import and register it:

```javascript
import {ImageDimensions} from "./hooks/image_dimensions"
```

and add `ImageDimensions` to the hooks object:

```javascript
  hooks: {...colocatedHooks, AdminTheme, MarkdownEditor, ImageDimensions},
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `mix test test/newton_web/live/admin/gallery_show_live_test.exs`
Expected: PASS — the upload test creates a photo with width 1200, height 800.

- [ ] **Step 7: Commit**

```bash
git add lib/newton_web/live/admin/gallery_live/show.ex assets/js/hooks/image_dimensions.js assets/js/admin.js test/newton_web/live/admin/gallery_show_live_test.exs
git commit -m "Add drag-drop photo upload with client-side dimension capture"
```

---

## Task 10: Per-photo drawer (alt edit + delete)

**Files:**
- Modify: `lib/newton_web/live/admin/gallery_live/show.ex`
- Test: `test/newton_web/live/admin/gallery_show_live_test.exs`

- [ ] **Step 1: Write the failing tests**

Add to `test/newton_web/live/admin/gallery_show_live_test.exs`:

```elixir
  test "editing alt text clears the needs-alt badge", %{conn: conn} do
    group = group_fixture()
    photo = photo_fixture(group, %{alt: ""})
    {:ok, view, _html} = live(conn, ~p"/admin/photos/#{group.id}/photo/#{photo.id}")

    view |> form("#photo-form", photo: %{alt: "A described photo"}) |> render_submit()

    assert_patch(view, ~p"/admin/photos/#{group.id}")
    assert Gallery.get_photo!(photo.id).alt == "A described photo"
    refute has_element?(view, "#photo-#{photo.id} [data-role=needs-alt]")
  end

  test "deleting a photo removes it from the grid", %{conn: conn} do
    group = group_fixture()
    photo = photo_fixture(group, %{alt: "x"})
    {:ok, view, _html} = live(conn, ~p"/admin/photos/#{group.id}/photo/#{photo.id}")

    view |> element("#photo-drawer button", "Delete") |> render_click()

    assert_patch(view, ~p"/admin/photos/#{group.id}")
    assert_raise Ecto.NoResultsError, fn -> Gallery.get_photo!(photo.id) end
    refute has_element?(view, "#photo-#{photo.id}")
  end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `mix test test/newton_web/live/admin/gallery_show_live_test.exs`
Expected: FAIL — the `:photo` action and `#photo-drawer` / `#photo-form` don't exist.

- [ ] **Step 3: Add handle_params + drawer handlers**

In `lib/newton_web/live/admin/gallery_live/show.ex`, add `Components` to the alias line:

```elixir
  alias NewtonWeb.Admin.{Components, Layouts}
```

Add `handle_params/3` and `apply_action/3` (after `mount/3`):

```elixir
  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :show, _params) do
    socket
    |> assign(:editing_photo, nil)
    |> assign(:photo_form, nil)
  end

  defp apply_action(socket, :photo, %{"photo_id" => photo_id}) do
    photo = Gallery.get_photo!(photo_id)

    socket
    |> assign(:editing_photo, photo)
    |> assign(:photo_form, to_form(Gallery.change_photo(photo)))
  end
```

Add the alt-edit + delete + close handlers (with the other `handle_event`s):

```elixir
  def handle_event("validate_photo", %{"photo" => params}, socket) do
    form =
      socket.assigns.editing_photo
      |> Gallery.change_photo(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :photo_form, form)}
  end

  def handle_event("save_photo", %{"photo" => params}, socket) do
    {:ok, photo} = Gallery.update_photo(socket.assigns.editing_photo, params)

    {:noreply,
     socket
     |> stream_insert(:photos, photo)
     |> push_patch(to: ~p"/admin/photos/#{socket.assigns.group.id}")}
  end

  def handle_event("close_photo", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/photos/#{socket.assigns.group.id}")}
  end

  def handle_event("delete_photo", _params, socket) do
    photo = socket.assigns.editing_photo
    {:ok, _} = Gallery.delete_photo(photo)

    {:noreply,
     socket
     |> stream_delete(:photos, photo)
     |> push_patch(to: ~p"/admin/photos/#{socket.assigns.group.id}")}
  end
```

Make each photo tile open the drawer — wrap the tile's content in a patch link. Replace the tile `<img>`/badge block inside the `:for` with a clickable version:

```elixir
        <div
          :for={{id, photo} <- @streams.photos}
          id={id}
          class="group relative aspect-square overflow-hidden rounded-lg border border-(--admin-border) bg-(--admin-bg)"
        >
          <.link patch={~p"/admin/photos/#{@group.id}/photo/#{photo.id}"} class="block size-full">
            <img src={Gallery.image_url(photo.image_key)} alt={photo.alt} class="size-full object-cover" />
          </.link>
          <span
            :if={photo.alt == ""}
            data-role="needs-alt"
            class="pointer-events-none absolute left-1.5 top-1.5 rounded bg-(--admin-accent) px-1.5 py-0.5 text-[0.65rem] font-medium text-white"
          >
            needs alt
          </span>
        </div>
```

Add the drawer at the end of the template (before `</Layouts.admin>`):

```elixir
      <Components.drawer :if={@editing_photo} id="photo-drawer" on_close="close_photo">
        <:title>Photo</:title>

        <img
          src={Gallery.image_url(@editing_photo.image_key)}
          alt={@editing_photo.alt}
          class="aspect-square w-full rounded-lg object-cover"
        />

        <.form
          for={@photo_form}
          id="photo-form"
          phx-change="validate_photo"
          phx-submit="save_photo"
          class="flex flex-col gap-3"
        >
          <Components.field field={@photo_form[:alt]} type="textarea" label="Alt text" rows="2" />

          <div class="mt-2 flex items-center gap-2">
            <button
              type="button"
              phx-click="delete_photo"
              data-confirm="Delete this photo?"
              class="rounded-md border border-(--admin-border) px-3 py-1.5 text-[0.78rem] text-(--admin-accent) hover:bg-(--admin-accent-soft)"
            >
              Delete
            </button>
            <div class="flex-1"></div>
            <button
              type="submit"
              class="rounded-md bg-(--admin-accent) px-3 py-1.5 text-[0.78rem] font-medium text-white hover:bg-(--admin-accent-hover)"
            >
              Save
            </button>
          </div>
        </.form>
      </Components.drawer>
```

- [ ] **Step 4: Run them to verify they pass**

Run: `mix test test/newton_web/live/admin/gallery_show_live_test.exs`
Expected: PASS — alt edit clears the badge; delete removes the tile.

- [ ] **Step 5: Commit**

```bash
git add lib/newton_web/live/admin/gallery_live/show.ex test/newton_web/live/admin/gallery_show_live_test.exs
git commit -m "Add the per-photo drawer for alt text and delete"
```

---

## Task 11: Drag-to-reorder

**Files:**
- Modify: `lib/newton_web/live/admin/gallery_live/show.ex`
- Create: `assets/js/hooks/sortable_grid.js`
- Modify: `assets/js/admin.js`
- Test: `test/newton_web/live/admin/gallery_show_live_test.exs`

The grid is a sortable hook; on drop it pushes the ordered photo-id list to a
`"reorder"` handler. The test exercises the server handler directly via
`render_hook`.

- [ ] **Step 1: Write the failing test**

Add to `test/newton_web/live/admin/gallery_show_live_test.exs`:

```elixir
  test "reorder event persists the new photo order", %{conn: conn} do
    group = group_fixture()
    a = photo_fixture(group, %{position: 0})
    b = photo_fixture(group, %{position: 1})
    {:ok, view, _html} = live(conn, ~p"/admin/photos/#{group.id}")

    render_hook(view, "reorder", %{"ids" => ["#{b.id}", "#{a.id}"]})

    ordered = Gallery.get_group!(group.id).photos |> Enum.map(& &1.id)
    assert ordered == [b.id, a.id]
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/newton_web/live/admin/gallery_show_live_test.exs`
Expected: FAIL — no `"reorder"` handler.

- [ ] **Step 3: Add the reorder handler**

In `lib/newton_web/live/admin/gallery_live/show.ex`, add:

```elixir
  def handle_event("reorder", %{"ids" => ids}, socket) do
    ordered_ids = Enum.map(ids, &String.to_integer/1)
    :ok = Gallery.reorder_photos(socket.assigns.group, ordered_ids)
    {:noreply, socket}
  end
```

- [ ] **Step 4: Run it to verify it passes**

Run: `mix test test/newton_web/live/admin/gallery_show_live_test.exs`
Expected: PASS — order persists as `[b, a]`.

- [ ] **Step 5: Add the sortable hook + wire it to the grid**

Create `assets/js/hooks/sortable_grid.js`:

```javascript
// Minimal HTML5 drag-and-drop reordering for the photo grid. On drop it reads
// the new child order and pushes the photo-id list to the server. Reorders the
// DOM optimistically; the server persists positions. No external library.
export const SortableGrid = {
  mounted() {
    this.dragEl = null

    this.el.addEventListener("dragstart", (e) => {
      this.dragEl = e.target.closest("[data-id]")
      if (this.dragEl) e.dataTransfer.effectAllowed = "move"
    })

    this.el.addEventListener("dragover", (e) => {
      e.preventDefault()
      const over = e.target.closest("[data-id]")
      if (!over || over === this.dragEl || !this.dragEl) return
      const rect = over.getBoundingClientRect()
      const after = (e.clientX - rect.left) / rect.width > 0.5
      this.el.insertBefore(this.dragEl, after ? over.nextSibling : over)
    })

    this.el.addEventListener("drop", (e) => {
      e.preventDefault()
      this.dragEl = null
      const ids = [...this.el.querySelectorAll("[data-id]")].map((el) => el.dataset.id)
      this.pushEvent("reorder", {ids})
    })
  },
}
```

In `lib/newton_web/live/admin/gallery_live/show.ex`, add `phx-hook` + `phx-update="stream"` stays, and give each tile `draggable` + `data-id`. Update the grid container and tile:

Grid container — add the hook (keep the existing classes and `phx-update="stream"`):

```elixir
      <div
        id="photos"
        phx-hook="SortableGrid"
        phx-update="stream"
        class="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4"
      >
```

Tile — add `draggable="true"` and `data-id={photo.id}`:

```elixir
        <div
          :for={{id, photo} <- @streams.photos}
          id={id}
          draggable="true"
          data-id={photo.id}
          class="group relative aspect-square cursor-grab overflow-hidden rounded-lg border border-(--admin-border) bg-(--admin-bg) active:cursor-grabbing"
        >
```

Note: the photo's open-drawer link must not swallow drags — keep the `<.link>` as-is; HTML5 drag on the parent still fires. (`draggable` on the tile, link click still works.)

- [ ] **Step 6: Register the hook**

In `assets/js/admin.js`:

```javascript
import {SortableGrid} from "./hooks/sortable_grid"
```

and add `SortableGrid` to the hooks object:

```javascript
  hooks: {...colocatedHooks, AdminTheme, MarkdownEditor, ImageDimensions, SortableGrid},
```

- [ ] **Step 7: Run the Show tests to confirm green**

Run: `mix test test/newton_web/live/admin/gallery_show_live_test.exs`
Expected: PASS — all Show tests still green.

- [ ] **Step 8: Commit**

```bash
git add lib/newton_web/live/admin/gallery_live/show.ex assets/js/hooks/sortable_grid.js assets/js/admin.js test/newton_web/live/admin/gallery_show_live_test.exs
git commit -m "Add drag-to-reorder for the photo grid"
```

---

## Task 12: JS hook unit tests

**Files:**
- Create: `assets/js/hooks/image_dimensions.test.js`
- Create: `assets/js/hooks/sortable_grid.test.js`

Follow the existing Vitest style (`assets/js/hooks/admin_theme.test.js`).

- [ ] **Step 1: Write the dimension hook test**

Create `assets/js/hooks/image_dimensions.test.js`:

```javascript
import {describe, it, expect, vi, beforeEach} from "vitest"
import {ImageDimensions} from "./image_dimensions"

describe("ImageDimensions", () => {
  beforeEach(() => {
    global.URL.createObjectURL = vi.fn(() => "blob:x")
    global.URL.revokeObjectURL = vi.fn()
    // Make Image load synchronously with fixed natural dimensions.
    global.Image = class {
      set src(_v) {
        this.naturalWidth = 640
        this.naturalHeight = 480
        this.onload()
      }
    }
  })

  it("pushes width/height for each picked file", () => {
    const input = document.createElement("input")
    input.type = "file"
    const pushEvent = vi.fn()
    const hook = {el: input, pushEvent}
    Object.setPrototypeOf(hook, ImageDimensions)
    hook.mounted()

    const file = new File(["x"], "shot.jpg", {type: "image/jpeg"})
    Object.defineProperty(input, "files", {value: [file]})
    input.dispatchEvent(new Event("input", {bubbles: true}))

    expect(pushEvent).toHaveBeenCalledWith("set_dimensions", {
      name: "shot.jpg",
      width: 640,
      height: 480,
    })
  })
})
```

- [ ] **Step 2: Write the sortable hook test**

Create `assets/js/hooks/sortable_grid.test.js`:

```javascript
import {describe, it, expect, vi} from "vitest"
import {SortableGrid} from "./sortable_grid"

function tile(id) {
  const el = document.createElement("div")
  el.dataset.id = id
  return el
}

describe("SortableGrid", () => {
  it("pushes the current child id order on drop", () => {
    const grid = document.createElement("div")
    grid.append(tile("1"), tile("2"), tile("3"))
    const pushEvent = vi.fn()
    const hook = {el: grid, pushEvent}
    Object.setPrototypeOf(hook, SortableGrid)
    hook.mounted()

    const drop = new Event("drop", {bubbles: true})
    drop.preventDefault = () => {}
    grid.dispatchEvent(drop)

    expect(pushEvent).toHaveBeenCalledWith("reorder", {ids: ["1", "2", "3"]})
  })
})
```

- [ ] **Step 3: Run the JS tests**

Run (from `assets/`): `pnpm test`
Expected: PASS — new tests green alongside the existing suite.

- [ ] **Step 4: Commit**

```bash
git add assets/js/hooks/image_dimensions.test.js assets/js/hooks/sortable_grid.test.js
git commit -m "Add unit tests for the image-dimensions and sortable-grid hooks"
```

---

## Task 13: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full precommit suite**

Run: `mix precommit`
Expected: PASS — compiles `--warnings-as-errors`, formatted, Credo `--strict` clean, both test suites green, Dialyzer 0 errors. Fix anything reported.

- [ ] **Step 2: Visual smoke check (dev server already running)**

Run (from `assets/`): `node screenshot.mjs /admin/photos=galleries /admin/photos/new=gallery-drawer`
Then open a gallery in the browser, upload a couple of images, confirm: thumbnails appear, "needs alt" badges show, clicking a tile opens the photo drawer, editing alt clears the badge, dragging reorders, and deleting removes the tile. Confirm the uploaded photos appear on the public `/photos` page.

---

## Self-review notes

- **Spec coverage:** schema blank-alt (Task 2); `Storage` (Task 3); context CRUD + file-aware deletes (Task 4); `reorder_photos` (Task 5); galleries list + routes + nav (Task 6); settings drawer with slug autofill (Task 7); Show grid + needs-alt badge (Task 8); upload + client dimensions (Task 9); photo drawer alt+delete (Task 10); drag-reorder (Task 11); JS unit tests (Task 12); verification (Task 13). The slug-helper extraction (Task 1) satisfies the spec's "extract into a shared helper" and lands it in `NewtonWeb.Admin.FormHelpers`.
- **Names/types consistent across tasks:** `Gallery.{get_group!/1, get_group_by_slug!/1, update_group/2, change_group/2, delete_group/1, get_photo!/1, update_photo/2, change_photo/2, delete_photo/1, next_position/1, reorder_photos/2}`; `Storage.{store/2, delete/1}`; events `set_dimensions`, `save_upload`, `cancel_upload`, `reorder`, `validate_photo`, `save_photo`, `delete_photo`, `close_photo`; DOM ids `#galleries`, `#gallery-drawer`, `#gallery-form`, `#photos`, `#photo-<id>`, `#upload-form`, `#photo-drawer`, `#photo-form`; hooks `ImageDimensions`, `SortableGrid`; the photo stream uses `dom_id: &"photo-#{&1.id}"` so `#photo-<id>` is consistent in template and tests.
- **Decisions honored:** client-side dimensions (Task 9), drag-reorder (Task 11), photo drawer = alt+delete only (Task 10), 50MB max (Task 9), no native image lib, no migration.
- **Out of scope (per spec):** in-place image replacement, server-side processing, gallery reordering.
