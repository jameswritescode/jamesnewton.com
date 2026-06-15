# Post Admin Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Editable publish date (backdating), content-gated draft creation (no phantom drafts), render-then-strip excerpts, and URL-backed post-list filters.

**Architecture:** Four mostly-independent changes in the post admin: a `Newton.Markdown.excerpt/1` rewrite using MDEx's AST; a `Blog.list_posts/1` filter + coalesced sort with a URL-backed segmented control in `PostLive.Index`; a date input + `set_publish_date` event in the `PostLive.Editor` publish drawer; and a draft model where "New post" opens an in-memory editor that only inserts a row on the first autosave with content (removing the eager-create + discard-on-mount machinery).

**Tech Stack:** Phoenix 1.8 LiveView, Ecto/Postgres, MDEx.

---

## Context for the implementer

Read the spec first: `docs/superpowers/specs/2026-06-15-post-admin-improvements-design.md`.

**Current code (exact, as of this plan):**

- `lib/newton/blog.ex`:
  - `list_posts, do: Repo.all(from p in Post, order_by: [desc: p.published_at])`
  - `create_draft/0` (creates an "Untitled post" with `next_untitled_slug/0`),
    `discard_empty_untitled_drafts/0` (deletes empty untitled drafts),
    `next_untitled_slug/0`, `@untitled_title "Untitled post"`.
- `lib/newton/markdown.ex`: `excerpt/1` = `first_paragraph |> strip_markdown |> truncate`. `strip_markdown/1` regex only handles inline `[text](url)`, not reference links. `@excerpt_max_chars 200`.
- `lib/newton_web/live/admin/post_live/index.ex`: `mount` calls `discard_empty_untitled_drafts()` + `stream(:posts, list_posts())`; `new_post` event → `create_draft()` → `push_navigate` to `/edit`; `delete` event; "New post" is a `<button phx-click="new_post">`.
- `lib/newton_web/live/admin/post_live/editor.ex`: only `apply_action(:edit)`. `save/2` has one clause (`%Post{}` update). `handle_info(:autosave,…)` updates `socket.assigns.post`. `set_published/2` updates `published_at`. Publish drawer has Status text, "Publish now"/"Move to draft" buttons, reading time, "View on site", Delete.
- `lib/newton_web/router.ex`: `live "/posts", PostLive.Index, :index` and `live "/posts/:id/edit", PostLive.Editor, :edit` (no `/posts/new`).

**MDEx facts (verified):** `MDEx.parse_document!(md)` returns `%MDEx.Document{nodes: [...]}`. Reference links resolve when the **full** doc is parsed: `[Code School][1]` becomes a `%MDEx.Link{nodes: [%MDEx.Text{literal: "Code School"}], url: …}`. Container nodes have a `:nodes` list; `%MDEx.Text{}`/`%MDEx.Code{}` have `:literal`. Reference **definitions** (`[1]: …`) are not paragraph nodes, so they're naturally excluded.

**Rules:** TDD (failing test first). Test behaviors, not structure. No narrating comments. pnpm for assets (n/a here). `mix precommit` at the end. Verify with a real `mix test` before each commit (don't chain `mix test | tail && commit` — the pipe masks failures).

## File structure

| File | Responsibility | Action |
| --- | --- | --- |
| `lib/newton/markdown.ex` | AST-based excerpt | Modify |
| `lib/newton/blog.ex` | `list_posts/1` filter+sort; remove draft cleanup/create_draft | Modify |
| `lib/newton_web/live/admin/post_live/index.ex` | URL-backed filter; New post → /new | Modify |
| `lib/newton_web/live/admin/post_live/editor.ex` | publish date; `:new` + create-on-content | Modify |
| `lib/newton_web/router.ex` | add `/posts/new` | Modify |
| `test/newton/markdown_test.exs` | excerpt tests | Modify/Create |
| `test/newton/blog_test.exs` | filter/sort tests; drop discard test | Modify |
| `test/newton_web/live/admin/post_index_live_test.exs` | filter + new-post-nav tests | Modify |
| `test/newton_web/live/admin/post_editor_live_test.exs` | publish-date + draft-create tests | Modify |

---

## Task 1: Excerpt — render-then-strip via MDEx AST

**Files:**
- Modify: `lib/newton/markdown.ex`
- Test: `test/newton/markdown_test.exs`

- [ ] **Step 1: Write the failing test**

Check whether `test/newton/markdown_test.exs` exists (`ls test/newton/markdown_test.exs`). If it does, add these tests inside the module; if not, create it with this content:

```elixir
defmodule Newton.MarkdownTest do
  use ExUnit.Case, async: true
  alias Newton.Markdown

  test "excerpt strips reference-style links to their text" do
    md = """
    Moved to join the team at [Code School][1] and wear [pants][2].

    [1]: https://example.com
    [2]: https://example.com/pants
    """

    excerpt = Markdown.excerpt(md)
    assert excerpt == "Moved to join the team at Code School and wear pants."
    refute excerpt =~ "["
    refute excerpt =~ "]"
  end

  test "excerpt strips inline links, emphasis, and code to plain text" do
    md = "A **bold** word, some `code`, and a [link](https://x.com)."
    assert Markdown.excerpt(md) == "A bold word, some code, and a link."
  end

  test "excerpt uses only the first paragraph" do
    md = "First paragraph here.\n\nSecond paragraph should not appear."
    assert Markdown.excerpt(md) == "First paragraph here."
  end

  test "excerpt truncates long first paragraphs at a word boundary with an ellipsis" do
    long = String.duplicate("word ", 60) |> String.trim()
    excerpt = Markdown.excerpt(long)
    assert String.length(excerpt) <= 201
    assert String.ends_with?(excerpt, "…")
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/newton/markdown_test.exs`
Expected: FAIL — the reference-link test fails (current output keeps `[Code School][1]`).

- [ ] **Step 3: Rewrite `excerpt/1` and its helpers**

In `lib/newton/markdown.ex`, replace `excerpt/1`, `first_paragraph/1`, and `strip_markdown/1` with an AST-based implementation (keep `truncate/2` as-is):

```elixir
  @doc "Plain-text excerpt from the first paragraph, truncated at a word boundary."
  def excerpt(markdown) when is_binary(markdown) do
    markdown
    |> MDEx.parse_document!()
    |> first_paragraph_text()
    |> truncate(@excerpt_max_chars)
  end
```

Add these private helpers (and delete `first_paragraph/1` and `strip_markdown/1`):

```elixir
  defp first_paragraph_text(%MDEx.Document{nodes: nodes}) do
    case Enum.find(nodes, &match?(%MDEx.Paragraph{}, &1)) do
      nil -> ""
      paragraph -> paragraph |> node_text() |> normalize_ws()
    end
  end

  defp node_text(%MDEx.Text{literal: literal}), do: literal
  defp node_text(%MDEx.Code{literal: literal}), do: literal
  defp node_text(%MDEx.SoftBreak{}), do: " "
  defp node_text(%MDEx.LineBreak{}), do: " "
  defp node_text(%{nodes: nodes}) when is_list(nodes), do: Enum.map_join(nodes, "", &node_text/1)
  defp node_text(_), do: ""

  defp normalize_ws(text), do: text |> String.replace(~r/\s+/, " ") |> String.trim()
```

- [ ] **Step 4: Run it to verify it passes**

Run: `mix test test/newton/markdown_test.exs`
Expected: PASS — all excerpt tests green.

- [ ] **Step 5: Confirm callers still pass**

Run: `mix test test/newton/blog_test.exs test/newton_web/live/admin/post_editor_live_test.exs`
Expected: PASS — `Blog.Post` (excerpt derivation) and the editor (`excerpt_locked?`/excerpt autofill) use `excerpt/1` with an unchanged signature.

- [ ] **Step 6: Commit**

```bash
git add lib/newton/markdown.ex test/newton/markdown_test.exs
git commit -m "Derive post excerpts from the parsed markdown, not regex"
```

---

## Task 2: `Blog.list_posts/1` — filter + coalesced sort

**Files:**
- Modify: `lib/newton/blog.ex`
- Test: `test/newton/blog_test.exs`

- [ ] **Step 1: Write the failing tests**

Add to `test/newton/blog_test.exs` (inside the module):

```elixir
  test "list_posts/1 filters by status and sorts newest-first across drafts and published" do
    {:ok, _pub_old} =
      Blog.create_post(%{@valid | slug: "pub-old", published_at: ~U[2026-01-01 00:00:00Z]})

    {:ok, _pub_new} =
      Blog.create_post(%{@valid | slug: "pub-new", published_at: ~U[2026-03-01 00:00:00Z]})

    {:ok, draft} = Blog.create_post(%{@valid | slug: "a-draft", published_at: nil})

    all = Blog.list_posts(:all) |> Enum.map(& &1.slug)
    # newest-first: the just-created draft (inserted now) leads, then pub-new, pub-old
    assert all == ["a-draft", "pub-new", "pub-old"]

    assert Blog.list_posts(:drafts) |> Enum.map(& &1.slug) == ["a-draft"]
    assert Blog.list_posts(:published) |> Enum.map(& &1.slug) == ["pub-new", "pub-old"]
    assert Blog.list_posts() |> Enum.map(& &1.id) |> Enum.member?(draft.id)
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/newton/blog_test.exs`
Expected: FAIL — `list_posts/1` doesn't accept an argument / doesn't filter.

- [ ] **Step 3: Implement `list_posts/1`**

In `lib/newton/blog.ex`, replace:

```elixir
  def list_posts, do: Repo.all(from p in Post, order_by: [desc: p.published_at])
```

with:

```elixir
  @doc "Admin post list, optionally filtered by status, newest-first."
  def list_posts(filter \\ :all) do
    from(p in Post, order_by: [desc: coalesce(p.published_at, p.inserted_at)])
    |> filter_posts(filter)
    |> Repo.all()
  end

  defp filter_posts(query, :drafts), do: from(p in query, where: is_nil(p.published_at))
  defp filter_posts(query, :published), do: from(p in query, where: not is_nil(p.published_at))
  defp filter_posts(query, _all), do: query
```

- [ ] **Step 4: Run it to verify it passes**

Run: `mix test test/newton/blog_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/newton/blog.ex test/newton/blog_test.exs
git commit -m "Add status filter and newest-first sort to Blog.list_posts"
```

---

## Task 3: Posts index — URL-backed filter control

**Files:**
- Modify: `lib/newton_web/live/admin/post_live/index.ex`
- Test: `test/newton_web/live/admin/post_index_live_test.exs`

(Leaves the `new_post`/`discard` behavior alone — that changes in Task 5.)

- [ ] **Step 1: Write the failing tests**

Add to `test/newton_web/live/admin/post_index_live_test.exs`:

```elixir
  test "the drafts filter shows only drafts", %{conn: conn} do
    post_fixture(%{title: "Published", slug: "pub", published_at: ~U[2026-01-01 00:00:00Z]})
    post_fixture(%{title: "Draftee", slug: "draftee", published_at: nil})

    {:ok, _view, html} = live(conn, ~p"/admin/posts?filter=drafts")

    assert html =~ "Draftee"
    refute html =~ "Published"
  end

  test "the published filter shows only published", %{conn: conn} do
    post_fixture(%{title: "Published", slug: "pub", published_at: ~U[2026-01-01 00:00:00Z]})
    post_fixture(%{title: "Draftee", slug: "draftee", published_at: nil})

    {:ok, _view, html} = live(conn, ~p"/admin/posts?filter=published")

    assert html =~ "Published"
    refute html =~ "Draftee"
  end

  test "switching filters re-streams the list", %{conn: conn} do
    post_fixture(%{title: "Published", slug: "pub", published_at: ~U[2026-01-01 00:00:00Z]})
    post_fixture(%{title: "Draftee", slug: "draftee", published_at: nil})

    {:ok, view, _html} = live(conn, ~p"/admin/posts")
    html = view |> element(~s(a[href="/admin/posts?filter=drafts"])) |> render_click()

    assert html =~ "Draftee"
    refute html =~ "Published"
  end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `mix test test/newton_web/live/admin/post_index_live_test.exs`
Expected: FAIL — no filter param handling, no filter links.

- [ ] **Step 3: Add `handle_params` filtering + the segmented control**

In `lib/newton_web/live/admin/post_live/index.ex`, change `mount/3` to configure an empty stream (handle_params fills it):

```elixir
  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :posts, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filter = parse_filter(params["filter"])

    {:noreply,
     socket
     |> assign(:filter, filter)
     |> stream(:posts, Newton.Blog.list_posts(filter), reset: true)}
  end

  defp parse_filter("drafts"), do: :drafts
  defp parse_filter("published"), do: :published
  defp parse_filter(_), do: :all
```

(Remove the `discard_empty_untitled_drafts()` call from `mount` here — Task 5 deletes that function; doing it now is fine since the function still exists until Task 5. To keep this task self-contained, leave the call **in place** for now and let Task 5 remove it. So: keep `mount` as `{:ok, stream(socket, :posts, [])}` and do NOT call discard here.)

Add the segmented control in `render/1`, just below the header `<div class="mb-6 …">` block (which holds the title + New post button). Insert after that closing `</div>`:

```elixir
      <div class="mb-4 flex gap-1 text-[0.8rem]">
        <.filter_tab filter={@filter} value={:all} label="All" />
        <.filter_tab filter={@filter} value={:drafts} label="Drafts" />
        <.filter_tab filter={@filter} value={:published} label="Published" />
      </div>
```

Add the `filter_tab` function component (private) at the bottom of the module:

```elixir
  attr :filter, :atom, required: true
  attr :value, :atom, required: true
  attr :label, :string, required: true

  defp filter_tab(assigns) do
    ~H"""
    <.link
      patch={~p"/admin/posts?filter=#{@value}"}
      class={[
        "rounded-md px-3 py-1 no-underline",
        @filter == @value && "bg-(--admin-accent-soft) font-medium text-(--admin-accent)",
        @filter != @value && "text-(--admin-text-muted) hover:bg-(--admin-accent-soft)"
      ]}
    >
      {@label}
    </.link>
    """
  end
```

- [ ] **Step 4: Run them to verify they pass**

Run: `mix test test/newton_web/live/admin/post_index_live_test.exs`
Expected: PASS — filters work and switching re-streams. (The existing "New post creates a draft" test still passes here; it changes in Task 5.)

- [ ] **Step 5: Commit**

```bash
git add lib/newton_web/live/admin/post_live/index.ex test/newton_web/live/admin/post_index_live_test.exs
git commit -m "Add URL-backed All/Drafts/Published filter to the posts list"
```

---

## Task 4: Editable publish date in the publish drawer

**Files:**
- Modify: `lib/newton_web/live/admin/post_live/editor.ex`
- Test: `test/newton_web/live/admin/post_editor_live_test.exs`

- [ ] **Step 1: Write the failing tests**

Add to `test/newton_web/live/admin/post_editor_live_test.exs`:

```elixir
  test "setting a past publish date backdates the post", %{conn: conn} do
    {:ok, post} =
      Newton.Blog.create_post(%{
        title: "Live",
        slug: "backdate",
        body_markdown: "b",
        published_at: ~U[2026-06-01 12:00:00Z]
      })

    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")
    view |> element("button", "Settings") |> render_click()

    view
    |> element("#publish-date-form")
    |> render_change(%{"date" => "2020-03-15"})

    updated = Newton.Blog.get_post!(post.id)
    assert DateTime.to_date(updated.published_at) == ~D[2020-03-15]
    assert Newton.Blog.publish_status(updated.published_at) == :published
  end

  test "setting a future publish date schedules the post", %{conn: conn} do
    {:ok, post} =
      Newton.Blog.create_post(%{
        title: "Live",
        slug: "sched",
        body_markdown: "b",
        published_at: ~U[2026-06-01 12:00:00Z]
      })

    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")
    view |> element("button", "Settings") |> render_click()

    view |> element("#publish-date-form") |> render_change(%{"date" => "2999-01-01"})

    updated = Newton.Blog.get_post!(post.id)
    assert Newton.Blog.publish_status(updated.published_at) == :scheduled
  end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `mix test test/newton_web/live/admin/post_editor_live_test.exs`
Expected: FAIL — no `#publish-date-form` / `set_publish_date` handler.

- [ ] **Step 3: Add the `set_publish_date` handler**

In `lib/newton_web/live/admin/post_live/editor.ex`, add with the other `handle_event` clauses (e.g. after `unpublish`):

```elixir
  def handle_event("set_publish_date", %{"date" => date}, socket) do
    case Date.from_iso8601(date) do
      {:ok, date} ->
        {:noreply, set_published(socket, DateTime.new!(date, ~T[12:00:00]))}

      _ ->
        {:noreply, socket}
    end
  end
```

(`DateTime.new!/2` defaults to `"Etc/UTC"`, needs no tz database; `published_at` is `:utc_datetime`, and noon-UTC truncates cleanly to seconds.)

- [ ] **Step 4: Add the date input to the publish drawer**

In `render/1`'s publish drawer, replace the status block:

```elixir
        <div class="text-[0.78rem] text-(--admin-text-muted)">
          Status:
          <span class="font-medium text-(--admin-text)">{Blog.publish_status(@published_at)}</span>
        </div>
```

with the status block plus a date control shown when published/scheduled:

```elixir
        <div class="text-[0.78rem] text-(--admin-text-muted)">
          Status:
          <span class="font-medium text-(--admin-text)">{Blog.publish_status(@published_at)}</span>
        </div>

        <form :if={@published_at} id="publish-date-form" phx-change="set_publish_date">
          <label class="block text-[0.78rem] text-(--admin-text-muted)">
            Publish date
            <input
              type="date"
              name="date"
              value={Date.to_iso8601(DateTime.to_date(@published_at))}
              class="mt-1 w-full rounded-md border border-(--admin-border) bg-(--admin-surface) px-2 py-1 text-[0.8rem] text-(--admin-text) focus:outline-none"
            />
          </label>
        </form>
```

- [ ] **Step 5: Run them to verify they pass**

Run: `mix test test/newton_web/live/admin/post_editor_live_test.exs`
Expected: PASS — backdate and schedule both work.

- [ ] **Step 6: Commit**

```bash
git add lib/newton_web/live/admin/post_live/editor.ex test/newton_web/live/admin/post_editor_live_test.exs
git commit -m "Allow editing a post's publish date to backdate or schedule"
```

---

## Task 5: Draft model — create on first content

**Files:**
- Modify: `lib/newton_web/router.ex`, `lib/newton_web/live/admin/post_live/index.ex`, `lib/newton_web/live/admin/post_live/editor.ex`, `lib/newton/blog.ex`
- Test: `test/newton_web/live/admin/post_index_live_test.exs`, `test/newton_web/live/admin/post_editor_live_test.exs`, `test/newton/blog_test.exs`

This is the largest task: "New post" stops creating a row; the editor creates one on the first autosave that has content; the eager-create + cleanup code is removed.

- [ ] **Step 1: Write the failing tests (index nav + no phantom)**

In `test/newton_web/live/admin/post_index_live_test.exs`, **replace** the existing test `"New post creates a draft and opens the editor"` with:

```elixir
  test "New post opens the editor without creating a row", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/posts")

    {:error, {:live_redirect, %{to: path}}} =
      view |> element("a", "New post") |> render_click()

    assert path == ~p"/admin/posts/new"
    assert Newton.Blog.list_posts() == []
  end
```

If the file has a test `"untouched untitled drafts are discarded when the list loads"`, **delete it** (the mechanism is removed).

- [ ] **Step 2: Write the failing tests (editor create-on-content)**

In `test/newton_web/live/admin/post_editor_live_test.exs`, add:

```elixir
  test "a brand-new post creates no row until there is content", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

    # an autosave with no content creates nothing
    render_change(view, "validate", %{"post" => %{"title" => "", "body_markdown" => ""}})
    send(view.pid, :autosave)
    _ = :sys.get_state(view.pid)
    assert Newton.Blog.list_posts() == []
  end

  test "typing content into a new post creates it and moves to its edit URL", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

    render_change(view, "validate", %{
      "post" => %{"title" => "Fresh Post", "slug" => "", "body_markdown" => "Hello body"}
    })

    send(view.pid, :autosave)
    _ = :sys.get_state(view.pid)

    post = Newton.Blog.get_post_by_slug!("fresh-post")
    assert post.body_html =~ "Hello body"
    assert_patch(view, ~p"/admin/posts/#{post.id}/edit")
  end

  test "a body-only new post is created with a default title", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

    render_change(view, "validate", %{
      "post" => %{"title" => "", "slug" => "", "body_markdown" => "Just a body"}
    })

    send(view.pid, :autosave)
    _ = :sys.get_state(view.pid)

    [post] = Newton.Blog.list_posts()
    assert post.title == "Untitled post"
    assert post.body_html =~ "Just a body"
  end
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `mix test test/newton_web/live/admin/post_index_live_test.exs test/newton_web/live/admin/post_editor_live_test.exs`
Expected: FAIL — no `/admin/posts/new` route; New post still creates; editor has no `:new` action / create branch.

- [ ] **Step 4: Add the `/posts/new` route**

In `lib/newton_web/router.ex`, change:

```elixir
      live "/posts", PostLive.Index, :index
      live "/posts/:id/edit", PostLive.Editor, :edit
```

to:

```elixir
      live "/posts", PostLive.Index, :index
      live "/posts/new", PostLive.Editor, :new
      live "/posts/:id/edit", PostLive.Editor, :edit
```

- [ ] **Step 5: Make "New post" a navigation link (remove eager create)**

In `lib/newton_web/live/admin/post_live/index.ex`:

Change `mount/3` to (also drops the `discard_empty_untitled_drafts` call permanently):

```elixir
  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :posts, [])}
  end
```

Delete the `handle_event("new_post", …)` clause entirely.

Replace the "New post" `<button phx-click="new_post">…</button>` with:

```elixir
        <.link
          navigate={~p"/admin/posts/new"}
          class="rounded-md bg-(--admin-accent) px-3 py-1.5 text-[0.8rem] font-medium text-white no-underline hover:bg-(--admin-accent-hover)"
        >
          New post
        </.link>
```

- [ ] **Step 6: Add the editor `:new` action (in-memory form)**

In `lib/newton_web/live/admin/post_live/editor.ex`, add an `apply_action(:new, …)` clause above `apply_action(:edit, …)`:

```elixir
  defp apply_action(socket, :new, _params) do
    post = %Post{}

    socket
    |> assign(:page_title, "New post")
    |> assign(:post, post)
    |> assign(:published_at, nil)
    |> assign(:slug_locked, false)
    |> assign(:slug_auto, "")
    |> assign(:excerpt_locked, false)
    |> assign(:excerpt_auto, "")
    |> assign(:save_state, :saved)
    |> assign(:autosave_params, nil)
    |> assign(:form, to_form(Blog.change_post(post)))
  end
```

- [ ] **Step 7: Add create-on-content to autosave and manual save**

In `lib/newton_web/live/admin/post_live/editor.ex`, find `handle_info(:autosave, socket)`. Its body currently updates `socket.assigns.post`. Replace the **persist branch** so it dispatches on whether the post is new. Concretely, change the success path to call a new `persist_autosave/1`. Replace the whole `handle_info(:autosave, …)` with:

```elixir
  @impl true
  def handle_info(:autosave, socket) do
    if is_nil(socket.assigns.published_at) and socket.assigns.autosave_params do
      persist_autosave(socket, socket.assigns.post, socket.assigns.autosave_params)
    else
      {:noreply, socket}
    end
  end

  defp persist_autosave(socket, %Post{id: nil}, params) do
    if content?(params) do
      case Blog.create_post(backfill_new(params)) do
        {:ok, post} ->
          {:noreply,
           socket
           |> assign(:post, post)
           |> assign(:published_at, post.published_at)
           |> assign(:autosave_params, nil)
           |> assign(:autosave_timer, nil)
           |> assign(:save_state, :saved)
           |> push_patch(to: ~p"/admin/posts/#{post.id}/edit")}

        {:error, _changeset} ->
          {:noreply, assign(socket, :save_state, :error)}
      end
    else
      {:noreply, assign(socket, :save_state, :saved)}
    end
  end

  defp persist_autosave(socket, %Post{} = post, params) do
    case Blog.update_post(post, params) do
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
  end

  defp content?(params) do
    String.trim(params["title"] || "") != "" or String.trim(params["body_markdown"] || "") != ""
  end

  defp backfill_new(params) do
    if String.trim(params["title"] || "") == "" do
      params
      |> Map.put("title", "Untitled post")
      |> Map.put("slug", Blog.next_untitled_slug())
    else
      params
    end
  end
```

Add a `save/2` clause for a new post (place it above the existing `defp save(socket, %Post{} = post, params)`):

```elixir
  defp save(socket, %Post{id: nil}, params) do
    case Blog.create_post(backfill_new(params)) do
      {:ok, post} ->
        {:noreply,
         socket
         |> put_flash(:info, "Post saved")
         |> push_patch(to: ~p"/admin/posts/#{post.id}/edit")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end
```

- [ ] **Step 8: Remove the dead Blog functions**

In `lib/newton/blog.ex`, delete `create_draft/0` and `discard_empty_untitled_drafts/0`. Keep `next_untitled_slug/0` (used by `backfill_new`) and `@untitled_title` only if still referenced — if nothing else uses `@untitled_title` after deleting `discard_empty_untitled_drafts/0`, delete the attribute too (a compile warning will flag it; resolve by removing it).

In `test/newton/blog_test.exs`, delete the test `"discard_empty_untitled_drafts removes only untouched untitled drafts"`. Keep the `next_untitled_slug` test.

- [ ] **Step 9: Run all affected tests**

Run: `mix test test/newton/blog_test.exs test/newton_web/live/admin/post_index_live_test.exs test/newton_web/live/admin/post_editor_live_test.exs`
Expected: PASS — new-post nav, create-on-content (incl. body-only default title), no-phantom, and all prior editor/index/blog tests green.

- [ ] **Step 10: Confirm no stale references + clean compile**

Run: `mix compile --warnings-as-errors 2>&1 | tail -5` and `grep -rn "create_draft\|discard_empty_untitled" lib test`
Expected: clean compile; grep returns nothing.

- [ ] **Step 11: Commit**

```bash
git add lib/newton_web/router.ex lib/newton_web/live/admin/post_live/index.ex lib/newton_web/live/admin/post_live/editor.ex lib/newton/blog.ex test/newton/blog_test.exs test/newton_web/live/admin/post_index_live_test.exs test/newton_web/live/admin/post_editor_live_test.exs
git commit -m "Create draft posts on first content instead of eagerly"
```

---

## Task 6: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full precommit suite**

Run: `mix precommit`
Expected: PASS — compile `--warnings-as-errors`, format, Credo `--strict`, both test suites, Dialyzer 0 errors. Fix anything reported.

- [ ] **Step 2: Browser smoke (start a single dev server, then stop it after)**

Start one server (`mix phx.server`), then via Playwright (`assets/screenshot.mjs` pattern) or manually:
- `/admin/posts` → New post → lands on `/admin/posts/new`; the posts list count is unchanged. Dashboard shows no phantom draft.
- Type a title + body → after the pause it autosaves, URL becomes `/admin/posts/<id>/edit`, and it now appears in the list.
- Open a post → Settings → change the publish date → confirm it backdates (and a future date reads "scheduled").
- Posts list → All / Drafts / Published tabs filter correctly; `?filter=drafts` is in the URL.
- Stop the server when done (don't leave it running).

---

## Self-review notes

- **Spec coverage:** Section 1 publish date (Task 4); Section 2 draft model (Task 5); Section 3 excerpt (Task 1); Section 4 list filter+sort (Tasks 2–3). All four covered.
- **Ordering rationale:** isolated low-risk wins first (excerpt, list filter), then the publish-date UI, then the cross-cutting draft-model rework, then verification. Task 3 deliberately leaves `new_post`/cleanup intact so it stays self-contained; Task 5 removes them.
- **Names/types consistent:** `list_posts/1` (`:all|:drafts|:published`) defined in Task 2, used in Task 3; `set_publish_date` event + `#publish-date-form` id consistent between Task 4 code and tests; `persist_autosave/3`, `content?/1`, `backfill_new/1`, `apply_action(:new)`, route `/posts/new` consistent across Task 5 code and tests; `node_text/1`/`first_paragraph_text/1` in Task 1.
- **No placeholders:** every step has concrete code/commands. The one conditional (delete `@untitled_title` if unreferenced) is resolved by the compile-warning check in Task 5 Step 10.
- **Out of scope (per spec):** datetime precision, background scheduler, Reading/Photos filters.
