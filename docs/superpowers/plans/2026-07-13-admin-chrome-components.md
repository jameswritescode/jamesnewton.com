# Admin Chrome Components Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the admin's triplicated index markup and copied headers with four slot-based components: `page_header`, `section_header`, `list`, `list_item`.

**Architecture:** Pure render-layer refactor. The components join `NewtonWeb.Admin.Components` (where `button`/`drawer` live) and are consumed namespaced (`<Components.list>`). Five pages adopt them; zero behavior change anywhere.

**Tech Stack:** Phoenix 1.8 HEEx function components + slots. No JS, no CSS, no schema changes.

**Spec:** `docs/superpowers/specs/2026-07-13-admin-chrome-components-design.md`

## Global Constraints

- **Every existing admin LiveView test passes UNCHANGED.** That is the refactor's success criterion; needing to edit one is a red flag to stop and justify.
- **No narrating comments** (AGENTS.md).
- Component names exactly: `page_header`, `section_header`, `list`, `list_item` — consumed as `<Components.*>`.
- The extracted class strings are copied **verbatim** from the current templates (listed inside each component below); visual parity is the point.
- The `list` empty-state div id must be `"#{id}-empty"` (matches the existing `posts-empty` / `entries-empty` / `galleries-empty` ids).
- Tests assert component contracts (id wiring, link kind, slot placement), not exhaustive class lists.
- Finish the whole plan with `mix precommit`.

## File Structure

| File | Responsibility |
|---|---|
| `lib/newton_web/components/admin/components.ex` | + the four components |
| `test/newton_web/components/admin/components_test.exs` | + contract tests |
| `lib/newton_web/live/admin/post_live/index.ex` | adopt header + list |
| `lib/newton_web/live/admin/reading_live/index.ex` | adopt header + list |
| `lib/newton_web/live/admin/gallery_live/index.ex` | adopt header + list |
| `lib/newton_web/live/admin/dashboard_live.ex` | adopt header |
| `lib/newton_web/live/admin/media_live.ex` | adopt header + section headers |
| `lib/newton_web/live/admin/post_live/editor.ex` | adopt section header (Images) |

---

### Task 1: The four components

**Files:**
- Modify: `lib/newton_web/components/admin/components.ex` (append the four components before the module's final `end`)
- Test: `test/newton_web/components/admin/components_test.exs` (append)

**Interfaces:**
- Consumes: nothing new.
- Produces (later tasks rely on these exactly):
  `page_header(title:, inner_block?)`;
  `section_header(title:)`;
  `list(id:, empty:, inner_block)`;
  `list_item(id:, navigate: nil | url, patch: nil | url, leading?, inner_block, inline?, meta*)`.

- [ ] **Step 1: Write the failing tests**

Append to `test/newton_web/components/admin/components_test.exs` (inside the module; it already has `use NewtonWeb.ConnCase, async: true` and imports for `render_component` — add `import Phoenix.Component` and `import Phoenix.LiveViewTest` at the top of the module if not present):

```elixir
  defp h(template), do: rendered_to_string(template)

  test "page_header renders the title and right-aligned actions" do
    assigns = %{}

    html =
      h(~H"""
      <Components.page_header title="Posts">
        <button>New post</button>
      </Components.page_header>
      """)

    assert html =~ "Posts"
    assert html =~ "New post"
  end

  test "page_header works without actions" do
    assigns = %{}
    assert h(~H|<Components.page_header title="Dashboard" />|) =~ "Dashboard"
  end

  test "section_header renders an h2 with the title" do
    assigns = %{}
    html = h(~H|<Components.section_header title="Images" />|)
    assert html =~ "<h2"
    assert html =~ "Images"
  end

  test "list renders a stream container with a wired empty state" do
    assigns = %{}

    html =
      h(~H"""
      <Components.list id="things" empty="No things yet.">
        <div id="thing-1">one</div>
      </Components.list>
      """)

    assert html =~ ~s(id="things")
    assert html =~ ~s(phx-update="stream")
    assert html =~ ~s(id="things-empty")
    assert html =~ "No things yet."
    assert html =~ "one"
  end

  test "list_item links via navigate or patch and places all slots" do
    assigns = %{}

    navigate =
      h(~H"""
      <Components.list_item id="row-1" navigate="/admin/posts/1/edit">
        Title text
        <:leading><span>thumb</span></:leading>
        <:inline><span>author</span></:inline>
        <:meta><span>badge</span></:meta>
        <:meta><span>date</span></:meta>
      </Components.list_item>
      """)

    assert navigate =~ ~s(href="/admin/posts/1/edit")
    assert navigate =~ ~s(data-phx-link="redirect")
    assert navigate =~ "Title text"

    for piece <- ~w(thumb author badge date) do
      assert navigate =~ piece
    end

    patch =
      h(~H"""
      <Components.list_item id="row-2" patch="/admin/reading/2/edit">
        Entry
      </Components.list_item>
      """)

    assert patch =~ ~s(data-phx-link="patch")
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/newton_web/components/admin/components_test.exs`
Expected: FAIL — `page_header` etc. undefined.

- [ ] **Step 3: Implement**

Append inside `lib/newton_web/components/admin/components.ex`, before the final `end`:

```elixir
  attr :title, :string, required: true
  slot :inner_block

  def page_header(assigns) do
    ~H"""
    <div class="mb-6 flex items-center justify-between">
      <h1 class="text-[1.35rem] font-semibold tracking-tight">{@title}</h1>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :title, :string, required: true

  def section_header(assigns) do
    ~H"""
    <h2 class="mb-3 text-[0.78rem] uppercase tracking-wide text-(--admin-text-subtle)">
      {@title}
    </h2>
    """
  end

  attr :id, :string, required: true
  attr :empty, :string, required: true
  slot :inner_block, required: true

  def list(assigns) do
    ~H"""
    <div
      id={@id}
      phx-update="stream"
      class="overflow-hidden rounded-xl border border-(--admin-border)"
    >
      <div
        id={"#{@id}-empty"}
        class="hidden p-5 text-[0.85rem] text-(--admin-text-subtle) only:block"
      >
        {@empty}
      </div>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :id, :string, required: true
  attr :navigate, :string, default: nil
  attr :patch, :string, default: nil
  slot :leading
  slot :inner_block, required: true
  slot :inline
  slot :meta

  def list_item(assigns) do
    ~H"""
    <div
      id={@id}
      class="relative flex items-center gap-3 border-b border-(--admin-border) bg-(--admin-surface) px-4 py-3 last:border-b-0 hover:bg-(--admin-accent-soft)"
    >
      {render_slot(@leading)}
      <div class="flex min-w-0 flex-1 items-baseline gap-2">
        <.link
          {link_attrs(@navigate, @patch)}
          class="text-[0.9rem] font-medium text-(--admin-text) no-underline after:absolute after:inset-0"
        >
          {render_slot(@inner_block)}
        </.link>
        {render_slot(@inline)}
      </div>
      {render_slot(@meta)}
    </div>
    """
  end

  defp link_attrs(nil, nil), do: %{}
  defp link_attrs(nil, patch), do: %{patch: patch}
  defp link_attrs(navigate, _patch), do: %{navigate: navigate}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/newton_web/components/admin/components_test.exs`
Expected: all pass (existing drawer/button tests included).

- [ ] **Step 5: Commit**

```bash
git add lib/newton_web/components/admin/components.ex test/newton_web/components/admin/components_test.exs
git commit -m "Add page_header, section_header, and list/list_item admin components"
```

---

### Task 2: Posts index adopts

**Files:**
- Modify: `lib/newton_web/live/admin/post_live/index.ex` (the `render/1` header + list region only; filter tabs and everything else stay)

**Interfaces:**
- Consumes: Task 1's components (the module already aliases `Components`).
- Produces: nothing new.

- [ ] **Step 1: Replace the header and list markup**

Current header block:

```heex
      <div class="mb-6 flex items-center justify-between">
        <h1 class="text-[1.35rem] font-semibold tracking-tight">Posts</h1>
        <Components.button navigate={~p"/admin/posts/new"}>New post</Components.button>
      </div>
```

becomes:

```heex
      <Components.page_header title="Posts">
        <Components.button navigate={~p"/admin/posts/new"}>New post</Components.button>
      </Components.page_header>
```

Current list block (the `div#posts` through its closing tag) becomes:

```heex
      <Components.list id="posts" empty="No posts yet.">
        <Components.list_item
          :for={{id, post} <- @streams.posts}
          id={id}
          navigate={~p"/admin/posts/#{post.id}/edit"}
        >
          {post.title}
          <:meta>
            <Layouts.status_badge status={Newton.Blog.publish_status(post.published_at)} />
          </:meta>
          <:meta>
            <span class="hidden w-28 text-right text-[0.78rem] text-(--admin-text-subtle) sm:block">
              {format_date(post.published_at, on_nil: "—")}
            </span>
          </:meta>
        </Components.list_item>
      </Components.list>
```

(The one deliberate DOM change across all three indexes: the primary link now sits inside the component's `min-w-0 flex-1` wrapper instead of being `flex-1` itself. Click target is unchanged — the stretched link covers the row.)

- [ ] **Step 2: Run the page's tests unchanged**

Run: `mix test test/newton_web/live/admin/post_index_live_test.exs test/newton_web/live/admin/admin_shell_test.exs`
Expected: all pass with no test edits.

- [ ] **Step 3: Commit**

```bash
git add lib/newton_web/live/admin/post_live/index.ex
git commit -m "Posts index adopts the shared page header and list components"
```

---

### Task 3: Reading and photos indexes adopt

**Files:**
- Modify: `lib/newton_web/live/admin/reading_live/index.ex`
- Modify: `lib/newton_web/live/admin/gallery_live/index.ex`

**Interfaces:**
- Consumes: Task 1's components (both modules already alias `Components`; verify, add the alias if missing).

- [ ] **Step 1: Reading index**

Header:

```heex
      <Components.page_header title="Reading">
        <Components.button patch={~p"/admin/reading/new"}>Add entry</Components.button>
      </Components.page_header>
```

(`<.reading_summary counts={@status_counts} />` stays between header and list.)

List (replacing `div#entries` through its closing tag):

```heex
      <Components.list id="entries" empty="No reading entries yet.">
        <Components.list_item
          :for={{id, entry} <- @streams.entries}
          id={id}
          patch={~p"/admin/reading/#{entry.id}/edit"}
        >
          {entry.title}
          <:inline>
            <span class="truncate text-[0.8rem] text-(--admin-text-subtle)">{entry.author}</span>
          </:inline>
          <:meta>
            <Layouts.reading_badge status={entry.status} />
          </:meta>
          <:meta>
            <span class="w-36 text-right text-[0.78rem] text-(--admin-text-subtle)">
              {format_date(entry.finished_at, on_nil: "—")}
            </span>
          </:meta>
        </Components.list_item>
      </Components.list>
```

- [ ] **Step 2: Photos index**

Header:

```heex
      <Components.page_header title="Photos">
        <Components.button patch={~p"/admin/photos/new"}>Add gallery</Components.button>
      </Components.page_header>
```

List (replacing `div#galleries` through its closing tag):

```heex
      <Components.list id="galleries" empty="No galleries yet.">
        <Components.list_item
          :for={{id, group} <- @streams.galleries}
          id={id}
          navigate={~p"/admin/photos/#{group.id}"}
        >
          <:leading>
            <div class="size-10 shrink-0 overflow-hidden rounded-md bg-(--admin-bg)">
              <img
                :if={cover = List.first(group.photos)}
                src={Gallery.thumb_url(cover)}
                alt=""
                class="size-full object-cover"
              />
            </div>
          </:leading>
          {group.title}
          <:meta>
            <span class="text-[0.78rem] text-(--admin-text-subtle)">
              {length(group.photos)} photo{if length(group.photos) == 1, do: "", else: "s"}
            </span>
          </:meta>
          <:meta>
            <span class="w-36 text-right text-[0.78rem] text-(--admin-text-subtle)">
              {format_date(group.taken_on, on_nil: "—")}
            </span>
          </:meta>
        </Components.list_item>
      </Components.list>
```

- [ ] **Step 3: Run both pages' tests unchanged**

Run: `mix test test/newton_web/live/admin/reading_live_test.exs test/newton_web/live/admin/gallery_index_live_test.exs`
Expected: all pass with no test edits.

- [ ] **Step 4: Commit**

```bash
git add lib/newton_web/live/admin/reading_live/index.ex lib/newton_web/live/admin/gallery_live/index.ex
git commit -m "Reading and photos indexes adopt the shared list components"
```

---

### Task 4: Headers everywhere else + full gate

**Files:**
- Modify: `lib/newton_web/live/admin/dashboard_live.ex`
- Modify: `lib/newton_web/live/admin/media_live.ex`
- Modify: `lib/newton_web/live/admin/post_live/editor.ex`

**Interfaces:**
- Consumes: `page_header`, `section_header`. Dashboard and media must gain `alias NewtonWeb.Admin.Components` if absent.

- [ ] **Step 1: Dashboard**

`<h1 class="mb-6 text-[1.35rem] font-semibold tracking-tight">Dashboard</h1>`
becomes `<Components.page_header title="Dashboard" />`.

- [ ] **Step 2: Media**

The `h1` becomes `<Components.page_header title="Media" />`. Each of the two
section `h2`s (`Orphaned files`, `Missing files`) becomes
`<Components.section_header title="Orphaned files" />` /
`<Components.section_header title="Missing files" />` (delete the raw `h2`
markup they replace; the `mb-3` spacing lives in the component).

- [ ] **Step 3: Editor Images heading**

In `lib/newton_web/live/admin/post_live/editor.ex`, the Images section's

```heex
        <h2 class="mb-3 text-[0.78rem] uppercase tracking-wide text-(--admin-text-subtle)">
          Images
        </h2>
```

becomes `<Components.section_header title="Images" />`. The Excerpt `<label>`
is NOT touched (it's a label, not a heading — spec-noted divergence).

- [ ] **Step 4: Run the affected suites unchanged, then the full gate**

Run: `mix test test/newton_web/live/admin/`
Expected: all pass with no test edits.

Run: `mix precommit`
Expected: clean.

- [ ] **Step 5: Commit**

```bash
git add lib/newton_web/live/admin/dashboard_live.ex lib/newton_web/live/admin/media_live.ex lib/newton_web/live/admin/post_live/editor.ex
git commit -m "Adopt shared page and section headers across the admin"
```

---

## Post-plan notes

- James tophats visual parity across the five pages before any deploy.
- Deploy scope reminder: `fly deploy` ships the working tree; confirm scope before deploying.
