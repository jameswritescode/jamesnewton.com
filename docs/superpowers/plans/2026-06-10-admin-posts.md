# Admin Posts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A complete Posts management section in the admin — list with status, a full create/edit editor with a publish drawer, delete, and session-aware draft visibility on the public `/posts/:slug`.

**Architecture:** Two admin LiveViews (`PostLive.Index`, `PostLive.Editor`) under the existing gated `/admin` `live_session`, styled with the admin theme tokens. The editor uses a plain markdown **textarea** for the body (Milkdown is a separate Plan 3 that swaps only the textarea). `body_markdown` stays canonical; MDEx renders `body_html` on save via the existing `Post.changeset`. Publish state is a `published_at` datetime managed through drawer controls. The public `PostController.show` becomes session-aware so a signed-in admin can preview drafts at the real URL.

**Tech Stack:** Phoenix 1.8 LiveView, Ecto/Postgres, the existing `Newton.Blog` context + `Post` schema, `Newton.Slug`, admin theme tokens (`assets/css/admin.css`).

**Scope note:** Plan 2 of the admin series (Plan 1 = foundation). Plan 3 swaps the body textarea for Milkdown. Reading and Photos are later plans. Spec: `docs/superpowers/specs/2026-06-10-admin-dashboard-design.md`.

---

## File Structure

**Authored / modified in this plan:**
- Modify: `lib/newton/blog.ex` — admin queries: `get_post!/1`, `get_post_by_slug!/1`, `delete_post/1`, `change_post/2`, `publish_status/1`
- Modify: `lib/newton_web/controllers/post_controller.ex` — session-aware `show/2`
- Create: `lib/newton_web/live/admin/post_live/index.ex` — `NewtonWeb.Admin.PostLive.Index` (list + delete)
- Create: `lib/newton_web/live/admin/post_live/editor.ex` — `NewtonWeb.Admin.PostLive.Editor` (new/edit + publish drawer)
- Modify: `lib/newton_web/router.ex` — three post routes in the `:admin` `live_session`
- Tests: `test/newton/blog_test.exs`, `test/newton_web/controllers/post_controller_test.exs`, `test/newton_web/live/admin/post_index_live_test.exs`, `test/newton_web/live/admin/post_editor_live_test.exs`

**Conventions to follow (already in the repo):**
- `conn.assigns.current_scope.user` is `nil` for anonymous visitors and a `%Newton.Accounts.User{}` for the signed-in admin (set by the `:browser` pipeline's `fetch_current_scope_for_user` plug).
- Admin LiveViews wrap content in `<Layouts.admin flash={@flash} current={...}>` where `Layouts` is `NewtonWeb.Admin.Layouts`.
- Admin styling uses theme tokens via Tailwind utilities, e.g. `bg-(--admin-surface)`, `text-(--admin-text)`, `border-(--admin-border)`, `text-(--admin-accent)`.
- `Post.changeset/2` already derives `body_html`, `excerpt`, and `reading_time` from `body_markdown` on save.

---

## Task 1: Blog admin queries + publish status

**Files:**
- Modify: `lib/newton/blog.ex`
- Test: `test/newton/blog_test.exs`

- [ ] **Step 1: Write the failing tests**

Append to `test/newton/blog_test.exs` (before the final `end`):

```elixir
  test "get_post!/1 fetches any post by id, including drafts" do
    {:ok, draft} = Blog.create_post(%{@valid | slug: "d", published_at: nil})
    assert Blog.get_post!(draft.id).id == draft.id
  end

  test "get_post_by_slug!/1 fetches any post by slug, including drafts" do
    {:ok, draft} = Blog.create_post(%{@valid | slug: "draft-slug", published_at: nil})
    assert Blog.get_post_by_slug!("draft-slug").id == draft.id
    assert_raise Ecto.NoResultsError, fn -> Blog.get_post_by_slug!("missing") end
  end

  test "delete_post/1 removes the post" do
    {:ok, post} = Blog.create_post(@valid)
    {:ok, _} = Blog.delete_post(post)
    assert_raise Ecto.NoResultsError, fn -> Blog.get_post!(post.id) end
  end

  test "change_post/2 returns a changeset" do
    {:ok, post} = Blog.create_post(@valid)
    assert %Ecto.Changeset{} = Blog.change_post(post, %{title: "New"})
  end

  test "publish_status/1 derives draft/scheduled/published from a datetime" do
    future = DateTime.add(DateTime.utc_now(), 60, :minute)
    past = DateTime.add(DateTime.utc_now(), -60, :minute)
    assert Blog.publish_status(nil) == :draft
    assert Blog.publish_status(future) == :scheduled
    assert Blog.publish_status(past) == :published
  end
```

- [ ] **Step 2: Run to confirm failure**

Run: `mix test test/newton/blog_test.exs`
Expected: FAIL — `get_post!/1` undefined.

- [ ] **Step 3: Implement the functions**

In `lib/newton/blog.ex`, add after `list_posts/0`:

```elixir
  @doc "Fetch any post by id (admin), regardless of publish status."
  def get_post!(id), do: Repo.get!(Post, id)

  @doc "Fetch any post by slug (admin), regardless of publish status."
  def get_post_by_slug!(slug), do: Repo.get_by!(Post, slug: slug)

  @doc "Delete a post."
  def delete_post(%Post{} = post), do: Repo.delete(post)

  @doc "Build a post changeset for forms."
  def change_post(%Post{} = post, attrs \\ %{}), do: Post.changeset(post, attrs)

  @doc "Derive publish status from a `published_at` value (or nil)."
  def publish_status(nil), do: :draft

  def publish_status(%DateTime{} = at) do
    if DateTime.compare(at, DateTime.utc_now()) == :gt, do: :scheduled, else: :published
  end
```

- [ ] **Step 4: Run to confirm pass**

Run: `mix test test/newton/blog_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/newton/blog.ex test/newton/blog_test.exs
git commit -m "Add admin post queries and publish_status to Blog"
```

---

## Task 2: Draft visibility on the public `/posts/:slug`

A signed-in admin sees any post at its real URL; anonymous visitors see only published posts (404 otherwise). The public index is unchanged (drafts never listed).

**Files:**
- Modify: `lib/newton_web/controllers/post_controller.ex`
- Test: `test/newton_web/controllers/post_controller_test.exs`

- [ ] **Step 1: Write the failing tests**

Append to `test/newton_web/controllers/post_controller_test.exs` (inside the top-level `describe`/module — match the file's existing structure; if unsure, add a new `describe` block before the final `end`):

```elixir
  describe "draft visibility" do
    setup do
      {:ok, draft} =
        Newton.Blog.create_post(%{
          slug: "secret-draft",
          title: "Secret Draft",
          body_markdown: "Hidden body.",
          published_at: nil
        })

      %{draft: draft}
    end

    test "anonymous visitors get 404 for a draft", %{conn: conn, draft: draft} do
      conn = get(conn, ~p"/posts/#{draft.slug}")
      assert conn.status == 404
    end

    test "a signed-in admin can preview a draft at its real URL", %{conn: conn, draft: draft} do
      {:ok, user} = Newton.Release.create_admin("preview@example.com", "supersecret123")

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/posts/#{draft.slug}")

      assert html_response(conn, 200) =~ "Secret Draft"
    end
  end
```

> `log_in_user/2` is the generated `ConnCase` helper. If the existing test file does not `import Phoenix.LiveViewTest` or set up `~p`, no change is needed — `ConnCase` already provides `~p` and `get/2`.

- [ ] **Step 2: Run to confirm failure**

Run: `mix test test/newton_web/controllers/post_controller_test.exs`
Expected: FAIL — the admin currently gets 404 too (or the draft raises for everyone).

- [ ] **Step 3: Make `show/2` session-aware**

Replace the body of `lib/newton_web/controllers/post_controller.ex`'s `show/2`:

```elixir
  def show(conn, %{"slug" => slug}) do
    post = fetch_post(conn.assigns.current_scope, slug)
    render(conn, :show, page_title: post.title, post: post)
  end

  # A signed-in admin previews any post (drafts included); everyone else sees
  # only published posts (404 otherwise).
  defp fetch_post(%{user: nil}, slug), do: Blog.get_published_post!(slug)
  defp fetch_post(_admin_scope, slug), do: Blog.get_post_by_slug!(slug)
```

- [ ] **Step 4: Run to confirm pass**

Run: `mix test test/newton_web/controllers/post_controller_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/newton_web/controllers/post_controller.ex test/newton_web/controllers/post_controller_test.exs
git commit -m "Let a signed-in admin preview drafts at /posts/:slug"
```

---

## Task 3: Posts list — `PostLive.Index`

**Files:**
- Modify: `lib/newton_web/router.ex`
- Create: `lib/newton_web/live/admin/post_live/index.ex`
- Test: `test/newton_web/live/admin/post_index_live_test.exs`

- [ ] **Step 1: Write the failing test**

Create `test/newton_web/live/admin/post_index_live_test.exs`:

```elixir
defmodule NewtonWeb.Admin.PostIndexLiveTest do
  use NewtonWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Newton.AccountsFixtures

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture())}
  end

  defp post_fixture(attrs) do
    {:ok, post} =
      Newton.Blog.create_post(
        Map.merge(%{title: "T", slug: "t", body_markdown: "body"}, attrs)
      )

    post
  end

  test "lists posts with a status label and a new-post link", %{conn: conn} do
    post_fixture(%{title: "Published", slug: "pub", published_at: ~U[2026-01-01 00:00:00Z]})
    post_fixture(%{title: "Draft", slug: "draft", published_at: nil})

    {:ok, view, _html} = live(conn, ~p"/admin/posts")

    assert has_element?(view, "#posts")
    assert has_element?(view, "a", "New post")
    assert render(view) =~ "Published"
    assert render(view) =~ "Draft"
  end
end
```

- [ ] **Step 2: Run to confirm failure**

Run: `mix test test/newton_web/live/admin/post_index_live_test.exs`
Expected: FAIL — route/LiveView missing.

- [ ] **Step 3: Add the routes**

In `lib/newton_web/router.ex`, inside the existing `live_session :admin` block, add below the dashboard route:

```elixir
      live "/posts", PostLive.Index, :index
      live "/posts/new", PostLive.Editor, :new
      live "/posts/:id/edit", PostLive.Editor, :edit
```

> The `Editor` routes are used in Tasks 5–8; adding them now keeps the router edits in one place. The module is created in Task 5, so the suite will not compile until then — implement Task 3's LiveView and Task 5's together if executing strictly in order, or expect a compile error on this route until Task 5.

To avoid a compile gap, add only the index route in this task:

```elixir
      live "/posts", PostLive.Index, :index
```

and add the two `Editor` routes in Task 5.

- [ ] **Step 4: Implement `PostLive.Index`**

Create `lib/newton_web/live/admin/post_live/index.ex`:

```elixir
defmodule NewtonWeb.Admin.PostLive.Index do
  use NewtonWeb, :live_view

  alias NewtonWeb.Admin.Layouts

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :posts, Newton.Blog.list_posts())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current={:posts}>
      <div class="mb-6 flex items-center justify-between">
        <h1 class="text-[1.35rem] font-semibold tracking-tight">Posts</h1>
        <.link
          navigate={~p"/admin/posts/new"}
          class="rounded-md bg-(--admin-accent) px-3 py-1.5 text-[0.8rem] font-medium text-white no-underline hover:bg-(--admin-accent-hover)"
        >
          New post
        </.link>
      </div>

      <div id="posts" phx-update="stream" class="overflow-hidden rounded-xl border border-(--admin-border)">
        <div class="hidden only:block p-5 text-[0.85rem] text-(--admin-text-subtle)">
          No posts yet.
        </div>
        <.link
          :for={{id, post} <- @streams.posts}
          id={id}
          navigate={~p"/admin/posts/#{post.id}/edit"}
          class="flex items-center gap-3 border-b border-(--admin-border) bg-(--admin-surface) px-4 py-3 no-underline last:border-b-0 hover:bg-(--admin-accent-soft)"
        >
          <span class="flex-1 text-[0.9rem] font-medium text-(--admin-text)">{post.title}</span>
          <.status_badge status={Newton.Blog.publish_status(post.published_at)} />
          <span class="w-28 text-right text-[0.78rem] text-(--admin-text-subtle)">
            {format_date(post.published_at)}
          </span>
        </.link>
      </div>
    </Layouts.admin>
    """
  end

  attr :status, :atom, required: true

  defp status_badge(assigns) do
    ~H"""
    <span class={[
      "rounded-full px-2 py-0.5 text-[0.7rem] font-medium",
      @status == :published && "bg-(--admin-accent-soft) text-(--admin-accent)",
      @status == :draft && "border border-(--admin-border-strong) text-(--admin-text-subtle)",
      @status == :scheduled && "bg-(--admin-accent-soft) text-(--admin-accent)"
    ]}>
      {@status}
    </span>
    """
  end

  defp format_date(nil), do: "—"
  defp format_date(%DateTime{} = at), do: Calendar.strftime(at, "%b %-d, %Y")
end
```

- [ ] **Step 5: Run to confirm pass**

Run: `mix test test/newton_web/live/admin/post_index_live_test.exs`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/newton_web/router.ex lib/newton_web/live/admin/post_live/index.ex test/newton_web/live/admin/post_index_live_test.exs
git commit -m "Add admin Posts list LiveView"
```

---

## Task 4: Delete a post from the list

**Files:**
- Modify: `lib/newton_web/live/admin/post_live/index.ex`
- Test: `test/newton_web/live/admin/post_index_live_test.exs`

- [ ] **Step 1: Write the failing test**

Append to `test/newton_web/live/admin/post_index_live_test.exs` (before the final `end`):

```elixir
  test "deletes a post from the list", %{conn: conn} do
    post = post_fixture(%{title: "Doomed", slug: "doomed"})

    {:ok, view, _html} = live(conn, ~p"/admin/posts")
    assert render(view) =~ "Doomed"

    view |> element("#posts button[phx-value-id='#{post.id}']") |> render_click()

    refute render(view) =~ "Doomed"
    assert_raise Ecto.NoResultsError, fn -> Newton.Blog.get_post!(post.id) end
  end
```

- [ ] **Step 2: Run to confirm failure**

Run: `mix test test/newton_web/live/admin/post_index_live_test.exs`
Expected: FAIL — no delete button.

- [ ] **Step 3: Add the delete button and handler**

In `lib/newton_web/live/admin/post_live/index.ex`, add a delete button inside each row. Because the row is a `<.link navigate>`, put the button as a sibling cell and stop propagation. Replace the row markup's trailing date span block with:

```elixir
          <span class="w-28 text-right text-[0.78rem] text-(--admin-text-subtle)">
            {format_date(post.published_at)}
          </span>
          <button
            type="button"
            phx-click="delete"
            phx-value-id={post.id}
            data-confirm="Delete this post?"
            class="rounded-md px-2 py-1 text-[0.75rem] text-(--admin-text-subtle) hover:text-(--admin-accent)"
          >
            Delete
          </button>
```

Add the handler:

```elixir
  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    post = Newton.Blog.get_post!(id)
    {:ok, _} = Newton.Blog.delete_post(post)
    {:noreply, stream_delete(socket, :posts, post)}
  end
```

> Note: the button lives inside an `<.link navigate>`; `phx-click` on the button is handled before navigation and `data-confirm` intercepts. If navigation still fires in manual testing, change the row from a `<.link>` wrapper to a `<div>` with an explicit "Edit" `<.link>` cell. The test only needs the delete button to work.

- [ ] **Step 4: Run to confirm pass**

Run: `mix test test/newton_web/live/admin/post_index_live_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/newton_web/live/admin/post_live/index.ex test/newton_web/live/admin/post_index_live_test.exs
git commit -m "Add delete to the admin Posts list"
```

---

## Task 5: Editor — create a new post

**Files:**
- Modify: `lib/newton_web/router.ex` (add the two Editor routes)
- Create: `lib/newton_web/live/admin/post_live/editor.ex`
- Test: `test/newton_web/live/admin/post_editor_live_test.exs`

- [ ] **Step 1: Add the Editor routes**

In `lib/newton_web/router.ex`, inside `live_session :admin`, below the `live "/posts", PostLive.Index, :index` line:

```elixir
      live "/posts/new", PostLive.Editor, :new
      live "/posts/:id/edit", PostLive.Editor, :edit
```

- [ ] **Step 2: Write the failing test**

Create `test/newton_web/live/admin/post_editor_live_test.exs`:

```elixir
defmodule NewtonWeb.Admin.PostEditorLiveTest do
  use NewtonWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Newton.AccountsFixtures

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture())}
  end

  test "creates a post and redirects to the list", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

    {:ok, _index, html} =
      view
      |> form("#post-form", post: %{title: "Hello Admin", slug: "hello-admin", body_markdown: "Body text."})
      |> render_submit()
      |> follow_redirect(conn, ~p"/admin/posts")

    assert html =~ "Hello Admin"
    assert Newton.Blog.get_post_by_slug!("hello-admin").body_html =~ "Body text."
  end
end
```

- [ ] **Step 3: Run to confirm failure**

Run: `mix test test/newton_web/live/admin/post_editor_live_test.exs`
Expected: FAIL — `PostLive.Editor` undefined.

- [ ] **Step 4: Implement `PostLive.Editor` (new + save)**

Create `lib/newton_web/live/admin/post_live/editor.ex`:

```elixir
defmodule NewtonWeb.Admin.PostLive.Editor do
  use NewtonWeb, :live_view

  alias Newton.Blog
  alias Newton.Blog.Post
  alias NewtonWeb.Admin.Layouts

  @impl true
  def mount(params, _session, socket) do
    {:ok, load(socket, socket.assigns.live_action, params)}
  end

  defp load(socket, :new, _params) do
    post = %Post{}

    socket
    |> assign(:page_title, "New post")
    |> assign(:post, post)
    |> assign(:published_at, nil)
    |> assign(:drawer_open, false)
    |> assign(:form, to_form(Blog.change_post(post)))
  end

  defp load(socket, :edit, %{"id" => id}) do
    post = Blog.get_post!(id)

    socket
    |> assign(:page_title, "Edit post")
    |> assign(:post, post)
    |> assign(:published_at, post.published_at)
    |> assign(:drawer_open, false)
    |> assign(:form, to_form(Blog.change_post(post)))
  end

  @impl true
  def handle_event("save", %{"post" => params}, socket) do
    params = Map.put(params, "published_at", socket.assigns.published_at)
    save(socket, socket.assigns.post, params)
  end

  defp save(socket, %Post{id: nil}, params) do
    case Blog.create_post(params) do
      {:ok, _post} ->
        {:noreply,
         socket
         |> put_flash(:info, "Post created")
         |> push_navigate(to: ~p"/admin/posts")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save(socket, %Post{} = post, params) do
    case Blog.update_post(post, params) do
      {:ok, _post} ->
        {:noreply,
         socket
         |> put_flash(:info, "Post saved")
         |> push_navigate(to: ~p"/admin/posts")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current={:posts}>
      <.form for={@form} id="post-form" phx-submit="save" phx-change="validate">
        <div class="mb-4 flex items-center gap-3">
          <.link navigate={~p"/admin/posts"} class="text-[0.8rem] text-(--admin-text-subtle) no-underline hover:text-(--admin-text)">
            ← Posts
          </.link>
          <div class="flex-1"></div>
          <button
            type="submit"
            class="rounded-md bg-(--admin-accent) px-3 py-1.5 text-[0.8rem] font-medium text-white hover:bg-(--admin-accent-hover)"
          >
            Save
          </button>
        </div>

        <.input
          field={@form[:title]}
          type="text"
          placeholder="Title"
          class="mb-4 w-full border-none bg-transparent text-2xl font-semibold text-(--admin-text) focus:outline-none"
        />

        <.input
          field={@form[:body_markdown]}
          type="textarea"
          placeholder="Write your post in markdown…"
          rows="24"
          class="w-full rounded-lg border border-(--admin-border) bg-(--admin-surface) p-4 font-mono text-[0.9rem] text-(--admin-text) focus:outline-none"
        />
      </.form>
    </Layouts.admin>
    """
  end
end
```

> The `<.input>` component wraps inputs in its own markup; the `class` overrides the default classes. If the rendered field id is not `post[title]`-derived, the test still targets `#post-form`, so it passes regardless. A `validate` handler is added in Task 6 — until then, `phx-change="validate"` with no handler raises on change but not on the submit path the test uses. Implement Task 6 immediately after to avoid a runtime error in the browser.

- [ ] **Step 5: Run to confirm pass**

Run: `mix test test/newton_web/live/admin/post_editor_live_test.exs`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/newton_web/router.ex lib/newton_web/live/admin/post_live/editor.ex test/newton_web/live/admin/post_editor_live_test.exs
git commit -m "Add admin post editor with create"
```

---

## Task 6: Editor — live validation + slug auto-fill

**Files:**
- Modify: `lib/newton_web/live/admin/post_live/editor.ex`
- Test: `test/newton_web/live/admin/post_editor_live_test.exs`

- [ ] **Step 1: Write the failing test**

Append to `test/newton_web/live/admin/post_editor_live_test.exs`:

```elixir
  test "auto-fills the slug from the title while the slug is blank", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

    html =
      view
      |> form("#post-form", post: %{title: "My First Post!", slug: "", body_markdown: "x"})
      |> render_change()

    assert html =~ ~s(value="my-first-post")
  end

  test "shows validation errors on invalid submit", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

    html =
      view
      |> form("#post-form", post: %{title: "", slug: "", body_markdown: ""})
      |> render_submit()

    assert html =~ "can&#39;t be blank"
  end
```

- [ ] **Step 2: Run to confirm failure**

Run: `mix test test/newton_web/live/admin/post_editor_live_test.exs`
Expected: FAIL — no `validate` handler / slug not auto-filled.

- [ ] **Step 3: Add the validate handler with slug auto-fill**

In `lib/newton_web/live/admin/post_live/editor.ex`, add before the `save` handler:

```elixir
  @impl true
  def handle_event("validate", %{"post" => params}, socket) do
    params = maybe_autofill_slug(params)

    form =
      socket.assigns.post
      |> Blog.change_post(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  # Auto-fill the slug from the title only while the slug field is still blank,
  # so manual slug edits are never clobbered.
  defp maybe_autofill_slug(%{"slug" => slug} = params) when slug != "" do
    params
  end

  defp maybe_autofill_slug(%{"title" => title} = params) do
    Map.put(params, "slug", Newton.Slug.slugify(title))
  end

  defp maybe_autofill_slug(params), do: params
```

- [ ] **Step 4: Run to confirm pass**

Run: `mix test test/newton_web/live/admin/post_editor_live_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/newton_web/live/admin/post_live/editor.ex test/newton_web/live/admin/post_editor_live_test.exs
git commit -m "Add live validation and slug auto-fill to the post editor"
```

---

## Task 7: Editor — edit an existing post

**Files:**
- Test: `test/newton_web/live/admin/post_editor_live_test.exs` (the edit path is already wired in `load/3` from Task 5)

- [ ] **Step 1: Write the failing test**

Append to `test/newton_web/live/admin/post_editor_live_test.exs`:

```elixir
  test "loads an existing post and updates it", %{conn: conn} do
    {:ok, post} =
      Newton.Blog.create_post(%{title: "Original", slug: "original", body_markdown: "old body"})

    {:ok, view, html} = live(conn, ~p"/admin/posts/#{post.id}/edit")
    assert html =~ "Original"

    view
    |> form("#post-form", post: %{title: "Updated", slug: "original", body_markdown: "new body"})
    |> render_submit()
    |> follow_redirect(conn, ~p"/admin/posts")

    updated = Newton.Blog.get_post!(post.id)
    assert updated.title == "Updated"
    assert updated.body_html =~ "new body"
  end
```

- [ ] **Step 2: Run to confirm pass (edit already implemented in Task 5)**

Run: `mix test test/newton_web/live/admin/post_editor_live_test.exs`
Expected: PASS — `load/3` for `:edit` and the `update_post` save clause already exist.

> If this fails because the title isn't pre-filled, verify `load(socket, :edit, ...)` assigns `to_form(Blog.change_post(post))` (it does in Task 5). No code change should be needed; if one is, it belongs in `editor.ex`.

- [ ] **Step 3: Commit**

```bash
git add test/newton_web/live/admin/post_editor_live_test.exs
git commit -m "Cover editing an existing post"
```

---

## Task 8: Publish drawer

A slide-over panel in the editor holding the publish controls: status badge, Publish-now / Move-to-draft, an optional schedule date, an editable excerpt, a read-only reading time, a "View on site" link, and Delete (edit only).

**Files:**
- Modify: `lib/newton_web/live/admin/post_live/editor.ex`
- Test: `test/newton_web/live/admin/post_editor_live_test.exs`

- [ ] **Step 1: Write the failing tests**

Append to `test/newton_web/live/admin/post_editor_live_test.exs`:

```elixir
  test "publish-now sets the post to published on save", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

    view |> element("button", "Publish now") |> render_click()

    view
    |> form("#post-form", post: %{title: "Pub", slug: "pub-now", body_markdown: "body"})
    |> render_submit()
    |> follow_redirect(conn, ~p"/admin/posts")

    assert Newton.Blog.publish_status(Newton.Blog.get_post_by_slug!("pub-now").published_at) ==
             :published
  end

  test "delete removes the post and redirects to the list", %{conn: conn} do
    {:ok, post} =
      Newton.Blog.create_post(%{title: "Kill", slug: "kill", body_markdown: "b"})

    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")

    view
    |> element("button", "Delete post")
    |> render_click()
    |> follow_redirect(conn, ~p"/admin/posts")

    assert_raise Ecto.NoResultsError, fn -> Newton.Blog.get_post!(post.id) end
  end
```

- [ ] **Step 2: Run to confirm failure**

Run: `mix test test/newton_web/live/admin/post_editor_live_test.exs`
Expected: FAIL — no "Publish now"/"Delete post" controls.

- [ ] **Step 3: Add the drawer toggle, publish controls, and delete**

In `lib/newton_web/live/admin/post_live/editor.ex`, add these handlers (after `validate`):

```elixir
  @impl true
  def handle_event("toggle_drawer", _params, socket) do
    {:noreply, assign(socket, :drawer_open, !socket.assigns.drawer_open)}
  end

  def handle_event("publish_now", _params, socket) do
    {:noreply, assign(socket, :published_at, DateTime.truncate(DateTime.utc_now(), :second))}
  end

  def handle_event("unpublish", _params, socket) do
    {:noreply, assign(socket, :published_at, nil)}
  end

  def handle_event("schedule", %{"value" => ""}, socket) do
    {:noreply, assign(socket, :published_at, nil)}
  end

  def handle_event("schedule", %{"value" => date_string}, socket) do
    published_at =
      case Date.from_iso8601(date_string) do
        {:ok, date} -> DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
        _ -> socket.assigns.published_at
      end

    {:noreply, assign(socket, :published_at, published_at)}
  end

  def handle_event("delete", _params, socket) do
    {:ok, _} = Blog.delete_post(socket.assigns.post)

    {:noreply,
     socket
     |> put_flash(:info, "Post deleted")
     |> push_navigate(to: ~p"/admin/posts")}
  end
```

In the toolbar (the `<div class="mb-4 flex items-center gap-3">` block), add a "Publish settings" button and a live status badge before the Save button:

```elixir
          <span class="text-[0.78rem] text-(--admin-text-subtle)">{Blog.publish_status(@published_at)}</span>
          <button
            type="button"
            phx-click="toggle_drawer"
            class="rounded-md border border-(--admin-border) px-3 py-1.5 text-[0.8rem] text-(--admin-text) hover:bg-(--admin-accent-soft)"
          >
            Publish settings
          </button>
```

Just **before** the closing `</.form>` (so the drawer's fields submit with the form — the drawer is `position: fixed`, so its place in the DOM doesn't affect layout), add the drawer:

```elixir
      <div
        :if={@drawer_open}
        class="fixed inset-y-0 right-0 z-20 flex w-80 flex-col gap-4 border-l border-(--admin-border) bg-(--admin-sidebar) p-5 shadow-xl"
      >
        <div class="flex items-center justify-between">
          <span class="text-[0.9rem] font-semibold">Publish</span>
          <button type="button" phx-click="toggle_drawer" aria-label="Close" class="text-(--admin-text-subtle) hover:text-(--admin-text)">
            <.icon name="hero-x-mark-mini" class="size-5" />
          </button>
        </div>

        <div class="flex gap-2">
          <button type="button" phx-click="publish_now" class="flex-1 rounded-md bg-(--admin-accent) px-2 py-1.5 text-[0.78rem] font-medium text-white hover:bg-(--admin-accent-hover)">
            Publish now
          </button>
          <button type="button" phx-click="unpublish" class="flex-1 rounded-md border border-(--admin-border) px-2 py-1.5 text-[0.78rem] hover:bg-(--admin-accent-soft)">
            Move to draft
          </button>
        </div>

        <label class="block text-[0.78rem]">
          <span class="mb-1 block text-(--admin-text-muted)">Schedule for</span>
          <input
            type="date"
            value={schedule_value(@published_at)}
            phx-change="schedule"
            class="w-full rounded-md border border-(--admin-border) bg-(--admin-surface) px-2 py-1 text-(--admin-text)"
          />
        </label>

        <.input field={@form[:excerpt]} type="textarea" label="Excerpt (optional)" rows="3" />

        <div class="text-[0.78rem] text-(--admin-text-subtle)">
          Reading time: {@post.reading_time || "—"} min
        </div>

        <.link
          :if={@post.id}
          href={~p"/posts/#{@post.slug}"}
          target="_blank"
          class="text-[0.8rem] text-(--admin-accent) no-underline hover:underline"
        >
          View on site ↗
        </.link>

        <div class="flex-1"></div>

        <button
          :if={@post.id}
          type="button"
          phx-click="delete"
          data-confirm="Delete this post permanently?"
          class="rounded-md border border-(--admin-border) px-3 py-1.5 text-[0.8rem] text-(--admin-accent) hover:bg-(--admin-accent-soft)"
        >
          Delete post
        </button>
      </div>
```

Add the helper at the bottom of the module:

```elixir
  defp schedule_value(nil), do: ""
  defp schedule_value(%DateTime{} = at), do: Calendar.strftime(at, "%Y-%m-%d")
```

> The drawer sits inside `<.form>` so its `excerpt` field submits with the post and its `phx-click` buttons (all `type="button"`) don't trigger submit. Because the drawer is `position: fixed`, placing it inside the form has no visual effect.

- [ ] **Step 4: Run to confirm pass**

Run: `mix test test/newton_web/live/admin/post_editor_live_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/newton_web/live/admin/post_live/editor.ex test/newton_web/live/admin/post_editor_live_test.exs
git commit -m "Add publish drawer to the post editor"
```

---

## Task 9: Precommit + browser smoke

**Files:** none (verification).

- [ ] **Step 1: Run precommit**

Run: `mix precommit`
Expected: PASS — compile (warnings-as-errors), formatter, `credo --strict`, both test suites, dialyzer. Fix any findings (no disabling credo rules without authorization).

- [ ] **Step 2: Manual / browser smoke (dev)**

Start the server (`mix phx.server`), sign in at `/users/log-in`, then:
- Visit `/admin/posts` → the list renders with status labels and a "New post" button.
- Create a post (title + markdown body), Save → it appears in the list as a draft.
- Edit it → open "Publish settings" → "Publish now" → Save → status shows published.
- "View on site ↗" opens `/posts/:slug` and shows the rendered post.
- While signed out, an unpublished post's `/posts/:slug` returns 404; signed in, it renders.
- Delete a post from the list and from the drawer.

- [ ] **Step 3: Final commit if precommit required fixes**

```bash
git add -A
git commit -m "Address precommit findings for admin Posts"
```

---

## Self-Review Notes

- **Spec coverage:** Posts list as the hub with status (Task 3) ✓; status badges (Task 3) ✓; create/edit editor with markdown body (Tasks 5–7) ✓; slug auto-from-title, editable (Task 6) ✓; publish drawer with status toggle / publish date / read-only reading time / excerpt / View-on-site / Delete (Task 8) ✓; `published_at` drives draft/scheduled/published (Tasks 1, 8) ✓; `/posts/:slug` draft visibility, anonymous 404 (Task 2) ✓; drafts absent from public index (unchanged `list_published_posts`) ✓. **Deferred (correctly):** the **Milkdown** rich editor — Plan 2 ships a markdown textarea; Plan 3 swaps it. The drawer is inlined in the editor here; extracting a shared drawer component is deferred until Reading/Photos need it.
- **Type consistency:** `Blog.publish_status/1` takes `nil | DateTime` and is used identically in Tasks 1, 3, 8. `Blog.get_post!/1`, `get_post_by_slug!/1`, `delete_post/1`, `change_post/2` signatures match across tasks. The editor keeps publish state in the `:published_at` assign (DateTime | nil) and injects it into save params as `"published_at"` — `Post.changeset`'s `cast` accepts a `%DateTime{}` value under that string key.
- **Placeholder scan:** no TBD/TODO; every code step includes full code. The two "if your browser differs" notes describe a concrete fallback, not missing content.
- **Router note:** Task 3 adds only `live "/posts", PostLive.Index`; Task 5 adds the two `Editor` routes, so each task compiles on its own.
