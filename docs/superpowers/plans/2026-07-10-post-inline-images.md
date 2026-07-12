# Post Inline Images Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Track inline post images in a `post_images` ledger so they follow the post's lifecycle, are visible in the admin editor, and existing untracked files can be adopted.

**Architecture:** A small `post_images` table owned by `Newton.Blog` (upload-origin ownership: an image belongs to the post whose editor uploaded it). Usage ("referenced?") is never stored — it is computed live from `post.body_markdown`. The editor's upload handler attaches images at upload time; `delete_post` removes owned files; an Images section in the editor provides manual cleanup of unreferenced images; a backfill module adopts pre-existing files.

**Tech Stack:** Phoenix 1.8 + LiveView, Ecto (SQLite/Postgres-agnostic migration), existing `Newton.Gallery.Storage` for file IO. No JS changes.

**Spec:** `docs/superpowers/specs/2026-07-09-post-inline-images-design.md`

## Global Constraints

- **COMMIT HOLD:** James has instructed that nothing be committed until he says otherwise. Leave every "Commit" step unchecked and do not run `git commit`; the steps stay in the plan so they can be executed when the hold lifts.
- **No narrating comments** (AGENTS.md): no comments that restate code or justify choices. Comments only for constraints the code cannot express.
- **`@spec` on every public function in the domain layer** (`lib/newton/**`), matching the existing style in `lib/newton/blog.ex`.
- The post body field is **`body_markdown`** — there is no `body` field.
- Tests assert behaviors, not markup structure. Reference elements by DOM id.
- Test media root is `Path.join(System.tmp_dir!(), "newton_test_media")` (already configured in `config/test.exs`).
- Run tests with `mix test <file>`; finish the whole plan with `mix precommit`.

## File Structure

| File | Responsibility |
|---|---|
| `priv/repo/migrations/<ts>_create_post_images.exs` | the ledger table |
| `lib/newton/blog/post_image.ex` | schema + creation changeset |
| `lib/newton/blog.ex` | attach/list/referenced?/delete functions; delete_post file cleanup |
| `lib/newton/blog/post.ex` | `has_many :images` |
| `lib/newton/blog/image_backfill.ex` | adopt/audit core (pure, testable) |
| `lib/mix/tasks/newton.post_images.backfill.ex` | thin mix-task shell that prints the report |
| `lib/newton_web/live/admin/post_live/editor.ex` | attach on upload; draft-on-first-upload; Images section + delete event |
| `test/newton/blog/post_images_test.exs` | ledger + lifecycle context tests |
| `test/newton/blog/image_backfill_test.exs` | backfill tests |
| `test/newton_web/live/admin/post_editor_live_test.exs` | upload/attach + Images-section tests (extend existing file) |

---

### Task 1: Ledger — migration, schema, attach/list/referenced?

**Files:**
- Create: `priv/repo/migrations/<ts>_create_post_images.exs` (via `mix ecto.gen.migration`)
- Create: `lib/newton/blog/post_image.ex`
- Modify: `lib/newton/blog.ex` (new functions + aliases)
- Modify: `lib/newton/blog/post.ex` (`has_many`)
- Test: `test/newton/blog/post_images_test.exs`

**Interfaces:**
- Consumes: `Newton.Blog.create_post/1` (exists), `Newton.Repo`.
- Produces: `Blog.attach_image(post, key, original_filename \\ nil)` → `{:ok, %PostImage{}} | {:error, Ecto.Changeset.t()}`; `Blog.list_images(post)` → `[%PostImage{}]` ordered by insertion; `Blog.image_referenced?(post, image)` → `boolean`; `%Newton.Blog.PostImage{id, post_id, key, original_filename}`.

- [ ] **Step 1: Write the failing tests**

Create `test/newton/blog/post_images_test.exs`:

```elixir
defmodule Newton.Blog.PostImagesTest do
  use Newton.DataCase
  alias Newton.Blog

  defp post_fixture(attrs \\ %{}) do
    {:ok, post} =
      attrs
      |> Enum.into(%{
        slug: "post-#{System.unique_integer([:positive])}",
        title: "A Post",
        body_markdown: "Some text."
      })
      |> Blog.create_post()

    post
  end

  test "attach_image records an upload against its post" do
    post = post_fixture()

    assert {:ok, image} = Blog.attach_image(post, "abc123.png", "shot.png")
    assert image.post_id == post.id
    assert image.original_filename == "shot.png"
    assert [%{key: "abc123.png"}] = Blog.list_images(post)
  end

  test "a key can only be attached once" do
    post = post_fixture()
    {:ok, _} = Blog.attach_image(post, "dup.png", "a.png")

    assert {:error, changeset} = Blog.attach_image(post, "dup.png", "b.png")
    assert %{key: ["has already been taken"]} = errors_on(changeset)
  end

  test "list_images returns only the post's images, oldest first" do
    post = post_fixture()
    other = post_fixture()
    {:ok, first} = Blog.attach_image(post, "one.png", nil)
    {:ok, second} = Blog.attach_image(post, "two.png", nil)
    {:ok, _} = Blog.attach_image(other, "three.png", nil)

    assert [^first, ^second] = Blog.list_images(post)
  end

  test "image_referenced? reflects whether the body still uses the key" do
    post = post_fixture(%{body_markdown: "Intro\n\n![](/media/used.png)\n"})
    {:ok, used} = Blog.attach_image(post, "used.png", nil)
    {:ok, unused} = Blog.attach_image(post, "unused.png", nil)

    assert Blog.image_referenced?(post, used)
    refute Blog.image_referenced?(post, unused)
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/newton/blog/post_images_test.exs`
Expected: FAIL — `Blog.attach_image/3 is undefined`.

- [ ] **Step 3: Generate the migration**

Run: `mix ecto.gen.migration create_post_images`

Fill the generated file:

```elixir
defmodule Newton.Repo.Migrations.CreatePostImages do
  use Ecto.Migration

  def change do
    create table(:post_images) do
      add :post_id, references(:posts, on_delete: :delete_all), null: false
      add :key, :string, null: false
      add :original_filename, :string

      timestamps(type: :utc_datetime)
    end

    create index(:post_images, [:post_id])
    create unique_index(:post_images, [:key])
  end
end
```

Run: `mix ecto.migrate`

- [ ] **Step 4: Write the schema**

Create `lib/newton/blog/post_image.ex`:

```elixir
defmodule Newton.Blog.PostImage do
  use Ecto.Schema
  import Ecto.Changeset
  alias Newton.Blog.Post

  schema "post_images" do
    field :key, :string
    field :original_filename, :string

    belongs_to :post, Post
    timestamps(type: :utc_datetime)
  end

  @doc "Creation changeset for the upload flow; post_id is set on the struct, never cast."
  @spec create_changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def create_changeset(image, attrs) do
    image
    |> cast(attrs, [:key, :original_filename])
    |> validate_required([:post_id, :key])
    |> unique_constraint(:key)
    |> foreign_key_constraint(:post_id)
  end
end
```

Add to the schema block in `lib/newton/blog/post.ex` (after the `field` lines, before `timestamps`):

```elixir
    has_many :images, Newton.Blog.PostImage
```

- [ ] **Step 5: Add the context functions**

In `lib/newton/blog.ex`, extend the alias line to include `PostImage` (currently `alias Newton.Blog.Post` or similar — match file style), confirm `import Ecto.Query` is present (it is, for the existing list queries), and add:

```elixir
  @doc "Records an editor upload on the post's image ledger."
  @spec attach_image(%Post{}, String.t(), String.t() | nil) ::
          {:ok, %PostImage{}} | {:error, Ecto.Changeset.t()}
  def attach_image(%Post{} = post, key, original_filename \\ nil) do
    %PostImage{post_id: post.id}
    |> PostImage.create_changeset(%{key: key, original_filename: original_filename})
    |> Repo.insert()
  end

  @spec list_images(%Post{}) :: [%PostImage{}]
  def list_images(%Post{} = post) do
    Repo.all(
      from i in PostImage,
        where: i.post_id == ^post.id,
        order_by: [asc: i.inserted_at, asc: i.id]
    )
  end

  @doc "Whether the post's markdown still uses the image. Usage is derived, never stored."
  @spec image_referenced?(%Post{}, %PostImage{}) :: boolean()
  def image_referenced?(%Post{} = post, %PostImage{} = image) do
    String.contains?(post.body_markdown || "", image.key)
  end
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `mix test test/newton/blog/post_images_test.exs`
Expected: 4 tests, 0 failures.

- [ ] **Step 7: Commit** *(skip while the commit hold stands)*

```bash
git add priv/repo/migrations lib/newton/blog/post_image.ex lib/newton/blog.ex lib/newton/blog/post.ex test/newton/blog/post_images_test.exs
git commit -m "Add the post_images ledger: attach, list, derived referenced?"
```

---

### Task 2: Lifecycle — guarded delete_image, delete_post file cleanup

**Files:**
- Modify: `lib/newton/blog.ex` (`delete_image/1`; replace `delete_post/1`)
- Test: `test/newton/blog/post_images_test.exs` (extend)

**Interfaces:**
- Consumes: Task 1's functions; `Newton.Gallery.Storage.delete/1` (`:ok` always).
- Produces: `Blog.delete_image(image)` → `{:ok, %PostImage{}} | {:error, :referenced | Ecto.Changeset.t()}`; `Blog.delete_post(post)` (same signature as today, now also removes owned files).

- [ ] **Step 1: Write the failing tests**

Add to `test/newton/blog/post_images_test.exs`:

```elixir
  defp stored_file(key) do
    root = Application.fetch_env!(:newton, :media_root)
    File.mkdir_p!(root)
    path = Path.join(root, key)
    File.write!(path, "img-bytes")
    path
  end

  test "delete_image removes the file and the record for an unreferenced image" do
    post = post_fixture()
    {:ok, image} = Blog.attach_image(post, "gone.png", nil)
    path = stored_file("gone.png")

    assert {:ok, _} = Blog.delete_image(image)
    refute File.exists?(path)
    assert Blog.list_images(post) == []
  end

  test "delete_image refuses while the post still references the image" do
    post = post_fixture(%{body_markdown: "![](/media/kept.png)"})
    {:ok, image} = Blog.attach_image(post, "kept.png", nil)
    path = stored_file("kept.png")

    assert {:error, :referenced} = Blog.delete_image(image)
    assert File.exists?(path)
    assert [_] = Blog.list_images(post)
  end

  test "delete_post removes the post's image files" do
    post = post_fixture()
    {:ok, _} = Blog.attach_image(post, "a.png", nil)
    {:ok, _} = Blog.attach_image(post, "b.png", nil)
    a = stored_file("a.png")
    b = stored_file("b.png")

    assert {:ok, _} = Blog.delete_post(post)
    refute File.exists?(a)
    refute File.exists?(b)
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/newton/blog/post_images_test.exs`
Expected: the three new tests FAIL (`delete_image/1` undefined; files survive `delete_post`).

- [ ] **Step 3: Implement**

In `lib/newton/blog.ex`, add `alias Newton.Gallery.Storage` next to the existing aliases, add `delete_image/1`, and replace the one-line `delete_post/1`:

```elixir
  @doc "Deletes an image's file and ledger row. Refused while the post still uses it."
  @spec delete_image(%PostImage{}) ::
          {:ok, %PostImage{}} | {:error, :referenced | Ecto.Changeset.t()}
  def delete_image(%PostImage{} = image) do
    post = Repo.get!(Post, image.post_id)

    if image_referenced?(post, image) do
      {:error, :referenced}
    else
      Storage.delete(image.key)
      Repo.delete(image)
    end
  end

  @doc "Deletes a post and the image files it owns; ledger rows cascade."
  @spec delete_post(%Post{}) :: {:ok, %Post{}} | {:error, Ecto.Changeset.t()}
  def delete_post(%Post{} = post) do
    post |> list_images() |> Enum.each(&Storage.delete(&1.key))
    Repo.delete(post)
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/newton/blog/post_images_test.exs`
Expected: 7 tests, 0 failures. Also run `mix test test/newton/blog_test.exs` — the existing `delete_post` tests must still pass.

- [ ] **Step 5: Commit** *(skip while the commit hold stands)*

```bash
git add lib/newton/blog.ex test/newton/blog/post_images_test.exs
git commit -m "Delete post images with their post; guard manual deletes on live references"
```

---

### Task 3: Editor upload flow — attach on upload, draft-on-first-upload

**Files:**
- Modify: `lib/newton_web/live/admin/post_live/editor.ex` (`handle_inline_upload/3` + two private helpers)
- Test: `test/newton_web/live/admin/post_editor_live_test.exs` (extend)

**Interfaces:**
- Consumes: `Blog.attach_image/3` (Task 1), existing `backfill_new/1`, `Storage.store/2`, `Gallery.image_url/1`.
- Produces: no new public interface; Task 4 relies on `socket.assigns.post` always holding a persisted post after any completed upload.

**Context for the implementer:** the current handler is at `lib/newton_web/live/admin/post_live/editor.ex:35`:

```elixir
  defp handle_inline_upload(:inline_images, entry, socket) do
    if entry.done? do
      url =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          {:ok, key} = Storage.store(path, entry.client_name)
          {:ok, Gallery.image_url(key)}
        end)

      {:noreply, push_event(socket, "insert_image", %{url: url, alt: ""})}
    else
      {:noreply, socket}
    end
  end
```

On `/admin/posts/new` the socket holds `%Post{id: nil}` until the first contentful autosave (`persist_autosave/3` at line 195 creates it via `Blog.create_post(backfill_new(params))` then `push_patch`es to the edit URL). Uploads complete before their markdown reaches the doc, so the handler must create the draft itself. Failure posture (from the spec): if draft creation or attach fails, the upload still stores the file and inserts markdown — degraded to untracked, never blocking the author.

- [ ] **Step 1: Write the failing tests**

Add to `test/newton_web/live/admin/post_editor_live_test.exs` (reuse the existing `@png_1x1` and `open_draft/2`):

```elixir
  test "an upload lands on the post's image ledger", %{conn: conn} do
    {view, post} = open_draft(conn)

    image =
      file_input(view, "#post-form", :inline_images, [
        %{name: "shot.png", content: @png_1x1, type: "image/png"}
      ])

    render_upload(image, "shot.png")

    assert [attached] = Newton.Blog.list_images(post)
    assert attached.original_filename == "shot.png"
    assert_push_event(view, "insert_image", %{url: url})
    assert url == "/media/" <> attached.key
  end

  test "the first upload on a brand-new post creates the draft and attaches to it", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

    image =
      file_input(view, "#post-form", :inline_images, [
        %{name: "first.png", content: @png_1x1, type: "image/png"}
      ])

    render_upload(image, "first.png")
    assert_patch(view)

    assert [post] = Newton.Blog.list_posts(:drafts)
    assert [%{original_filename: "first.png"}] = Newton.Blog.list_images(post)
    assert_push_event(view, "insert_image", %{url: "/media/" <> _})
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/newton_web/live/admin/post_editor_live_test.exs`
Expected: the two new tests FAIL (`list_images` empty; no patch happens on the new-post path).

- [ ] **Step 3: Implement**

Replace `handle_inline_upload/3` and add the helpers below it:

```elixir
  defp handle_inline_upload(:inline_images, entry, socket) do
    if entry.done? do
      socket = ensure_post(socket)
      post = socket.assigns.post

      url =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          {:ok, key} = Storage.store(path, entry.client_name)
          attach_image(post, key, entry.client_name)
          {:ok, Gallery.image_url(key)}
        end)

      {:noreply, push_event(socket, "insert_image", %{url: url, alt: ""})}
    else
      {:noreply, socket}
    end
  end

  defp ensure_post(%{assigns: %{post: %Post{id: nil}}} = socket) do
    case Blog.create_post(backfill_new(%{})) do
      {:ok, post} ->
        socket
        |> assign(:post, post)
        |> assign(:published_at, post.published_at)
        |> push_patch(to: ~p"/admin/posts/#{post.id}/edit")

      {:error, _changeset} ->
        socket
    end
  end

  defp ensure_post(socket), do: socket

  defp attach_image(%Post{id: nil}, _key, _original_filename), do: :ok

  defp attach_image(%Post{} = post, key, original_filename) do
    Blog.attach_image(post, key, original_filename)
    :ok
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/newton_web/live/admin/post_editor_live_test.exs`
Expected: all tests pass, including the pre-existing upload/autosave tests (the new-post autosave path is unchanged — `ensure_post` merely front-runs it when an upload arrives first).

- [ ] **Step 5: Commit** *(skip while the commit hold stands)*

```bash
git add lib/newton_web/live/admin/post_live/editor.ex test/newton_web/live/admin/post_editor_live_test.exs
git commit -m "Attach editor uploads to the post, creating the draft on a first-upload race"
```

---

### Task 4: Admin Images section — visibility + manual cleanup

**Files:**
- Modify: `lib/newton_web/live/admin/post_live/editor.ex` (assign `:images`; render section; `delete_image` event; refresh after upload)
- Test: `test/newton_web/live/admin/post_editor_live_test.exs` (extend)

**Interfaces:**
- Consumes: `Blog.list_images/1`, `Blog.image_referenced?/2`, `Blog.delete_image/1` (Tasks 1–2); Task 3's guarantee that `@post` is persisted after any completed upload.
- Produces: DOM ids `#post-images` (section) and `#post-image-<id>` (per image) used by tests.

**Note on staleness:** the badge computes referenced-ness from the last *saved* `body_markdown`; autosave keeps that near-current, and `Blog.delete_image/1` re-checks server-side at delete time, which is the real gate.

- [ ] **Step 1: Write the failing tests**

Add to `test/newton_web/live/admin/post_editor_live_test.exs`:

```elixir
  defp stored_file(key) do
    root = Application.fetch_env!(:newton, :media_root)
    File.mkdir_p!(root)
    path = Path.join(root, key)
    File.write!(path, "img-bytes")
    path
  end

  test "deleting an unreferenced image removes it from disk, ledger, and page", %{conn: conn} do
    {:ok, post} =
      Newton.Blog.create_post(%{title: "Img", slug: "img-post", body_markdown: "No pics anymore."})

    {:ok, image} = Newton.Blog.attach_image(post, "stale.png", "stale.png")
    path = stored_file("stale.png")

    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")
    assert has_element?(view, "#post-image-#{image.id}")

    view |> element("#post-image-#{image.id} button", "Delete") |> render_click()

    refute has_element?(view, "#post-image-#{image.id}")
    refute File.exists?(path)
    assert Newton.Blog.list_images(post) == []
  end

  test "a referenced image shows no delete button and survives a forged delete", %{conn: conn} do
    {:ok, post} =
      Newton.Blog.create_post(%{
        title: "Img",
        slug: "img-post-2",
        body_markdown: "![](/media/live.png)"
      })

    {:ok, image} = Newton.Blog.attach_image(post, "live.png", "live.png")
    stored_file("live.png")

    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")
    assert has_element?(view, "#post-image-#{image.id}")
    refute has_element?(view, "#post-image-#{image.id} button")

    render_click(view, "delete_image", %{"id" => to_string(image.id)})
    assert [_] = Newton.Blog.list_images(post)
  end

  test "an upload appears in the Images section immediately", %{conn: conn} do
    {view, _post} = open_draft(conn)

    image =
      file_input(view, "#post-form", :inline_images, [
        %{name: "fresh.png", content: @png_1x1, type: "image/png"}
      ])

    render_upload(image, "fresh.png")
    assert has_element?(view, "#post-images")
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/newton_web/live/admin/post_editor_live_test.exs`
Expected: the three new tests FAIL (no `#post-images` in the page).

- [ ] **Step 3: Implement**

In `lib/newton_web/live/admin/post_live/editor.ex`:

a) Wherever the socket's `:post` assign is established for both routes (`handle_params` — follow the existing assignment of `@post`), also assign images:

```elixir
    |> assign(:images, post_images(post))
```

with the helper:

```elixir
  defp post_images(%Post{id: nil}), do: []
  defp post_images(%Post{} = post), do: Blog.list_images(post)
```

b) In `handle_inline_upload/3` (from Task 3), refresh the list after the consume block, before the `{:noreply, ...}`:

```elixir
      socket = assign(socket, :images, post_images(post))
```

c) Add the event handler alongside the other `handle_event` clauses:

```elixir
  @impl true
  def handle_event("delete_image", %{"id" => id}, socket) do
    post = socket.assigns.post

    socket.assigns.images
    |> Enum.find(&(to_string(&1.id) == id))
    |> case do
      nil -> :ok
      image -> Blog.delete_image(image)
    end

    {:noreply, assign(socket, :images, post_images(post))}
  end
```

d) In `render/1`, after the closing `</.form>` tag and before the `<Components.drawer ...>`, add:

```heex
      <section :if={@images != []} id="post-images" class="mt-8">
        <h2 class="mb-3 text-[0.78rem] uppercase tracking-wide text-(--admin-text-subtle)">
          Images
        </h2>
        <ul class="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <li
            :for={image <- @images}
            id={"post-image-#{image.id}"}
            class="rounded-lg border border-(--admin-border) bg-(--admin-surface) p-2"
          >
            <img src={Gallery.image_url(image.key)} alt="" class="h-24 w-full rounded object-cover" />
            <div class="mt-2 flex items-center justify-between gap-2 text-[0.72rem] text-(--admin-text-subtle)">
              <span class="truncate">{image.original_filename || image.key}</span>
              <%= if Blog.image_referenced?(@post, image) do %>
                <span class="shrink-0 text-(--admin-text-muted)">in use</span>
              <% else %>
                <span class="shrink-0 text-amber-400/80">not referenced</span>
                <button
                  type="button"
                  phx-click="delete_image"
                  phx-value-id={image.id}
                  data-confirm="Delete this image file? This cannot be undone."
                  class="shrink-0 text-red-400 hover:text-red-300"
                >
                  Delete
                </button>
              <% end %>
            </div>
          </li>
        </ul>
      </section>
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/newton_web/live/admin/post_editor_live_test.exs`
Expected: all tests pass. (In the forged-delete test the section renders "in use" instead of a button; the server-side `{:error, :referenced}` keeps the row.)

- [ ] **Step 5: Commit** *(skip while the commit hold stands)*

```bash
git add lib/newton_web/live/admin/post_live/editor.ex test/newton_web/live/admin/post_editor_live_test.exs
git commit -m "Show a post's images in the editor with manual cleanup for unused ones"
```

---

### Task 5: Backfill & audit

**Files:**
- Create: `lib/newton/blog/image_backfill.ex`
- Create: `lib/mix/tasks/newton.post_images.backfill.ex`
- Test: `test/newton/blog/image_backfill_test.exs`

**Interfaces:**
- Consumes: `Post` (`body_markdown`, `slug`), `PostImage`, `Newton.Gallery.Photo` (`image_key`, `thumb_key`), media volume via `:media_root` config.
- Produces: `Newton.Blog.ImageBackfill.run/0` → `%{adopted: [String.t()], missing: [{slug, key}], strays: [String.t()]}`; `mix newton.post_images.backfill` prints that report.

**Rules (from the spec):** adopt = insert a `post_images` row for every `/media/<key>` referenced in a post body when the file exists on the volume and no row exists (`original_filename` left nil). Never adopt keys owned by the `photos` table (a manually embedded gallery URL must not transfer ownership — post deletion would delete a gallery file). Report, never delete: `missing` (referenced but not on the volume) and `strays` (volume files owned by neither table). Idempotent.

- [ ] **Step 1: Write the failing tests**

Create `test/newton/blog/image_backfill_test.exs`:

```elixir
defmodule Newton.Blog.ImageBackfillTest do
  use Newton.DataCase
  alias Newton.Blog
  alias Newton.Blog.ImageBackfill

  defp media_root, do: Application.fetch_env!(:newton, :media_root)

  defp stored_file(key) do
    File.mkdir_p!(media_root())
    File.write!(Path.join(media_root(), key), "img-bytes")
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

  test "adopts referenced on-volume files, skipping already-tracked ones" do
    post = post_with_body("![](/media/wild.png) and ![](/media/tracked.png)")
    {:ok, _} = Blog.attach_image(post, "tracked.png", nil)
    stored_file("wild.png")
    stored_file("tracked.png")

    report = ImageBackfill.run()

    assert report.adopted == ["wild.png"]
    assert Enum.map(Blog.list_images(post), & &1.key) |> Enum.sort() ==
             ["tracked.png", "wild.png"]
  end

  test "never adopts gallery photo keys" do
    group = Newton.GalleryFixtures.group_fixture()
    photo = Newton.GalleryFixtures.photo_fixture(group)
    post = post_with_body("![](/media/#{photo.image_key})")
    stored_file(photo.image_key)

    report = ImageBackfill.run()

    assert report.adopted == []
    assert Blog.list_images(post) == []
  end

  test "reports referenced-but-missing keys and unowned volume strays" do
    post = post_with_body("![](/media/ghost.png)")
    stored_file("stray.png")

    report = ImageBackfill.run()

    assert report.missing == [{post.slug, "ghost.png"}]
    assert report.strays == ["stray.png"]
  end

  test "is idempotent" do
    post_with_body("![](/media/wild.png)")
    stored_file("wild.png")

    assert %{adopted: ["wild.png"]} = ImageBackfill.run()
    assert %{adopted: []} = ImageBackfill.run()
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/newton/blog/image_backfill_test.exs`
Expected: FAIL — `Newton.Blog.ImageBackfill` is undefined.

- [ ] **Step 3: Implement the core**

Create `lib/newton/blog/image_backfill.ex`:

```elixir
defmodule Newton.Blog.ImageBackfill do
  @moduledoc """
  Adopts untracked inline post images into the post_images ledger and audits
  volume/ledger drift. Reports anomalies; never deletes anything.
  """
  import Ecto.Query
  alias Newton.Blog.{Post, PostImage}
  alias Newton.Gallery.Photo
  alias Newton.Repo

  @media_url ~r{/media/([A-Za-z0-9_-]+\.[A-Za-z0-9]+)}

  @spec run() :: %{
          adopted: [String.t()],
          missing: [{String.t(), String.t()}],
          strays: [String.t()]
        }
  def run do
    tracked = MapSet.new(Repo.all(from i in PostImage, select: i.key))
    photo_keys = photo_keys()
    volume = volume_keys()

    {adopted, missing} =
      Repo.all(from p in Post, order_by: p.id)
      |> Enum.reduce({[], []}, fn post, acc ->
        adopt_post(post, tracked, photo_keys, volume, acc)
      end)

    owned = tracked |> MapSet.union(MapSet.new(adopted)) |> MapSet.union(photo_keys)

    %{
      adopted: Enum.reverse(adopted),
      missing: Enum.reverse(missing),
      strays: volume |> MapSet.difference(owned) |> Enum.sort()
    }
  end

  defp adopt_post(post, tracked, photo_keys, volume, acc) do
    @media_url
    |> Regex.scan(post.body_markdown || "")
    |> Enum.map(fn [_, key] -> key end)
    |> Enum.uniq()
    |> Enum.reduce(acc, fn key, {adopted, missing} ->
      cond do
        MapSet.member?(tracked, key) or MapSet.member?(photo_keys, key) or key in adopted ->
          {adopted, missing}

        MapSet.member?(volume, key) ->
          {:ok, _} =
            %PostImage{post_id: post.id}
            |> PostImage.create_changeset(%{key: key})
            |> Repo.insert()

          {[key | adopted], missing}

        true ->
          {adopted, [{post.slug, key} | missing]}
      end
    end)
  end

  defp photo_keys do
    Repo.all(from p in Photo, select: {p.image_key, p.thumb_key})
    |> Enum.flat_map(fn {a, b} -> [a, b] end)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp volume_keys do
    root = Application.fetch_env!(:newton, :media_root)

    case File.ls(root) do
      {:ok, entries} -> entries |> Enum.filter(&File.regular?(Path.join(root, &1))) |> MapSet.new()
      {:error, _} -> MapSet.new()
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/newton/blog/image_backfill_test.exs`
Expected: 4 tests, 0 failures.

- [ ] **Step 5: Add the mix-task shell**

Create `lib/mix/tasks/newton.post_images.backfill.ex`:

```elixir
defmodule Mix.Tasks.Newton.PostImages.Backfill do
  @shortdoc "Adopt untracked inline post images; audit volume/ledger drift"
  @moduledoc """
  Scans every post body for /media/<key> references, inserts missing
  post_images rows for files present on the volume, and reports (never
  deletes) referenced-but-missing keys and unowned volume files.

      mix newton.post_images.backfill
  """
  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(_args) do
    report = Newton.Blog.ImageBackfill.run()

    Mix.shell().info("adopted: #{length(report.adopted)}")
    Enum.each(report.adopted, &Mix.shell().info("  + #{&1}"))

    Mix.shell().info("missing from volume: #{length(report.missing)}")
    Enum.each(report.missing, fn {slug, key} -> Mix.shell().info("  ! #{slug}: #{key}") end)

    Mix.shell().info("unowned volume files: #{length(report.strays)}")
    Enum.each(report.strays, &Mix.shell().info("  ? #{&1}"))
  end
end
```

Run: `mix newton.post_images.backfill` against the dev database.
Expected: it prints the three report sections; rerunning shows `adopted: 0`.

- [ ] **Step 6: Run the full suite and precommit**

Run: `mix precommit`
Expected: passes clean (compile without warnings, format, full test suite).

- [ ] **Step 7: Commit** *(skip while the commit hold stands)*

```bash
git add lib/newton/blog/image_backfill.ex lib/mix/tasks/newton.post_images.backfill.ex test/newton/blog/image_backfill_test.exs
git commit -m "Backfill/audit task: adopt untracked inline post images, report drift"
```

---

## Post-plan notes

- **Production backfill:** after deploy, run the task once on the release
  (`fly ssh console` → `/app/bin/newton rpc "IO.inspect(Newton.Blog.ImageBackfill.run())"`)
  — Mix tasks aren't available in releases, which is exactly why the logic
  lives in `Newton.Blog.ImageBackfill` and the mix task is a dev-only shell.
- **Deploy scope reminder:** `fly deploy` ships the working tree; confirm
  scope with James before any deploy.
