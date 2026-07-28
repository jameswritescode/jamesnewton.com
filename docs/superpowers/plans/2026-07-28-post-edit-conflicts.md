# Post Edit Conflict Handling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the post editor from silently losing edits when the same post is open in two browsers: detect stale writes with optimistic locking, surface a conflict banner, and replace LiveView's blind form recovery with a version-checked handshake.

**Architecture:** A `lock_version` column on posts makes every `Blog.update_post/2` a conditional write that returns `{:error, :stale}` when another session saved first. The editor LiveView turns that into a `:conflict` save state with "Load latest" / "Keep mine" resolution, and a custom `phx-auto-recover` handler only adopts reconnecting client state when its version still matches the database.

**Tech Stack:** Phoenix 1.8 LiveView, Ecto (`optimistic_lock/2`), existing `MarkdownEditor` CodeMirror hook (unchanged).

**Spec:** `docs/superpowers/specs/2026-07-28-post-edit-conflicts-design.md`

## Global Constraints

- TDD: failing test first, then implement (project memory: bias to TDD).
- Commits are SSH-signed (1Password); never use `--no-gpg-sign`; verify with `git cat-file commit HEAD | grep -q '^gpgsig'`. Every commit ends with the trailer lines used in this repo (Co-Authored-By + Claude-Session).
- No narrating comments — comments only for constraints the code cannot express (CLAUDE.md).
- Test behaviors, not markup: assert on DB outcomes, state transitions, and key element IDs, never raw HTML or hardcoded hrefs (CLAUDE.md).
- Commit messages are plain imperative sentences ("Add …", "Require …"), no conventional-commit prefixes — match `git log`.
- Run `mix precommit` after the final task and fix anything it flags.
- Copy strings verbatim from the spec: banner text "This post was changed in another window", buttons "Load latest" / "Keep mine", flash "Updated in another window — showing the latest version."

---

### Task 1: Optimistic locking in the Blog context

**Files:**
- Create: `priv/repo/migrations/<timestamp>_add_lock_version_to_posts.exs` (via `mix ecto.gen.migration`)
- Modify: `lib/newton/blog/post.ex` (schema + changeset)
- Modify: `lib/newton/blog.ex:27-30` (`update_post/2`)
- Test: `test/newton/blog_test.exs`

**Interfaces:**
- Consumes: existing `Blog.create_post/1`, `Blog.update_post/2`, `Post.changeset/2`.
- Produces: `Post` schema gains `lock_version :: integer` (default 1). `Blog.update_post/2` return type becomes `{:ok, %Post{}} | {:error, Ecto.Changeset.t() | :stale}` — Tasks 2 and 3 rely on the `{:error, :stale}` shape and on `post.lock_version`.

- [ ] **Step 1: Write the failing context test**

Append to `test/newton/blog_test.exs` (inside the existing module; it already aliases what it needs — if not, add `alias Newton.{Blog, Repo}` and `alias Newton.Blog.Post` to match the file's existing style):

```elixir
describe "update_post/2 optimistic locking" do
  test "returns {:error, :stale} and keeps the newer content when the post changed underneath" do
    {:ok, post} =
      Blog.create_post(%{"title" => "Race", "slug" => "race", "body_markdown" => "original"})

    {:ok, _newer} = Blog.update_post(post, %{"body_markdown" => "from computer A"})

    assert {:error, :stale} =
             Blog.update_post(post, %{"body_markdown" => "stale from computer B"})

    assert Repo.get!(Post, post.id).body_markdown == "from computer A"
  end

  test "sequential updates through fresh structs succeed" do
    {:ok, post} =
      Blog.create_post(%{"title" => "Seq", "slug" => "seq", "body_markdown" => "one"})

    {:ok, post} = Blog.update_post(post, %{"body_markdown" => "two"})
    assert {:ok, %Post{body_markdown: "three"}} =
             Blog.update_post(post, %{"body_markdown" => "three"})
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/newton/blog_test.exs`
Expected: the stale test FAILS — without locking the second update returns `{:ok, ...}` (match error on `{:error, :stale}`).

- [ ] **Step 3: Generate the migration**

```bash
mix ecto.gen.migration add_lock_version_to_posts
```

Edit the generated file to:

```elixir
defmodule Newton.Repo.Migrations.AddLockVersionToPosts do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add :lock_version, :integer, default: 1, null: false
    end
  end
end
```

Run: `mix ecto.migrate` (the test DB migrates automatically when tests run).

- [ ] **Step 4: Add the field and lock to the schema**

In `lib/newton/blog/post.ex`, add to the `schema "posts"` block after `field :preview_token, :string`:

```elixir
field :lock_version, :integer, default: 1
```

In `changeset/2`, add `optimistic_lock(:lock_version)` to the pipeline after `unique_constraint(:slug)`:

```elixir
def changeset(post, attrs) do
  post
  |> cast(attrs, [:slug, :title, :excerpt, :body_markdown, :published_at])
  |> clear_preview_token_when_published()
  |> ensure_body()
  |> validate_required([:slug, :title])
  |> unique_constraint(:slug)
  |> optimistic_lock(:lock_version)
  |> render_derived_fields()
end
```

(`import Ecto.Changeset` is already there; `optimistic_lock/2` comes with it. `rerender_changeset/1` stays as-is per the spec.)

- [ ] **Step 5: Return `{:error, :stale}` from update_post**

In `lib/newton/blog.ex`, replace `update_post/2`:

```elixir
@spec update_post(%Post{}, map()) ::
        {:ok, %Post{}} | {:error, Ecto.Changeset.t() | :stale}
def update_post(%Post{} = post, attrs) do
  post |> Post.changeset(attrs) |> Repo.update()
rescue
  Ecto.StaleEntryError -> {:error, :stale}
end
```

- [ ] **Step 6: Run the context tests**

Run: `mix test test/newton/blog_test.exs`
Expected: PASS (both new tests, no regressions in the file).

- [ ] **Step 7: Run the full suite to catch surprised callers**

Run: `mix test`
Expected: PASS. If any test fails on `Ecto.StaleEntryError` or on a `{:ok, _} = Blog.update_post(...)` match, it is reusing a stale struct across updates — fix the test to thread the updated struct, not the code.

- [ ] **Step 8: Commit**

```bash
git add priv/repo/migrations lib/newton/blog/post.ex lib/newton/blog.ex test/newton/blog_test.exs
git commit -m "Guard post updates with optimistic locking"
```

---

### Task 2: Conflict state in the editor LiveView

**Files:**
- Modify: `lib/newton_web/live/admin/post_live/editor.ex` — `persist_autosave/3` (~line 357), `save/3` (~line 503), `set_published/2` (~line 477), `track_save_state/3` (~line 417), `show_save_text?/2` (~line 470), toolbar in `render/1` (~line 533)
- Test: create `test/newton_web/live/admin/post_editor_conflict_test.exs`

**Interfaces:**
- Consumes: `Blog.update_post/2` returning `{:error, :stale}`; `Blog.get_post!/1`; existing helpers `new_editor_key/0`, `post_images/1`, `slug_locked?/1`, `excerpt_locked?/1`, `never_blank_identity/2`, `PublicationNotifier.notify_change/2`.
- Produces: `save_state` may be `:conflict`; element IDs `#conflict-banner`, `#conflict-load-latest`, `#conflict-keep-mine`; events `"conflict_load_latest"` and `"conflict_keep_mine"`. Task 3's tests reuse the new test file's helpers.

- [ ] **Step 1: Write the failing LiveView tests**

Create `test/newton_web/live/admin/post_editor_conflict_test.exs`:

```elixir
defmodule NewtonWeb.Admin.PostEditorConflictTest do
  use NewtonWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Newton.AccountsFixtures

  alias Newton.Blog

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture())}
  end

  defp open_editor(conn, attrs \\ %{}) do
    {:ok, post} =
      Blog.create_post(
        Enum.into(attrs, %{
          "title" => "Conflict post",
          "slug" => "conflict-post",
          "body_markdown" => "original body"
        })
      )

    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")
    {view, post}
  end

  defp write_elsewhere(post, body) do
    {:ok, updated} = Blog.update_post(post, %{"body_markdown" => body})
    updated
  end

  defp type_body(view, post, body) do
    view
    |> form("#post-form")
    |> render_change(%{
      "post" => %{"title" => post.title, "slug" => post.slug, "body_markdown" => body}
    })
  end

  defp autosave(view) do
    send(view.pid, :autosave)
    render(view)
  end

  test "a stale autosave shows the conflict banner and keeps the newer content", %{conn: conn} do
    {view, post} = open_editor(conn)
    write_elsewhere(post, "from computer A")

    type_body(view, post, "stale edit from computer B")
    autosave(view)

    assert has_element?(view, "#conflict-banner")
    assert Blog.get_post!(post.id).body_markdown == "from computer A"
  end

  test "Load latest adopts the newer version and clears the conflict", %{conn: conn} do
    {view, post} = open_editor(conn)
    write_elsewhere(post, "from computer A")
    type_body(view, post, "stale edit from computer B")
    autosave(view)

    view |> element("#conflict-load-latest") |> render_click()

    refute has_element?(view, "#conflict-banner")
    assert view |> element("#post-form") |> render() =~ "from computer A"

    type_body(view, post, "resumed edit")
    autosave(view)
    assert Blog.get_post!(post.id).body_markdown == "resumed edit"
  end

  test "Keep mine deliberately overwrites and clears the conflict", %{conn: conn} do
    {view, post} = open_editor(conn)
    write_elsewhere(post, "from computer A")
    type_body(view, post, "mine wins")
    autosave(view)

    view |> element("#conflict-keep-mine") |> render_click()

    refute has_element?(view, "#conflict-banner")
    assert Blog.get_post!(post.id).body_markdown == "mine wins"
  end

  test "typing during a conflict never auto-writes", %{conn: conn} do
    {view, post} = open_editor(conn)
    write_elsewhere(post, "from computer A")
    type_body(view, post, "first stale edit")
    autosave(view)
    assert has_element?(view, "#conflict-banner")

    type_body(view, post, "kept typing anyway")
    autosave(view)

    assert Blog.get_post!(post.id).body_markdown == "from computer A"
    assert has_element?(view, "#conflict-banner")

    view |> element("#conflict-keep-mine") |> render_click()
    assert Blog.get_post!(post.id).body_markdown == "kept typing anyway"
  end

  test "publishing from a stale window conflicts instead of crashing", %{conn: conn} do
    {view, post} = open_editor(conn)
    write_elsewhere(post, "from computer A")

    view |> element("button", "Settings") |> render_click()
    view |> element("#publish-drawer button", "Publish now") |> render_click()

    assert has_element?(view, "#conflict-banner")
    assert is_nil(Blog.get_post!(post.id).published_at)
  end

  test "a stale manual save of a published post conflicts and keeps the newer content", %{
    conn: conn
  } do
    published = DateTime.truncate(DateTime.utc_now(), :second)

    {view, post} =
      open_editor(conn, %{"slug" => "published-conflict", "published_at" => published})

    write_elsewhere(post, "from computer A")

    view
    |> form("#post-form")
    |> render_submit(%{
      "post" => %{"title" => post.title, "slug" => post.slug, "body_markdown" => "stale save"}
    })

    assert has_element?(view, "#conflict-banner")
    assert Blog.get_post!(post.id).body_markdown == "from computer A"
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/newton_web/live/admin/post_editor_conflict_test.exs`
Expected: FAIL — no `#conflict-banner` element exists, DB assertions fail (stale writes currently succeed), and the publish test crashes on the `{:ok, post} =` match in `set_published/2`.

- [ ] **Step 3: Handle `{:error, :stale}` in every editor write path**

In `lib/newton_web/live/admin/post_live/editor.ex`:

**3a.** `persist_autosave/3` (the `%Post{}` clause, ~line 357) — add a stale branch. The pending params stay in `:autosave_params` so "Keep mine" can use them:

```elixir
defp persist_autosave(socket, %Post{} = post, params) do
  case Blog.update_post(post, never_blank_identity(params, post)) do
    {:ok, updated} ->
      PublicationNotifier.notify_change(post, updated)

      {:noreply,
       socket
       |> assign(:post, updated)
       |> assign(:autosave_params, nil)
       |> assign(:autosave_timer, nil)
       |> assign(:save_state, :saved)
       |> reoffer_identity(updated, params)}

    {:error, :stale} ->
      {:noreply, enter_conflict(socket)}

    {:error, _changeset} ->
      {:noreply, assign(socket, :save_state, :error)}
  end
end
```

**3b.** `save/3` (the `%Post{}` clause, ~line 503) — add the stale branch, stashing the attempted params for "Keep mine":

```elixir
defp save(socket, %Post{} = post, params) do
  case Blog.update_post(post, params) do
    {:ok, updated} ->
      PublicationNotifier.notify_change(post, updated)

      {:noreply,
       socket
       |> put_flash(:info, "Post saved")
       |> assign(:post, updated)
       |> assign(:published_at, updated.published_at)
       |> assign(:form, to_form(Blog.change_post(updated)))
       |> assign(:save_state, :saved)
       |> assign(:autosave_params, nil)}

    {:error, :stale} ->
      {:noreply, socket |> assign(:autosave_params, params) |> enter_conflict()}

    {:error, changeset} ->
      {:noreply, assign(socket, :form, to_form(changeset))}
  end
end
```

**3c.** `set_published/2` (~line 477) — stop crash-matching; merge the publish intent into the pending params so "Keep mine" re-applies it:

```elixir
defp set_published(socket, published_at) do
  before = socket.assigns.post

  case Blog.update_post(before, %{"published_at" => published_at}) do
    {:ok, post} ->
      PublicationNotifier.notify_change(before, post)

      socket
      |> assign(:post, post)
      |> assign(:published_at, post.published_at)
      |> put_flash(:info, if(post.published_at, do: "Post published", else: "Moved to draft"))

    {:error, :stale} ->
      socket
      |> update(:autosave_params, &Map.put(&1 || %{}, "published_at", published_at))
      |> enter_conflict()

    {:error, _changeset} ->
      assign(socket, :save_state, :error)
  end
end
```

**3d.** Add the shared helper near `reschedule_autosave_timer/1`:

```elixir
defp enter_conflict(socket) do
  if ref = socket.assigns.autosave_timer, do: Process.cancel_timer(ref)

  socket
  |> assign(:autosave_timer, nil)
  |> assign(:save_state, :conflict)
end
```

- [ ] **Step 4: Freeze autosave while in conflict**

Typing while the banner is up must keep updating the pending params (so "Keep mine" saves the latest) but never schedule a write and never leave `:conflict`. Add a guard clause ABOVE the existing `track_save_state/3` clauses (~line 417):

```elixir
defp track_save_state(%{assigns: %{save_state: :conflict}} = socket, params, _published?) do
  assign(socket, :autosave_params, params)
end
```

And guard `handle_event("autosave_now", ...)` (~line 247) the same way — blur must not force a stale write. Add ABOVE the existing clause:

```elixir
def handle_event("autosave_now", _params, %{assigns: %{save_state: :conflict}} = socket) do
  {:noreply, socket}
end
```

- [ ] **Step 5: Resolution handlers**

Add alongside the other `handle_event` clauses:

```elixir
def handle_event("conflict_load_latest", _params, socket) do
  post = Blog.get_post!(socket.assigns.post.id)

  {:noreply,
   socket
   |> assign(:post, post)
   |> assign(:published_at, post.published_at)
   |> assign(:images, post_images(post))
   |> assign(:slug_locked, slug_locked?(post))
   |> assign(:slug_auto, post.slug)
   |> assign(:excerpt_locked, excerpt_locked?(post))
   |> assign(:excerpt_auto, post.excerpt || "")
   |> assign(:save_state, :saved)
   |> assign(:autosave_params, nil)
   |> assign(:form, to_form(Blog.change_post(post)))
   |> assign(:editor_key, new_editor_key())}
end

def handle_event("conflict_keep_mine", _params, socket) do
  fresh = Blog.get_post!(socket.assigns.post.id)
  params = socket.assigns.autosave_params || %{}

  case Blog.update_post(fresh, never_blank_identity(params, fresh)) do
    {:ok, updated} ->
      PublicationNotifier.notify_change(fresh, updated)

      {:noreply,
       socket
       |> assign(:post, updated)
       |> assign(:published_at, updated.published_at)
       |> assign(:form, to_form(Blog.change_post(updated)))
       |> assign(:save_state, :saved)
       |> assign(:autosave_params, nil)}

    {:error, _} ->
      {:noreply, assign(socket, :save_state, :error)}
  end
end
```

(`conflict_load_latest` bumps `editor_key` so the `phx-update="ignore"` CodeMirror region is rebuilt from the fresh post — the same mechanism `sync_editor_key/2` uses for post switches. `conflict_keep_mine` doesn't bump: the client editor already shows "mine".)

- [ ] **Step 6: Banner UI and save-text suppression**

In `render/1`, inside the toolbar div, directly after `<div class="flex-1"></div>` (~line 540):

```heex
<div
  :if={@save_state == :conflict}
  id="conflict-banner"
  class="flex items-center gap-2 rounded-md border border-amber-500/40 bg-amber-500/10 px-2.5 py-1 text-[0.78rem] text-amber-600 admin-dark:text-amber-400"
>
  <.icon name="hero-exclamation-triangle-mini" class="size-4 shrink-0" />
  This post was changed in another window
  <Components.button id="conflict-load-latest" variant="secondary" phx-click="conflict_load_latest">
    Load latest
  </Components.button>
  <Components.button id="conflict-keep-mine" variant="secondary" phx-click="conflict_keep_mine">
    Keep mine
  </Components.button>
</div>
```

Update `show_save_text?/2` (~line 470) so the banner replaces the text indicator instead of showing "Saved" (the `save_state_label` catch-all) next to it:

```elixir
defp show_save_text?(_published_at, :conflict), do: false

defp show_save_text?(published_at, save_state) do
  (not is_nil(published_at) and save_state != :saved) or
    (is_nil(published_at) and save_state == :error)
end
```

- [ ] **Step 7: Run the conflict tests**

Run: `mix test test/newton_web/live/admin/post_editor_conflict_test.exs`
Expected: PASS (all six).

- [ ] **Step 8: Run the editor + context suites**

Run: `mix test test/newton_web/live/admin/ test/newton/blog_test.exs`
Expected: PASS, no regressions.

- [ ] **Step 9: Commit**

```bash
git add lib/newton_web/live/admin/post_live/editor.ex test/newton_web/live/admin/post_editor_conflict_test.exs
git commit -m "Surface edit conflicts in the post editor"
```

---

### Task 3: Version-checked reconnect recovery

**Files:**
- Modify: `lib/newton_web/live/admin/post_live/editor.ex` — form tag + hidden input in `render/1` (~line 526), `handle_event("validate", ...)` (~line 205), new `handle_event("recover", ...)`
- Test: `test/newton_web/live/admin/post_editor_conflict_test.exs` (append)

**Interfaces:**
- Consumes: `post.lock_version` (Task 1), `new_editor_key/0`, the validate pipeline.
- Produces: `#post-form` gains `phx-auto-recover="recover"` and a hidden `post[lock_version]` input; `handle_event("recover", %{"post" => params}, socket)`.

- [ ] **Step 1: Write the failing recovery tests**

Append to `test/newton_web/live/admin/post_editor_conflict_test.exs`:

```elixir
test "recover with a matching version restores the client's typing", %{conn: conn} do
  {view, post} = open_editor(conn)

  render_change(view, "recover", %{
    "post" => %{
      "lock_version" => to_string(Blog.get_post!(post.id).lock_version),
      "title" => post.title,
      "slug" => post.slug,
      "body_markdown" => "typed before reconnect"
    }
  })

  autosave(view)

  assert Blog.get_post!(post.id).body_markdown == "typed before reconnect"
  assert view |> element("#post-form") |> render() =~ "typed before reconnect"
end

test "recover with a stale version keeps the latest content and writes nothing", %{conn: conn} do
  {_view, post} = open_editor(conn)
  stale_version = to_string(Blog.get_post!(post.id).lock_version)
  write_elsewhere(post, "from computer A")

  {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")

  render_change(view, "recover", %{
    "post" => %{
      "lock_version" => stale_version,
      "title" => post.title,
      "slug" => post.slug,
      "body_markdown" => "stale client body"
    }
  })

  send(view.pid, :autosave)
  render(view)

  assert Blog.get_post!(post.id).body_markdown == "from computer A"
  refute has_element?(view, "#conflict-banner")
  assert view |> element("#post-form") |> render() =~ "from computer A"
end
```

(A reconnect is a fresh mount server-side, so the test models it as a second `live/2` on the same conn — the first mount is only there to establish the pre-conflict version string a stale client would still be holding.)

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/newton_web/live/admin/post_editor_conflict_test.exs`
Expected: the two new tests FAIL with "no handle_event clause for recover" (or equivalent).

- [ ] **Step 3: Extract the validate pipeline into a helper**

`handle_event("validate", ...)` (~line 205) becomes a thin wrapper so `recover` can reuse it:

```elixir
def handle_event("validate", %{"post" => params}, socket) do
  {:noreply, apply_validate(socket, params)}
end
```

New private function with the exact body the event handler had (same logic, returns the socket):

```elixir
defp apply_validate(socket, params) do
  published? = not is_nil(socket.assigns.published_at)

  slug_locked =
    socket.assigns.slug_locked or published? or
      field_edited?(params, "slug", socket.assigns.slug_auto)

  excerpt_locked =
    socket.assigns.excerpt_locked or
      field_edited?(params, "excerpt", socket.assigns.excerpt_auto)

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

  socket
  |> assign(:form, form)
  |> assign(:slug_locked, slug_locked)
  |> assign(:slug_auto, slug_auto)
  |> assign(:excerpt_locked, excerpt_locked)
  |> assign(:excerpt_auto, excerpt_auto)
  |> track_save_state(params, published?)
end
```

- [ ] **Step 4: The recover handler**

Add alongside the other `handle_event` clauses:

```elixir
def handle_event("recover", %{"post" => params}, socket) do
  if params["lock_version"] == to_string(socket.assigns.post.lock_version) do
    {:noreply,
     socket
     |> apply_validate(params)
     |> assign(:editor_key, new_editor_key())}
  else
    {:noreply,
     put_flash(socket, :info, "Updated in another window — showing the latest version.")}
  end
end
```

(On match, the reconnected client's params are adopted exactly as a `validate` would, and the `editor_key` bump rebuilds CodeMirror from the recovered form value — the remount had rebuilt it from DB state. On mismatch nothing is adopted: the freshly mounted DB content stands, and no write can occur.)

- [ ] **Step 5: Wire the form**

In `render/1` (~line 526), add the recovery attribute and hidden version input:

```heex
<.form for={@form} id="post-form" phx-submit="save" phx-change="validate" phx-auto-recover="recover">
  <input type="hidden" name="post[lock_version]" value={@post.lock_version} />
```

(`@post.lock_version` is the version this window last synced with — `%Post{}` defaults it to 1 for new posts. `lock_version` is not in `cast/2`, so its presence in params never touches the changeset.)

- [ ] **Step 6: Run the conflict test file**

Run: `mix test test/newton_web/live/admin/post_editor_conflict_test.exs`
Expected: PASS (all eight).

- [ ] **Step 7: Run the full suite**

Run: `mix test`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/newton_web/live/admin/post_live/editor.ex test/newton_web/live/admin/post_editor_conflict_test.exs
git commit -m "Version-check form recovery on editor reconnect"
```

---

### Task 4: Precommit sweep

**Files:**
- Modify: whatever `mix precommit` flags (format, unused aliases, compile warnings).

- [ ] **Step 1: Run precommit**

Run: `mix precommit`
Expected: clean. Fix any formatting/warnings it reports (no rule-disabling without user authorization — project memory).

- [ ] **Step 2: Commit any fixes**

Only if precommit changed files:

```bash
git add -u
git commit -m "Appease precommit"
```
