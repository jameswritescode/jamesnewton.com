# Post Auto-Save Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Draft posts auto-save (debounced) in the admin editor; "New post" creates a draft immediately, and an untouched auto-created draft is discarded on leave.

**Architecture:** A server-side debounce layered on the editor's existing `phx-change="validate"`: each validate (re)schedules a `Process.send_after(self(), :autosave, 1500)`; `handle_info(:autosave, …)` persists the latest params while the post is a draft. `apply_action(:new)` creates a draft and patches to its edit URL so the editor always edits a real post. `terminate/2` discards a pristine auto-created draft. No JS, no migration.

**Tech Stack:** Phoenix 1.8 LiveView, Ecto/Postgres.

---

## Context for the implementer

Read the spec first: `docs/superpowers/specs/2026-06-12-post-autosave-design.md`.

**Current code (exact):**

- `lib/newton/blog.ex` — `create_post/1`, `update_post/2`, `delete_post/1`, `change_post/2`, `get_post!/1`, `get_post_by_slug!/1`, `list_posts/0`, `publish_status/1`. Uses `import Ecto.Query`.
- `lib/newton/blog/post.ex` — `changeset/2` does `cast([:slug, :title, :excerpt, :body_markdown, :published_at])`, `validate_required([:slug, :title, :body_markdown])`, `unique_constraint(:slug)`, then `render_derived_fields/1` (recomputes `body_html`/`reading_time`/`excerpt` only when `body_markdown` is a change).
- `lib/newton_web/live/admin/post_live/editor.ex` — `mount/3` assigns `:drawer_open`; `apply_action(:new)` renders an empty form on `%Post{}`; `apply_action(:edit)` loads the post; `handle_event("validate", …)` does slug/excerpt autofill via `FormHelpers.autofill/5` and rebuilds the form; `handle_event("save", …)` → `save/2` (create when `id: nil`, else update); `set_published/2` persists publish toggles for existing posts. The form is `<.form id="post-form" phx-submit="save" phx-change="validate">`; Save button is in the header row.
- `lib/newton/slug.ex` — `Newton.Slug.slugify/1`.

**Patterns / rules:** TDD (failing test first). Test behaviors, not structure. No narrating comments — name helpers well. `mix precommit` at the end. To sync a LiveView process in tests after sending it a message, use `_ = :sys.get_state(view.pid)`. To assert a process terminated, use `Process.monitor/1` + `assert_receive {:DOWN, …}`.

**Key interactions to respect:**
- Relaxing `body_markdown` required (Task 1) lets an empty draft be created; no test asserts body is required (the "invalid submit" test relies on title/slug).
- The auto-created draft seeds slug `untitled-post`, which is **not blank**, so a few slug tests that assumed a blank starting slug are updated in Task 3 to send the current slug value (matching real usage, where the slug field always carries the last derived value).

## File structure

| File | Responsibility | Action |
| --- | --- | --- |
| `lib/newton/blog/post.ex` | Allow bodyless drafts | Modify |
| `lib/newton/blog.ex` | `next_untitled_slug/0` | Modify |
| `lib/newton_web/live/admin/post_live/editor.ex` | Auto-create, auto-save, discard, indicator | Modify |
| `test/newton/blog_test.exs` | Bodyless draft + slug helper tests | Modify |
| `test/newton_web/live/admin/post_editor_live_test.exs` | New-flow + auto-save + discard tests | Modify |

---

## Task 1: Allow bodyless drafts

**Files:**
- Modify: `lib/newton/blog/post.ex`
- Test: `test/newton/blog_test.exs`

An auto-created "Untitled post" draft has an empty body, so `body_markdown` can no longer be required.

- [ ] **Step 1: Write the failing test**

Add to `test/newton/blog_test.exs` (inside the module, before the final `end`):

```elixir
  test "a post can be created without a body" do
    assert {:ok, post} = Newton.Blog.create_post(%{title: "Empty", slug: "empty", body_markdown: ""})
    assert post.body_markdown == ""
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/newton/blog_test.exs`
Expected: FAIL — `body_markdown` "can't be blank".

- [ ] **Step 3: Relax the validation**

In `lib/newton/blog/post.ex`, change the `validate_required` line in `changeset/2` to:

```elixir
    |> validate_required([:slug, :title])
```

- [ ] **Step 4: Run it to verify it passes**

Run: `mix test test/newton/blog_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/newton/blog/post.ex test/newton/blog_test.exs
git commit -m "Allow posts to be created without a body"
```

---

## Task 2: Blog.next_untitled_slug/0

**Files:**
- Modify: `lib/newton/blog.ex`
- Test: `test/newton/blog_test.exs`

Returns the first free slug in the series `untitled-post`, `untitled-post-2`, …

- [ ] **Step 1: Write the failing test**

Add to `test/newton/blog_test.exs`:

```elixir
  test "next_untitled_slug returns the first free untitled slug" do
    assert Newton.Blog.next_untitled_slug() == "untitled-post"
    {:ok, _} = Newton.Blog.create_post(%{title: "Untitled post", slug: "untitled-post", body_markdown: ""})
    assert Newton.Blog.next_untitled_slug() == "untitled-post-2"
    {:ok, _} = Newton.Blog.create_post(%{title: "Untitled post", slug: "untitled-post-2", body_markdown: ""})
    assert Newton.Blog.next_untitled_slug() == "untitled-post-3"
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/newton/blog_test.exs`
Expected: FAIL — `Newton.Blog.next_untitled_slug/0` is undefined.

- [ ] **Step 3: Implement it**

In `lib/newton/blog.ex`, add:

```elixir
  @doc "First free slug in the series untitled-post, untitled-post-2, …"
  def next_untitled_slug do
    taken =
      Repo.all(from p in Post, where: like(p.slug, "untitled-post%"), select: p.slug)
      |> MapSet.new()

    Stream.iterate(1, &(&1 + 1))
    |> Enum.find_value(fn n ->
      slug = if n == 1, do: "untitled-post", else: "untitled-post-#{n}"
      if slug not in taken, do: slug
    end)
  end
```

- [ ] **Step 4: Run it to verify it passes**

Run: `mix test test/newton/blog_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/newton/blog.ex test/newton/blog_test.exs
git commit -m "Add Blog.next_untitled_slug for new drafts"
```

---

## Task 3: New post auto-creates a draft

**Files:**
- Modify: `lib/newton_web/live/admin/post_live/editor.ex`
- Test: `test/newton_web/live/admin/post_editor_live_test.exs`

`apply_action(:new)` now creates a draft and patches to its edit URL; the editor always edits a persisted post. This removes the `id: nil` save branch. Several existing tests are updated for the new flow.

- [ ] **Step 1: Update the affected tests (new flow)**

In `test/newton_web/live/admin/post_editor_live_test.exs`, replace the test "creates a post and stays in the editor on its edit URL" with:

```elixir
  test "a new post opens as a draft and edits persist", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

    view
    |> form("#post-form",
      post: %{title: "Hello Admin", slug: "hello-admin", body_markdown: "Body text."}
    )
    |> render_submit()

    post = Newton.Blog.get_post_by_slug!("hello-admin")
    assert post.body_html =~ "Body text."
    assert Newton.Blog.publish_status(post.published_at) == :draft
  end
```

Replace "auto-fills the slug from the title while the slug is blank" with:

```elixir
  test "the slug follows the title", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

    html =
      view
      |> form("#post-form", post: %{title: "My First Post!", slug: "untitled-post"})
      |> render_change()

    assert html =~ ~s(value="my-first-post")
  end
```

Replace "slug keeps following the full title across keystrokes" with:

```elixir
  test "slug keeps following the full title across keystrokes", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

    view |> form("#post-form", post: %{title: "h", slug: "untitled-post"}) |> render_change()
    html = view |> form("#post-form", post: %{title: "hello", slug: "h"}) |> render_change()
    assert html =~ ~s(value="hello")
  end
```

Replace "a manual slug edit stops the slug from following the title" with:

```elixir
  test "a manual slug edit stops the slug from following the title", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

    view |> form("#post-form", post: %{title: "hello", slug: "untitled-post"}) |> render_change()
    view |> form("#post-form", post: %{title: "hello", slug: "custom"}) |> render_change()
    html =
      view |> form("#post-form", post: %{title: "hello world", slug: "custom"}) |> render_change()

    assert html =~ ~s(value="custom")
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/newton_web/live/admin/post_editor_live_test.exs`
Expected: FAIL — `/admin/posts/new` still renders an empty form (slug starts blank, no draft created), so the new-flow assertions don't hold.

- [ ] **Step 3: Implement auto-create**

In `lib/newton_web/live/admin/post_live/editor.ex`, update `mount/3` to seed the auto-save assigns:

```elixir
  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:drawer_open, false)
     |> assign(:autocreated?, false)
     |> assign(:edited?, false)
     |> assign(:save_state, :saved)
     |> assign(:autosave_params, nil)
     |> assign(:autosave_timer, nil)}
  end
```

Replace `apply_action(socket, :new, _params)` with:

```elixir
  defp apply_action(socket, :new, _params) do
    {:ok, post} =
      Blog.create_post(%{
        "title" => "Untitled post",
        "slug" => Blog.next_untitled_slug(),
        "body_markdown" => ""
      })

    socket
    |> assign(:autocreated?, true)
    |> push_patch(to: ~p"/admin/posts/#{post.id}/edit")
  end
```

Update `apply_action(socket, :edit, …)` to preserve `:autocreated?` and reset the edit-session auto-save assigns. Replace it with:

```elixir
  defp apply_action(socket, :edit, %{"id" => id}) do
    post = Blog.get_post!(id)

    socket
    |> assign_new(:autocreated?, fn -> false end)
    |> assign(:page_title, "Edit post")
    |> assign(:post, post)
    |> assign(:published_at, post.published_at)
    |> assign(:slug_locked, slug_locked?(post))
    |> assign(:slug_auto, post.slug)
    |> assign(:excerpt_locked, excerpt_locked?(post))
    |> assign(:excerpt_auto, post.excerpt || "")
    |> assign(:edited?, false)
    |> assign(:save_state, :saved)
    |> assign(:autosave_params, nil)
    |> assign(:form, to_form(Blog.change_post(post)))
  end
```

Remove the now-dead `save(socket, %Post{id: nil}, params)` clause (the editor always edits a persisted post). Also simplify `set_published/2` to drop its `%Post{id: nil}` branch — replace the whole `set_published/2` with:

```elixir
  defp set_published(socket, published_at) do
    {:ok, post} = Blog.update_post(socket.assigns.post, %{"published_at" => published_at})

    socket
    |> assign(:post, post)
    |> assign(:published_at, post.published_at)
    |> put_flash(:info, if(post.published_at, do: "Post published", else: "Moved to draft"))
  end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/newton_web/live/admin/post_editor_live_test.exs`
Expected: PASS — all editor tests green under the new flow.

- [ ] **Step 5: Commit**

```bash
git add lib/newton_web/live/admin/post_live/editor.ex test/newton_web/live/admin/post_editor_live_test.exs
git commit -m "Create a draft immediately when starting a new post"
```

---

## Task 4: Auto-save drafts (debounced) + save-state indicator

**Files:**
- Modify: `lib/newton_web/live/admin/post_live/editor.ex`
- Test: `test/newton_web/live/admin/post_editor_live_test.exs`

Validate schedules a debounced `:autosave`; `handle_info(:autosave, …)` persists draft changes. A quiet indicator reflects state. (No `:saving` state — the DB write is synchronous, so there is no async window to show it; states are `:saved`, `:unsaved`, `:error`.)

- [ ] **Step 1: Write the failing tests**

Add to `test/newton_web/live/admin/post_editor_live_test.exs`:

```elixir
  test "editing a draft auto-saves without a manual save", %{conn: conn} do
    {:ok, post} =
      Newton.Blog.create_post(%{title: "Draft", slug: "auto-draft", body_markdown: "old"})

    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")

    view
    |> form("#post-form", post: %{title: "Draft", slug: "auto-draft", body_markdown: "new body"})
    |> render_change()

    send(view.pid, :autosave)
    _ = :sys.get_state(view.pid)

    assert Newton.Blog.get_post!(post.id).body_html =~ "new body"
  end

  test "a published post is not auto-saved", %{conn: conn} do
    {:ok, post} =
      Newton.Blog.create_post(%{
        title: "Live",
        slug: "live-auto",
        body_markdown: "original",
        published_at: ~U[2026-01-01 00:00:00Z]
      })

    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")

    view
    |> form("#post-form", post: %{title: "Live", slug: "live-auto", body_markdown: "changed"})
    |> render_change()

    send(view.pid, :autosave)
    _ = :sys.get_state(view.pid)

    refute Newton.Blog.get_post!(post.id).body_html =~ "changed"
  end

  test "the editor shows unsaved then saved state for a draft", %{conn: conn} do
    {:ok, post} = Newton.Blog.create_post(%{title: "D", slug: "state-draft", body_markdown: "a"})
    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")

    html = view |> form("#post-form", post: %{body_markdown: "b"}) |> render_change()
    assert html =~ "Unsaved changes"

    send(view.pid, :autosave)
    _ = :sys.get_state(view.pid)
    refute render(view) =~ "Unsaved changes"
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/newton_web/live/admin/post_editor_live_test.exs`
Expected: FAIL — there is no `:autosave` handler and no indicator.

- [ ] **Step 3: Add the debounce + handler + indicator**

In `lib/newton_web/live/admin/post_live/editor.ex`, add the debounce module attribute near the top (after `use`):

```elixir
  @autosave_debounce_ms 1500
```

At the end of `handle_event("validate", …)`, replace the final `{:noreply, …}` block with a version that schedules auto-save for drafts. The full handler becomes:

```elixir
  @impl true
  def handle_event("validate", %{"post" => params}, socket) do
    published? = not is_nil(socket.assigns.published_at)

    slug_locked =
      socket.assigns.slug_locked or published? or params["slug"] != socket.assigns.slug_auto

    excerpt_locked =
      socket.assigns.excerpt_locked or params["excerpt"] != socket.assigns.excerpt_auto

    {params, slug_auto} =
      FormHelpers.autofill(params, "slug", slug_locked, socket.assigns.slug_auto, fn ->
        Newton.Slug.slugify(params["title"] || "")
      end)

    {params, excerpt_auto} =
      FormHelpers.autofill(params, "excerpt", excerpt_locked, socket.assigns.excerpt_auto, fn ->
        Newton.Markdown.excerpt(params["body_markdown"] || "")
      end)

    form =
      socket.assigns.post
      |> Blog.change_post(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply,
     socket
     |> assign(:form, form)
     |> assign(:slug_locked, slug_locked)
     |> assign(:slug_auto, slug_auto)
     |> assign(:excerpt_locked, excerpt_locked)
     |> assign(:excerpt_auto, excerpt_auto)
     |> maybe_schedule_autosave(params, not published?)}
  end
```

Add these private helpers (place them near `set_published/2`):

```elixir
  defp maybe_schedule_autosave(socket, _params, false), do: socket

  defp maybe_schedule_autosave(socket, params, true) do
    socket
    |> assign(:edited?, socket.assigns.edited? or edited?(params))
    |> assign(:autosave_params, params)
    |> assign(:save_state, :unsaved)
    |> reschedule_autosave_timer()
  end

  defp edited?(params) do
    params["title"] != "Untitled post" or (params["body_markdown"] || "") != ""
  end

  defp reschedule_autosave_timer(socket) do
    if ref = socket.assigns.autosave_timer, do: Process.cancel_timer(ref)
    assign(socket, :autosave_timer, Process.send_after(self(), :autosave, @autosave_debounce_ms))
  end
```

Add the `:autosave` handler (place after the `handle_event` clauses, before the private `save/2`):

```elixir
  @impl true
  def handle_info(:autosave, socket) do
    draft? = is_nil(socket.assigns.published_at)

    if draft? and socket.assigns.autosave_params do
      case Blog.update_post(socket.assigns.post, socket.assigns.autosave_params) do
        {:ok, post} ->
          {:noreply,
           socket
           |> assign(:post, post)
           |> assign(:autosave_params, nil)
           |> assign(:autosave_timer, nil)
           |> assign(:save_state, :saved)}

        {:error, _changeset} ->
          {:noreply, assign(socket, :save_state, :error)}
      end
    else
      {:noreply, socket}
    end
  end
```

In the manual-save success branch (`save(socket, %Post{} = post, params)`), also reset the auto-save state. Replace that clause with:

```elixir
  defp save(socket, %Post{} = post, params) do
    case Blog.update_post(post, params) do
      {:ok, post} ->
        {:noreply,
         socket
         |> put_flash(:info, "Post saved")
         |> assign(:post, post)
         |> assign(:published_at, post.published_at)
         |> assign(:form, to_form(Blog.change_post(post)))
         |> assign(:save_state, :saved)
         |> assign(:autosave_params, nil)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end
```

Add the indicator to the header row in `render/1`. Replace the `<div class="flex-1"></div>` + status badge region so the indicator sits before the Save button — change this:

```elixir
          <div class="flex-1"></div>
          <Layouts.status_badge status={Blog.publish_status(@published_at)} />
```

to:

```elixir
          <div class="flex-1"></div>
          <span
            :if={Blog.publish_status(@published_at) == :draft}
            class="text-[0.78rem] text-(--admin-text-subtle)"
          >
            {save_state_label(@save_state)}
          </span>
          <Layouts.status_badge status={Blog.publish_status(@published_at)} />
```

Add the label helper (near `set_published/2`):

```elixir
  defp save_state_label(:unsaved), do: "Unsaved changes…"
  defp save_state_label(:error), do: "Couldn't save"
  defp save_state_label(_), do: "Saved"
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/newton_web/live/admin/post_editor_live_test.exs`
Expected: PASS — auto-save persists drafts, skips published, and the indicator flips.

- [ ] **Step 5: Commit**

```bash
git add lib/newton_web/live/admin/post_live/editor.ex test/newton_web/live/admin/post_editor_live_test.exs
git commit -m "Auto-save draft posts with a debounce and a status indicator"
```

---

## Task 5: Flush auto-save on blur

**Files:**
- Modify: `lib/newton_web/live/admin/post_live/editor.ex`
- Test: `test/newton_web/live/admin/post_editor_live_test.exs`

Leaving a field flushes the pending save immediately instead of waiting for the debounce.

- [ ] **Step 1: Write the failing test**

Add to `test/newton_web/live/admin/post_editor_live_test.exs`:

```elixir
  test "blurring a field flushes the pending auto-save", %{conn: conn} do
    {:ok, post} = Newton.Blog.create_post(%{title: "D", slug: "blur-draft", body_markdown: "a"})
    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")

    view |> form("#post-form", post: %{body_markdown: "blurred body"}) |> render_change()
    view |> element("#post_title") |> render_blur()
    _ = :sys.get_state(view.pid)

    assert Newton.Blog.get_post!(post.id).body_html =~ "blurred body"
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/newton_web/live/admin/post_editor_live_test.exs`
Expected: FAIL — no `autosave_now` handler / `phx-blur` wiring, so the save only happens on the (unfired) debounce timer.

- [ ] **Step 3: Add the blur handler + wiring**

In `lib/newton_web/live/admin/post_live/editor.ex`, add the handler (with the other `handle_event` clauses):

```elixir
  def handle_event("autosave_now", _params, socket) do
    if ref = socket.assigns.autosave_timer, do: Process.cancel_timer(ref)
    send(self(), :autosave)
    {:noreply, assign(socket, :autosave_timer, nil)}
  end
```

Add `phx-blur="autosave_now"` to the title input. Replace the title `<.input>` with:

```elixir
        <.input
          field={@form[:title]}
          type="text"
          placeholder="Title"
          phx-blur="autosave_now"
          class="mb-2 w-full border-none bg-transparent text-2xl font-semibold text-(--admin-text) focus:outline-none"
        />
```

And add it to the slug input. Replace the slug `<.input>` with:

```elixir
        <.input
          field={@form[:slug]}
          type="text"
          placeholder="slug"
          phx-blur="autosave_now"
          class="mb-4 w-full border-none bg-transparent font-mono text-[0.8rem] text-(--admin-text-subtle) focus:outline-none"
        />
```

- [ ] **Step 4: Run it to verify it passes**

Run: `mix test test/newton_web/live/admin/post_editor_live_test.exs`
Expected: PASS — blur flushes the pending save.

- [ ] **Step 5: Commit**

```bash
git add lib/newton_web/live/admin/post_live/editor.ex test/newton_web/live/admin/post_editor_live_test.exs
git commit -m "Flush draft auto-save on field blur"
```

---

## Task 6: Discard an untouched draft on leave

**Files:**
- Modify: `lib/newton_web/live/admin/post_live/editor.ex`
- Test: `test/newton_web/live/admin/post_editor_live_test.exs`

When the editor LiveView ends, an auto-created draft that was never edited is deleted.

- [ ] **Step 1: Write the failing tests**

Add to `test/newton_web/live/admin/post_editor_live_test.exs`:

```elixir
  test "an untouched new draft is discarded when the editor closes", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/posts/new")
    [draft] = Newton.Blog.list_posts()

    ref = Process.monitor(view.pid)
    GenServer.stop(view.pid)
    assert_receive {:DOWN, ^ref, :process, _, _}

    assert_raise Ecto.NoResultsError, fn -> Newton.Blog.get_post!(draft.id) end
  end

  test "an edited new draft survives when the editor closes", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/posts/new")
    [draft] = Newton.Blog.list_posts()

    view |> form("#post-form", post: %{title: "Real title"}) |> render_change()

    ref = Process.monitor(view.pid)
    GenServer.stop(view.pid)
    assert_receive {:DOWN, ^ref, :process, _, _}

    assert Newton.Blog.get_post!(draft.id).id == draft.id
  end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `mix test test/newton_web/live/admin/post_editor_live_test.exs`
Expected: FAIL — there is no `terminate/2`, so the untouched draft is not discarded.

- [ ] **Step 3: Add terminate/2**

In `lib/newton_web/live/admin/post_live/editor.ex`, add:

```elixir
  @impl true
  def terminate(_reason, socket) do
    discard_untouched_draft(socket.assigns)
    :ok
  end

  defp discard_untouched_draft(%{
         autocreated?: true,
         edited?: false,
         published_at: nil,
         post: %Post{id: id} = post
       })
       when not is_nil(id) do
    Blog.delete_post(post)
  end

  defp discard_untouched_draft(_assigns), do: :ok
```

- [ ] **Step 4: Run them to verify they pass**

Run: `mix test test/newton_web/live/admin/post_editor_live_test.exs`
Expected: PASS — untouched draft discarded, edited draft survives.

- [ ] **Step 5: Commit**

```bash
git add lib/newton_web/live/admin/post_live/editor.ex test/newton_web/live/admin/post_editor_live_test.exs
git commit -m "Discard an untouched new draft when the editor closes"
```

---

## Task 7: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full precommit suite**

Run: `mix precommit`
Expected: PASS — compile `--warnings-as-errors`, format, Credo `--strict`, both test suites, Dialyzer 0 errors. Fix anything reported.

- [ ] **Step 2: Manual smoke check (dev server running)**

Open `/admin/posts`, click **New post** — confirm it lands on `/admin/posts/<id>/edit` titled "Untitled post". Type a title and some body; pause — the indicator shows "Unsaved changes…" then "Saved"; refresh and confirm the content persisted without a manual Save. Navigate away from a fresh "New post" without typing — confirm the empty Untitled draft is gone from the list. Publish a draft, edit it — confirm no auto-save (manual Save only) and the indicator is hidden.

---

## Self-review notes

- **Spec coverage:** bodyless drafts + unique slug (Tasks 1–2); new post creates a draft immediately and the editor always edits a real post, removing the id-nil branch (Task 3); debounced draft-only auto-save + indicator + manual-save reset (Task 4); blur flush (Task 5); discard untouched draft on terminate (Task 6); verification (Task 7).
- **Deviation from spec:** the `:saving` indicator state is omitted — the auto-save DB write is synchronous within `handle_info`, so there is no async window to render "Saving…". States are `:saved`/`:unsaved`/`:error`.
- **Names/types consistent:** assigns `:autocreated?`, `:edited?`, `:save_state` (`:saved | :unsaved | :error`), `:autosave_params`, `:autosave_timer`; events `validate`, `save`, `autosave_now`; message `:autosave`; helpers `maybe_schedule_autosave/3`, `reschedule_autosave_timer/1`, `edited?/1`, `save_state_label/1`, `discard_untouched_draft/1`; `Blog.next_untitled_slug/0`. The slug tests updated in Task 3 reflect the non-blank `untitled-post` starting slug.
- **Out of scope (per spec):** revision history, auto-save for published posts, local-storage drafting.
