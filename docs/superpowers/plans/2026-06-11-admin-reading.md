# Admin Reading Section Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an admin Reading section — a finished-vs-in-progress summary visual, a list of reading entries with status badges, and a URL-backed, right-hand slide-over drawer for creating and editing entries.

**Architecture:** A single LiveView (`NewtonWeb.Admin.ReadingLive.Index`) renders a finished-vs-in-progress summary (two server-rendered stacked bars — Books and Audio — built from grouped status counts, no JS charting lib), the list as a LiveView stream, and an add/edit drawer whose open/close state is driven by the route (`/admin/reading/new`, `/admin/reading/:id/edit`) via `live_action` + `handle_params`, mirroring the existing Posts editor. The `Newton.Reading` context gains the CRUD + grouped-count functions the page needs. No schema change — the `reading_entries` table and `Newton.Reading.Entry` schema already exist.

**Tech Stack:** Phoenix 1.8 LiveView, Ecto/Postgres, the admin token-driven theme (`assets/css/admin.css`), `Phoenix.Component.to_form/2` + core `<.input>`.

---

## Context for the implementer

The Reading groundwork already exists and must be reused, not duplicated:

- **Schema** `lib/newton/reading/entry.ex` — fields: `title`, `author`, `link`, `note` (all `:string`), `status` (`Ecto.Enum` of `[:reading, :read, :listening, :listened]`), `finished_at` (`:date`). `changeset/2` casts all six and `validate_required([:title, :author, :status])`.
- **Context** `lib/newton/reading.ex` — already has `create_entry/1`, `list_entries/0` (orders `desc: finished_at`), `count_entries/0`, `count_in_progress/0`, `recent_finished/1`, `verb/1`. This plan ADDS `get_entry!/1`, `update_entry/2`, `delete_entry/1`, `change_entry/2`, and `status_counts/0` (a map of each status to its count, for the summary bars).
- **Patterns to mirror:**
  - List view: `lib/newton_web/live/admin/post_live/index.ex` (stream + empty-state row + badge + per-row link).
  - URL-backed editor + drawer: `lib/newton_web/live/admin/post_live/editor.ex` (`handle_params` → `apply_action`, drawer markup, `phx-window-keydown`/`phx-key="Escape"`).
  - Badge + nav: `lib/newton_web/components/admin/layouts.ex` (`status_badge/1`, the `@built` list that activates nav links).
  - Routes: `lib/newton_web/router.ex` (the `live_session :admin` block).
  - LiveView test conventions: `test/newton_web/live/admin/post_editor_live_test.exs` (`log_in_user(user_fixture())` setup, `form/2` + `render_submit/render_change`, `assert_patch`, element-ID assertions).

**Design decisions locked for this plan:**
- Drawer is **URL-backed** (refresh-survivable, deep-linkable).
- **No inline status toggle** on rows — status is changed inside the drawer.
- **One drawer, two modes** (new vs edit) sharing the same form markup.

**Project rules that apply:** TDD (failing test first). Don't add narrating comments — prefer well-named functions; reserve comments for genuine "why". Run `mix precommit` at the end and fix everything it reports.

## File structure

| File | Responsibility | Action |
| --- | --- | --- |
| `lib/newton/reading.ex` | Reading context — add admin CRUD | Modify |
| `test/newton/reading_test.exs` | Context tests — add CRUD coverage | Modify |
| `lib/newton_web/components/admin/layouts.ex` | Add `reading_badge/1`; activate `:reading` in nav | Modify |
| `lib/newton_web/router.ex` | Add three `/admin/reading*` routes | Modify |
| `lib/newton_web/live/admin/reading_live/index.ex` | Summary bars + list + URL-backed add/edit drawer | Create |
| `test/newton_web/live/admin/reading_live_test.exs` | LiveView tests for list/create/edit/delete/escape | Create |

---

## Task 1: Reading context CRUD

**Files:**
- Modify: `lib/newton/reading.ex`
- Test: `test/newton/reading_test.exs`

- [ ] **Step 1: Write the failing tests**

Append these tests inside the `Newton.ReadingTest` module in `test/newton/reading_test.exs` (before the final `end`):

```elixir
  test "get_entry!/1 returns the entry with the given id" do
    {:ok, entry} = Reading.create_entry(%{title: "T", author: "A", status: :read})
    assert Reading.get_entry!(entry.id).id == entry.id
  end

  test "update_entry/2 updates the given fields" do
    {:ok, entry} = Reading.create_entry(%{title: "T", author: "A", status: :reading})
    {:ok, updated} = Reading.update_entry(entry, %{title: "T2", status: :read})
    assert updated.title == "T2"
    assert updated.status == :read
  end

  test "delete_entry/1 removes the entry" do
    {:ok, entry} = Reading.create_entry(%{title: "T", author: "A", status: :read})
    {:ok, _} = Reading.delete_entry(entry)
    assert_raise Ecto.NoResultsError, fn -> Reading.get_entry!(entry.id) end
  end

  test "change_entry/1 returns a changeset" do
    {:ok, entry} = Reading.create_entry(%{title: "T", author: "A", status: :read})
    assert %Ecto.Changeset{} = Reading.change_entry(entry)
  end

  test "status_counts/0 returns a count per status, zero-filled" do
    {:ok, _} = Reading.create_entry(%{title: "A", author: "x", status: :read})
    {:ok, _} = Reading.create_entry(%{title: "B", author: "y", status: :read})
    {:ok, _} = Reading.create_entry(%{title: "C", author: "z", status: :reading})

    assert Reading.status_counts() == %{read: 2, reading: 1, listened: 0, listening: 0}
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/newton/reading_test.exs`
Expected: FAIL — `Reading.get_entry!/1` (and the other four) are undefined.

- [ ] **Step 3: Add the CRUD functions**

In `lib/newton/reading.ex`, add these functions inside the module (e.g. right after `create_entry/1`):

```elixir
  def get_entry!(id), do: Repo.get!(Entry, id)

  def update_entry(%Entry{} = entry, attrs) do
    entry |> Entry.changeset(attrs) |> Repo.update()
  end

  def delete_entry(%Entry{} = entry), do: Repo.delete(entry)

  def change_entry(%Entry{} = entry, attrs \\ %{}) do
    Entry.changeset(entry, attrs)
  end

  @statuses [:reading, :read, :listening, :listened]

  def status_counts do
    counted =
      Entry
      |> group_by([e], e.status)
      |> select([e], {e.status, count(e.id)})
      |> Repo.all()
      |> Map.new()

    Map.new(@statuses, fn status -> {status, Map.get(counted, status, 0)} end)
  end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/newton/reading_test.exs`
Expected: PASS — all reading context tests green.

- [ ] **Step 5: Commit**

```bash
git add lib/newton/reading.ex test/newton/reading_test.exs
git commit -m "Add reading context CRUD for the admin"
```

---

## Task 2: Reading status badge component

**Files:**
- Modify: `lib/newton_web/components/admin/layouts.ex`

A pill badge for a reading entry's status. In-progress states (`:reading`, `:listening`) get the filled accent treatment; finished states (`:read`, `:listened`) get the muted outline — same visual language as `status_badge/1`.

- [ ] **Step 1: Add the component**

In `lib/newton_web/components/admin/layouts.ex`, add this function after the existing `status_badge/1` function (before the module's final `end`):

```elixir
  @doc "A pill badge for a reading entry's status."
  attr :status, :atom, required: true

  def reading_badge(assigns) do
    ~H"""
    <span class={[
      "rounded-full px-2 py-0.5 text-[0.7rem] font-medium",
      @status in [:reading, :listening] && "bg-(--admin-accent-soft) text-(--admin-accent)",
      @status in [:read, :listened] && "border border-(--admin-border-strong) text-(--admin-text-subtle)"
    ]}>
      {@status}
    </span>
    """
  end
```

- [ ] **Step 2: Verify it compiles**

Run: `mix compile --warnings-as-errors`
Expected: compiles with no warnings (the new `def` is public, so no "unused" warning even before it's referenced).

- [ ] **Step 3: Commit**

```bash
git add lib/newton_web/components/admin/layouts.ex
git commit -m "Add a reading status badge component"
```

---

## Task 3: Reading list view, routes, and nav activation

**Files:**
- Create: `lib/newton_web/live/admin/reading_live/index.ex`
- Modify: `lib/newton_web/router.ex`
- Modify: `lib/newton_web/components/admin/layouts.ex`
- Test: `test/newton_web/live/admin/reading_live_test.exs`

This task delivers the list at `/admin/reading`. The template already references the `/admin/reading/new` and `/admin/reading/:id/edit` patch routes (so all three routes are added now for verified-route compilation), but the drawer itself arrives in Task 4.

- [ ] **Step 1: Write the failing test**

Create `test/newton_web/live/admin/reading_live_test.exs`:

```elixir
defmodule NewtonWeb.Admin.ReadingLiveTest do
  use NewtonWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Newton.AccountsFixtures

  alias Newton.Reading

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture())}
  end

  defp entry_fixture(attrs \\ %{}) do
    {:ok, entry} =
      attrs
      |> Enum.into(%{
        title: "A Book",
        author: "An Author",
        status: :read,
        finished_at: ~D[2026-01-01]
      })
      |> Reading.create_entry()

    entry
  end

  test "lists existing entries", %{conn: conn} do
    entry = entry_fixture(%{title: "Dune"})
    {:ok, view, _html} = live(conn, ~p"/admin/reading")
    assert has_element?(view, "#entries-#{entry.id}", "Dune")
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `mix test test/newton_web/live/admin/reading_live_test.exs`
Expected: FAIL — no route for `/admin/reading` (the LiveView and route don't exist yet).

- [ ] **Step 3: Add the three routes**

In `lib/newton_web/router.ex`, inside the `live_session :admin` block, add the reading routes after the post routes:

```elixir
      live "/posts/:id/edit", PostLive.Editor, :edit
      live "/reading", ReadingLive.Index, :index
      live "/reading/new", ReadingLive.Index, :new
      live "/reading/:id/edit", ReadingLive.Index, :edit
```

- [ ] **Step 4: Activate the Reading nav link**

In `lib/newton_web/components/admin/layouts.ex`, add `:reading` to the `@built` list:

```elixir
  @built [:dashboard, :posts, :reading]
```

- [ ] **Step 5: Create the list LiveView**

Create `lib/newton_web/live/admin/reading_live/index.ex`:

```elixir
defmodule NewtonWeb.Admin.ReadingLive.Index do
  use NewtonWeb, :live_view

  alias NewtonWeb.Admin.Layouts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Reading")
     |> stream(:entries, Newton.Reading.list_entries())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current={:reading}>
      <div class="mb-6 flex items-center justify-between">
        <h1 class="text-[1.35rem] font-semibold tracking-tight">Reading</h1>
        <.link
          patch={~p"/admin/reading/new"}
          class="rounded-md bg-(--admin-accent) px-3 py-1.5 text-[0.8rem] font-medium text-white no-underline hover:bg-(--admin-accent-hover)"
        >
          Add entry
        </.link>
      </div>

      <div
        id="entries"
        phx-update="stream"
        class="overflow-hidden rounded-xl border border-(--admin-border)"
      >
        <div
          id="entries-empty"
          class="hidden p-5 text-[0.85rem] text-(--admin-text-subtle) only:block"
        >
          No reading entries yet.
        </div>
        <div
          :for={{id, entry} <- @streams.entries}
          id={id}
          class="flex items-center gap-3 border-b border-(--admin-border) bg-(--admin-surface) px-4 py-3 last:border-b-0 hover:bg-(--admin-accent-soft)"
        >
          <.link
            patch={~p"/admin/reading/#{entry.id}/edit"}
            class="flex-1 text-[0.9rem] font-medium text-(--admin-text) no-underline"
          >
            {entry.title}
          </.link>
          <span class="w-32 truncate text-[0.8rem] text-(--admin-text-subtle)">{entry.author}</span>
          <Layouts.reading_badge status={entry.status} />
          <span class="w-24 text-right text-[0.78rem] text-(--admin-text-subtle)">
            {format_date(entry.finished_at)}
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

- [ ] **Step 6: Run the test to verify it passes**

Run: `mix test test/newton_web/live/admin/reading_live_test.exs`
Expected: PASS — the list renders the entry row.

- [ ] **Step 7: Commit**

```bash
git add lib/newton_web/live/admin/reading_live/index.ex lib/newton_web/router.ex lib/newton_web/components/admin/layouts.ex test/newton_web/live/admin/reading_live_test.exs
git commit -m "Add the admin reading list view and routes"
```

---

## Task 4: URL-backed add/edit drawer

**Files:**
- Modify: `lib/newton_web/live/admin/reading_live/index.ex`
- Test: `test/newton_web/live/admin/reading_live_test.exs`

Adds the finished-vs-in-progress summary bars and the slide-over drawer driven by `live_action`: `/admin/reading/new` opens an empty form, `/admin/reading/:id/edit` opens a pre-filled one. Save creates or updates and patches back to the list; Cancel/×/Escape patch back without saving. The summary (two stacked bars — Books: read vs reading; Audio: listened vs listening) is server-rendered from `Reading.status_counts/0`, kept in sync via `refresh_entries/1`, with no JS charting library (per project asset rules).

- [ ] **Step 1: Write the failing tests**

Append these tests to `test/newton_web/live/admin/reading_live_test.exs` (inside the module, before the final `end`):

```elixir
  test "renders the finished-vs-in-progress summary", %{conn: conn} do
    entry_fixture(%{title: "Done", status: :read})
    entry_fixture(%{title: "Reading now", status: :reading, finished_at: nil})

    {:ok, view, _html} = live(conn, ~p"/admin/reading")

    assert has_element?(view, "#reading-summary", "1 read · 1 reading")
  end

  test "Add entry opens the drawer in new mode", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/reading")

    view |> element("a", "Add entry") |> render_click()

    assert_patch(view, ~p"/admin/reading/new")
    assert has_element?(view, "#reading-drawer #reading-form")
  end

  test "creates an entry and shows it in the list", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/reading/new")

    view
    |> form("#reading-form", entry: %{title: "New Book", author: "Auth", status: :reading})
    |> render_submit()

    assert_patch(view, ~p"/admin/reading")
    assert has_element?(view, "#entries", "New Book")
    assert Enum.any?(Reading.list_entries(), &(&1.title == "New Book"))
  end

  test "shows validation errors on invalid submit", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/reading/new")

    html =
      view
      |> form("#reading-form", entry: %{title: "", author: "", status: :reading})
      |> render_submit()

    assert html =~ "can&#39;t be blank"
  end

  test "edits an existing entry", %{conn: conn} do
    entry = entry_fixture(%{title: "Old Title"})
    {:ok, view, _html} = live(conn, ~p"/admin/reading/#{entry.id}/edit")

    view
    |> form("#reading-form", entry: %{title: "Updated Title"})
    |> render_submit()

    assert_patch(view, ~p"/admin/reading")
    assert Reading.get_entry!(entry.id).title == "Updated Title"
  end

  test "Escape closes the drawer", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/reading/new")
    assert has_element?(view, "#reading-drawer")

    view |> element("#reading-drawer") |> render_keydown(%{"key" => "Escape"})

    assert_patch(view, ~p"/admin/reading")
    refute has_element?(view, "#reading-drawer")
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/newton_web/live/admin/reading_live_test.exs`
Expected: FAIL — `#reading-summary` / `#reading-drawer` / `#reading-form` don't exist; `/admin/reading/new` renders the list without a drawer.

- [ ] **Step 3: Implement the drawer**

Replace the entire contents of `lib/newton_web/live/admin/reading_live/index.ex` with:

```elixir
defmodule NewtonWeb.Admin.ReadingLive.Index do
  use NewtonWeb, :live_view

  alias Newton.Reading
  alias Newton.Reading.Entry
  alias NewtonWeb.Admin.Layouts

  @status_options [
    {"Reading", :reading},
    {"Read", :read},
    {"Listening", :listening},
    {"Listened", :listened}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:status_options, @status_options)
     |> assign(:status_counts, Reading.status_counts())
     |> stream(:entries, Reading.list_entries())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Reading")
    |> assign(:drawer_open, false)
    |> assign(:entry, nil)
    |> assign(:form, nil)
  end

  defp apply_action(socket, :new, _params) do
    entry = %Entry{status: :reading}

    socket
    |> assign(:page_title, "New entry")
    |> assign(:drawer_open, true)
    |> assign(:entry, entry)
    |> assign(:form, to_form(Reading.change_entry(entry)))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    entry = Reading.get_entry!(id)

    socket
    |> assign(:page_title, "Edit entry")
    |> assign(:drawer_open, true)
    |> assign(:entry, entry)
    |> assign(:form, to_form(Reading.change_entry(entry)))
  end

  @impl true
  def handle_event("validate", %{"entry" => params}, socket) do
    form =
      socket.assigns.entry
      |> Reading.change_entry(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"entry" => params}, socket) do
    save(socket, socket.assigns.entry, params)
  end

  def handle_event("close_drawer", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/reading")}
  end

  defp save(socket, %Entry{id: nil}, params) do
    case Reading.create_entry(params) do
      {:ok, _entry} ->
        {:noreply,
         socket
         |> put_flash(:info, "Entry added")
         |> refresh_entries()
         |> push_patch(to: ~p"/admin/reading")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save(socket, %Entry{} = entry, params) do
    case Reading.update_entry(entry, params) do
      {:ok, _entry} ->
        {:noreply,
         socket
         |> put_flash(:info, "Entry saved")
         |> refresh_entries()
         |> push_patch(to: ~p"/admin/reading")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp refresh_entries(socket) do
    socket
    |> stream(:entries, Reading.list_entries(), reset: true)
    |> assign(:status_counts, Reading.status_counts())
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current={:reading}>
      <div class="mb-6 flex items-center justify-between">
        <h1 class="text-[1.35rem] font-semibold tracking-tight">Reading</h1>
        <.link
          patch={~p"/admin/reading/new"}
          class="rounded-md bg-(--admin-accent) px-3 py-1.5 text-[0.8rem] font-medium text-white no-underline hover:bg-(--admin-accent-hover)"
        >
          Add entry
        </.link>
      </div>

      <.reading_summary counts={@status_counts} />

      <div
        id="entries"
        phx-update="stream"
        class="overflow-hidden rounded-xl border border-(--admin-border)"
      >
        <div
          id="entries-empty"
          class="hidden p-5 text-[0.85rem] text-(--admin-text-subtle) only:block"
        >
          No reading entries yet.
        </div>
        <div
          :for={{id, entry} <- @streams.entries}
          id={id}
          class="flex items-center gap-3 border-b border-(--admin-border) bg-(--admin-surface) px-4 py-3 last:border-b-0 hover:bg-(--admin-accent-soft)"
        >
          <.link
            patch={~p"/admin/reading/#{entry.id}/edit"}
            class="flex-1 text-[0.9rem] font-medium text-(--admin-text) no-underline"
          >
            {entry.title}
          </.link>
          <span class="w-32 truncate text-[0.8rem] text-(--admin-text-subtle)">{entry.author}</span>
          <Layouts.reading_badge status={entry.status} />
          <span class="w-24 text-right text-[0.78rem] text-(--admin-text-subtle)">
            {format_date(entry.finished_at)}
          </span>
        </div>
      </div>

      <.reading_drawer :if={@drawer_open} form={@form} entry={@entry} status_options={@status_options} />
    </Layouts.admin>
    """
  end

  attr :counts, :map, required: true

  defp reading_summary(assigns) do
    ~H"""
    <div id="reading-summary" class="mb-6 rounded-xl border border-(--admin-border) bg-(--admin-surface) p-4">
      <.reading_bar
        label="Books"
        finished={@counts.read}
        in_progress={@counts.reading}
        finished_label="read"
        in_progress_label="reading"
      />
      <.reading_bar
        label="Audio"
        finished={@counts.listened}
        in_progress={@counts.listening}
        finished_label="listened"
        in_progress_label="listening"
      />
      <div class="mt-3 flex items-center gap-4 text-[0.72rem] text-(--admin-text-subtle)">
        <span class="flex items-center gap-1.5">
          <span class="size-2.5 rounded-sm bg-(--admin-accent)"></span> finished
        </span>
        <span class="flex items-center gap-1.5">
          <span class="size-2.5 rounded-sm bg-(--admin-accent-soft)"></span> in progress
        </span>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :finished, :integer, required: true
  attr :in_progress, :integer, required: true
  attr :finished_label, :string, required: true
  attr :in_progress_label, :string, required: true

  defp reading_bar(assigns) do
    assigns = assign(assigns, :total, assigns.finished + assigns.in_progress)

    ~H"""
    <div class="mb-3 last:mb-0">
      <div class="mb-1 flex items-center justify-between text-[0.78rem]">
        <span class="font-medium text-(--admin-text)">{@label}</span>
        <span class="text-(--admin-text-subtle)">
          {@finished} {@finished_label} · {@in_progress} {@in_progress_label}
        </span>
      </div>
      <div class="flex h-2.5 overflow-hidden rounded-full bg-(--admin-bg)">
        <div
          :if={@total > 0}
          class="bg-(--admin-accent)"
          style={"width: #{percent(@finished, @total)}%"}
        >
        </div>
        <div
          :if={@total > 0}
          class="bg-(--admin-accent-soft)"
          style={"width: #{percent(@in_progress, @total)}%"}
        >
        </div>
      </div>
    </div>
    """
  end

  defp percent(part, total), do: round(part / total * 100)

  attr :form, :map, required: true
  attr :entry, :map, required: true
  attr :status_options, :list, required: true

  defp reading_drawer(assigns) do
    ~H"""
    <div
      id="reading-drawer"
      phx-window-keydown="close_drawer"
      phx-key="Escape"
      class="fixed inset-y-0 right-0 z-20 flex w-80 flex-col gap-4 overflow-y-auto border-l border-(--admin-border) bg-(--admin-sidebar) p-5 shadow-xl"
    >
      <div class="flex items-center justify-between">
        <span class="text-[0.9rem] font-semibold">
          {if @entry.id, do: "Edit entry", else: "New entry"}
        </span>
        <.link
          patch={~p"/admin/reading"}
          aria-label="Close"
          class="text-(--admin-text-subtle) hover:text-(--admin-text)"
        >
          <.icon name="hero-x-mark-mini" class="size-5" />
        </.link>
      </div>

      <.form
        for={@form}
        id="reading-form"
        phx-change="validate"
        phx-submit="save"
        class="flex flex-col gap-3"
      >
        <.input field={@form[:title]} type="text" label="Title" />
        <.input field={@form[:author]} type="text" label="Author" />
        <.input field={@form[:link]} type="text" label="Link" />
        <.input field={@form[:status]} type="select" label="Status" options={@status_options} />
        <.input field={@form[:finished_at]} type="date" label="Finished on" />
        <.input field={@form[:note]} type="textarea" label="Note" rows="3" />

        <div class="mt-2 flex items-center justify-end gap-2">
          <.link
            patch={~p"/admin/reading"}
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
    </div>
    """
  end

  defp format_date(nil), do: "—"
  defp format_date(%Date{} = d), do: Calendar.strftime(d, "%b %-d, %Y")
end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/newton_web/live/admin/reading_live_test.exs`
Expected: PASS — all tests (list + summary + the five drawer tests) green.

- [ ] **Step 5: Commit**

```bash
git add lib/newton_web/live/admin/reading_live/index.ex test/newton_web/live/admin/reading_live_test.exs
git commit -m "Add the URL-backed reading add/edit drawer"
```

---

## Task 5: Delete from the drawer

**Files:**
- Modify: `lib/newton_web/live/admin/reading_live/index.ex`
- Test: `test/newton_web/live/admin/reading_live_test.exs`

Editing an existing entry gets a Delete affordance (with a confirm). Deleting removes the row and patches back to the list.

- [ ] **Step 1: Write the failing test**

Append to `test/newton_web/live/admin/reading_live_test.exs` (before the final `end`):

```elixir
  test "deletes an entry from the drawer", %{conn: conn} do
    entry = entry_fixture()
    {:ok, view, _html} = live(conn, ~p"/admin/reading/#{entry.id}/edit")

    view |> element("#reading-drawer button", "Delete") |> render_click()

    assert_patch(view, ~p"/admin/reading")
    assert_raise Ecto.NoResultsError, fn -> Reading.get_entry!(entry.id) end
  end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `mix test test/newton_web/live/admin/reading_live_test.exs`
Expected: FAIL — there is no Delete button in the drawer and no `"delete"` event handler.

- [ ] **Step 3: Add the delete handler**

In `lib/newton_web/live/admin/reading_live/index.ex`, add a `delete` handler immediately after the `close_drawer` handler (keeping all `handle_event/3` clauses contiguous):

```elixir
  def handle_event("delete", %{"id" => id}, socket) do
    entry = Reading.get_entry!(id)
    {:ok, _} = Reading.delete_entry(entry)

    {:noreply,
     socket
     |> put_flash(:info, "Entry deleted")
     |> refresh_entries()
     |> push_patch(to: ~p"/admin/reading")}
  end
```

`refresh_entries/1` (added in Task 4) re-streams the list and recomputes `status_counts`, so the summary bars stay in sync after a delete.

- [ ] **Step 4: Add the Delete button**

In the drawer's button row inside `reading_drawer/1`, add a Delete button that only renders when editing (an existing entry has an `id`). Replace this block:

```elixir
        <div class="mt-2 flex items-center justify-end gap-2">
          <.link
            patch={~p"/admin/reading"}
            class="rounded-md px-3 py-1.5 text-[0.78rem] text-(--admin-text-muted) no-underline hover:text-(--admin-text)"
          >
            Cancel
          </.link>
```

with:

```elixir
        <div class="mt-2 flex items-center gap-2">
          <button
            :if={@entry.id}
            type="button"
            phx-click="delete"
            phx-value-id={@entry.id}
            data-confirm="Delete this entry?"
            class="rounded-md border border-(--admin-border) px-3 py-1.5 text-[0.78rem] text-(--admin-accent) hover:bg-(--admin-accent-soft)"
          >
            Delete
          </button>
          <div class="flex-1"></div>
          <.link
            patch={~p"/admin/reading"}
            class="rounded-md px-3 py-1.5 text-[0.78rem] text-(--admin-text-muted) no-underline hover:text-(--admin-text)"
          >
            Cancel
          </.link>
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `mix test test/newton_web/live/admin/reading_live_test.exs`
Expected: PASS — all seven LiveView tests green.

- [ ] **Step 6: Commit**

```bash
git add lib/newton_web/live/admin/reading_live/index.ex test/newton_web/live/admin/reading_live_test.exs
git commit -m "Add reading entry deletion from the drawer"
```

---

## Task 6: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full precommit suite**

Run: `mix precommit`
Expected: PASS — compiles with `--warnings-as-errors`, formatted, Credo `--strict` clean, both test suites green, Dialyzer 0 errors. Fix anything it reports before finishing.

- [ ] **Step 2: Manual smoke check (optional, dev server already running)**

Visit `/admin/reading`, click **Add entry**, fill the form, Save; confirm the row appears with its status badge and the summary bars update. Click the row, change a field, Save; confirm the update. Open an entry and Delete; confirm it disappears and the bars adjust. Press Escape on an open drawer; confirm it closes and the URL returns to `/admin/reading`.

---

## Self-review notes

- **Spec coverage** (Reading section of `docs/superpowers/specs/2026-06-10-admin-dashboard-design.md`): list with status badges + finished date (Task 3); add/edit via slide-over drawer covering title, author, link, status, finished date, note (Task 4); delete (Task 5); consistent drawer interaction language and inline changeset errors via `to_form/2` + `<.input>` (Task 4). The dashboard "Add entry" quick-action already links to `/admin/reading`, which this plan makes live — no dashboard change needed.
- **Beyond the spec (user request):** a finished-vs-in-progress summary at the top of `/admin/reading` — two server-rendered stacked bars (Books: read vs reading; Audio: listened vs listening) from `Reading.status_counts/0` (Tasks 1 + 4). No JS charting library, honoring the project rule that only the `app.js`/`app.css` bundles ship. The spec file should be updated to mention this once the section lands.
- **Out of scope** (matches spec/decisions): no inline status toggle, no schema change, no public-site change.
- **Type/name consistency:** `Reading.{get_entry!/1, update_entry/2, delete_entry/1, change_entry/2, status_counts/0}` defined in Task 1 are the exact functions called in Tasks 4–5; `status_counts/0` returns a zero-filled map keyed by `:reading/:read/:listening/:listened`, matching the `@counts.read/.reading/.listened/.listening` accesses in `reading_summary/1`; `reading_badge/1` defined in Task 2 is used in Task 3; `refresh_entries/1` defined in Task 4 is reused by Task 5's delete; stream name `:entries` and DOM IDs `#entries`, `#reading-summary`, `#reading-drawer`, `#reading-form` are consistent across template and tests.
