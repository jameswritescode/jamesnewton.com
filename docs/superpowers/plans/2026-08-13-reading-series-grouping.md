# Reading Series Grouping Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Group books that share a series into one visual block on the public `/reading` page, entered via a free-form admin field with autocomplete.

**Architecture:** A nullable `series` string on `reading_entries` is the grouping key. `Newton.Reading.feed_entries/0` turns the flat sorted entry list into a feed mixing plain `%Entry{}` structs with `{:series, name, entries}` tuples (group positioned at its newest entry). The public template pattern-matches that shape; the admin drawer adds a text field backed by a `<datalist>` of existing series names.

**Tech Stack:** Phoenix 1.8 / LiveView, Ecto (Postgres), plain CSS in `assets/css/site.css`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-13-reading-series-grouping-design.md`
- The grouping key is the exact series string; blank/whitespace series normalizes to `nil`
- A series with exactly one entry on the page renders as a plain entry (no group chrome)
- Group label is "Series · Author" when all entries share an author (then per-entry authors are dropped); series name alone otherwise (then entries keep "by Author")
- `list_entries/0` behavior is untouched — the admin list stays flat
- No narrating comments (repo CLAUDE.md); Elixir predicate names end in `?`, never `is_` prefix
- Public site is dark-only; use `rgba(var(--dot), …)` for hairlines, not new color literals
- Run `mix format` before each commit; the repo gate is `mix precommit`
- Commit trailers required on every commit (see repo conventions in the session; the executor session appends them)

---

### Task 1: `series` column, changeset normalization, and `series_names/0`

**Files:**
- Create: `priv/repo/migrations/<timestamp>_add_series_to_reading_entries.exs` (via `mix ecto.gen.migration`)
- Modify: `lib/newton/reading/entry.ex`
- Modify: `lib/newton/reading.ex`
- Test: `test/newton/reading_test.exs`

**Interfaces:**
- Consumes: nothing (first task)
- Produces: `Entry` schema field `series :: String.t() | nil`; `Newton.Reading.series_names() :: [String.t()]` (distinct, sorted asc, no nils). Tasks 2–4 rely on both.

- [ ] **Step 1: Write the failing tests**

Append to `test/newton/reading_test.exs` (inside `Newton.ReadingTest`, before the final `end`):

```elixir
  test "series is optional and blank normalizes to nil" do
    {:ok, blank} = Reading.create_entry(%{title: "T", author: "A", status: :read, series: "   "})
    assert blank.series == nil

    {:ok, trimmed} =
      Reading.create_entry(%{title: "T2", author: "A", status: :read, series: " First Law "})

    assert trimmed.series == "First Law"

    {:ok, cleared} = Reading.update_entry(trimmed, %{series: ""})
    assert cleared.series == nil
  end

  test "series_names/0 returns distinct sorted names excluding nil" do
    {:ok, _} = Reading.create_entry(%{title: "A", author: "x", status: :read, series: "Zeta"})
    {:ok, _} = Reading.create_entry(%{title: "B", author: "x", status: :read, series: "Alpha"})
    {:ok, _} = Reading.create_entry(%{title: "C", author: "x", status: :read, series: "Alpha"})
    {:ok, _} = Reading.create_entry(%{title: "D", author: "x", status: :read})

    assert Reading.series_names() == ["Alpha", "Zeta"]
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/newton/reading_test.exs`
Expected: the two new tests FAIL (`series` is not a permitted key / `series_names/0` undefined). Existing tests still pass.

- [ ] **Step 3: Generate and fill the migration**

Run: `mix ecto.gen.migration add_series_to_reading_entries`

Fill the generated file:

```elixir
defmodule Newton.Repo.Migrations.AddSeriesToReadingEntries do
  use Ecto.Migration

  def change do
    alter table(:reading_entries) do
      add :series, :string
    end
  end
end
```

Run: `mix ecto.migrate`

- [ ] **Step 4: Add the schema field and changeset normalization**

In `lib/newton/reading/entry.ex`, add the field after `:note`:

```elixir
    field :series, :string
```

Replace `changeset/2` and add the private helper:

```elixir
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:title, :author, :link, :note, :series, :status, :finished_at])
    |> validate_required([:title, :author, :status])
    |> normalize_series()
  end

  defp normalize_series(changeset) do
    with series when is_binary(series) <- get_change(changeset, :series),
         "" <- String.trim(series) do
      put_change(changeset, :series, nil)
    else
      trimmed when is_binary(trimmed) -> put_change(changeset, :series, trimmed)
      _ -> changeset
    end
  end
```

Note the `with`: a non-string change (nil) falls through unchanged; a trimmed non-empty string is written back so `" First Law "` stores as `"First Law"`.

- [ ] **Step 5: Add `series_names/0` to the context**

In `lib/newton/reading.ex`, after `change_entry/2`:

```elixir
  @doc "Distinct series names in use, sorted, for the admin autocomplete."
  @spec series_names() :: [String.t()]
  def series_names do
    Repo.all(
      from e in Entry,
        where: not is_nil(e.series),
        distinct: true,
        order_by: e.series,
        select: e.series
    )
  end
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `mix test test/newton/reading_test.exs`
Expected: all PASS.

- [ ] **Step 7: Format and commit**

```bash
mix format
git add priv/repo/migrations lib/newton/reading lib/newton/reading.ex test/newton/reading_test.exs
git commit -m "Add an optional series to reading entries"
```

---

### Task 2: `feed_entries/0` grouping

**Files:**
- Modify: `lib/newton/reading.ex`
- Test: `test/newton/reading_test.exs`

**Interfaces:**
- Consumes: `Entry.series` from Task 1; existing `list_entries/0` ordering (`finished_at` desc, Postgres NULLS FIRST — in-progress entries sort to the top)
- Produces: `Newton.Reading.feed_entries() :: [%Entry{} | {:series, String.t(), [%Entry{}]}]`. Task 3 renders exactly this shape.

- [ ] **Step 1: Write the failing tests**

Append to `test/newton/reading_test.exs`:

```elixir
  describe "feed_entries/0" do
    defp entry!(title, opts) do
      {:ok, entry} =
        Reading.create_entry(%{
          title: title,
          author: Keyword.get(opts, :author, "A"),
          status: Keyword.get(opts, :status, :read),
          finished_at: Keyword.get(opts, :finished_at),
          series: Keyword.get(opts, :series)
        })

      entry
    end

    test "groups a series at its newest entry, newest first within the group" do
      entry!("Book 1", series: "Saga", finished_at: ~D[2026-02-01])
      entry!("Between", finished_at: ~D[2026-03-01])
      entry!("Book 2", series: "Saga", finished_at: ~D[2026-04-01])
      entry!("Oldest", finished_at: ~D[2026-01-01])

      assert [{:series, "Saga", [b2, b1]}, between, oldest] = Reading.feed_entries()
      assert b2.title == "Book 2"
      assert b1.title == "Book 1"
      assert between.title == "Between"
      assert oldest.title == "Oldest"
    end

    test "an in-progress series book floats the group to the top" do
      entry!("Newest standalone", finished_at: ~D[2026-05-01])
      entry!("Book 1", series: "Saga", finished_at: ~D[2026-01-01])
      entry!("Book 2", series: "Saga", status: :reading, finished_at: nil)

      assert [{:series, "Saga", [b2, b1]}, standalone] = Reading.feed_entries()
      assert b2.title == "Book 2"
      assert b1.title == "Book 1"
      assert standalone.title == "Newest standalone"
    end

    test "a singleton series renders as a plain entry" do
      entry!("Solo", series: "Saga", finished_at: ~D[2026-01-01])

      assert [%Newton.Reading.Entry{title: "Solo"}] = Reading.feed_entries()
    end

    test "entries without a series pass through in order" do
      entry!("Old", finished_at: ~D[2025-01-01])
      entry!("New", finished_at: ~D[2026-01-01])

      assert ["New", "Old"] = Reading.feed_entries() |> Enum.map(& &1.title)
    end
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/newton/reading_test.exs`
Expected: the four new tests FAIL with `Reading.feed_entries/0 is undefined`.

- [ ] **Step 3: Implement `feed_entries/0`**

In `lib/newton/reading.ex`, after `list_entries/0`:

```elixir
  @type feed_item :: %Entry{} | {:series, String.t(), [%Entry{}]}

  @doc """
  Public reading feed: `list_entries/0` order, but all entries of a series are
  pulled together into a `{:series, name, entries}` tuple positioned where the
  series' newest entry falls. Singleton series stay plain entries.
  """
  @spec feed_entries() :: [feed_item()]
  def feed_entries do
    entries = list_entries()

    groups =
      entries
      |> Enum.reject(&is_nil(&1.series))
      |> Enum.group_by(& &1.series)

    entries
    |> Enum.reduce({[], MapSet.new()}, fn entry, {acc, seen} ->
      cond do
        is_nil(entry.series) -> {[entry | acc], seen}
        MapSet.member?(seen, entry.series) -> {acc, seen}
        true -> {[feed_group(entry.series, groups) | acc], MapSet.put(seen, entry.series)}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp feed_group(series, groups) do
    case groups[series] do
      [single] -> single
      group -> {:series, series, group}
    end
  end
```

`Enum.group_by/2` preserves encounter order, so each group inherits the
newest-first (in-progress first) order from `list_entries/0`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/newton/reading_test.exs`
Expected: all PASS.

- [ ] **Step 5: Format and commit**

```bash
mix format
git add lib/newton/reading.ex test/newton/reading_test.exs
git commit -m "Group series entries into a positioned feed structure"
```

---

### Task 3: Public page rendering and CSS

**Files:**
- Modify: `lib/newton_web/controllers/reading_controller.ex`
- Modify: `lib/newton_web/controllers/reading_html.ex`
- Modify: `lib/newton_web/controllers/reading_html/index.html.heex`
- Modify: `assets/css/site.css` (after the `.feed-item-book-caption` rule, ~line 664)
- Test: `test/newton_web/controllers/reading_controller_test.exs`

**Interfaces:**
- Consumes: `Reading.feed_entries/0` from Task 2 (`[%Entry{} | {:series, String.t(), [%Entry{}]}]`)
- Produces: nothing later tasks rely on

- [ ] **Step 1: Write the failing tests**

Append to `test/newton_web/controllers/reading_controller_test.exs`:

```elixir
  test "GET /reading groups series entries under a shared-author label", %{conn: conn} do
    {:ok, _} =
      Reading.create_entry(%{
        title: "Book One",
        author: "Ann Author",
        status: :read,
        finished_at: ~D[2026-01-10],
        series: "The Saga"
      })

    {:ok, _} =
      Reading.create_entry(%{
        title: "Standalone",
        author: "Someone Else",
        status: :read,
        finished_at: ~D[2026-02-10]
      })

    {:ok, _} =
      Reading.create_entry(%{
        title: "Book Two",
        author: "Ann Author",
        status: :read,
        finished_at: ~D[2026-03-10],
        series: "The Saga"
      })

    html = conn |> get(~p"/reading") |> html_response(200)
    series = html |> LazyHTML.from_document() |> LazyHTML.filter(".feed-series") |> LazyHTML.text()

    assert series =~ "Book One"
    assert series =~ "Book Two"
    assert series =~ "The Saga · Ann Author"
    refute series =~ "Standalone"
    refute series =~ "by Ann Author"
  end

  test "GET /reading keeps per-entry authors when a series has several", %{conn: conn} do
    {:ok, _} =
      Reading.create_entry(%{
        title: "Book One",
        author: "Ann Author",
        status: :read,
        finished_at: ~D[2026-01-10],
        series: "The Saga"
      })

    {:ok, _} =
      Reading.create_entry(%{
        title: "Book Two",
        author: "Bob Writer",
        status: :read,
        finished_at: ~D[2026-03-10],
        series: "The Saga"
      })

    html = conn |> get(~p"/reading") |> html_response(200)
    series = html |> LazyHTML.from_document() |> LazyHTML.filter(".feed-series") |> LazyHTML.text()

    assert series =~ "by Ann Author"
    assert series =~ "by Bob Writer"
    refute series =~ "The Saga ·"
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/newton_web/controllers/reading_controller_test.exs`
Expected: the two new tests FAIL (no `.feed-series` element renders). The existing test passes.

- [ ] **Step 3: Switch the controller to the feed structure**

In `lib/newton_web/controllers/reading_controller.ex`, change the `entries:` assign:

```elixir
    |> render(:index, page_title: "Reading", entries: Reading.feed_entries())
```

- [ ] **Step 4: Add the book item component and author helper to `ReadingHTML`**

Replace `lib/newton_web/controllers/reading_html.ex` with:

```elixir
defmodule NewtonWeb.ReadingHTML do
  use NewtonWeb, :html

  embed_templates "reading_html/*"

  defdelegate verb(status), to: Newton.Reading

  attr :entry, Newton.Reading.Entry, required: true
  attr :show_author, :boolean, default: true

  def book_item(assigns) do
    ~H"""
    <.feed_item
      id={Newton.Slug.slugify(@entry.title)}
      variant="book"
      date={format_date(@entry.finished_at)}
    >
      <p class="feed-item-book">
        {verb(@entry.status)}
        <cite>{@entry.title}</cite><span :if={@show_author}> by {@entry.author}</span>
      </p>

      <p :if={@entry.note} class="feed-item-book-caption">{@entry.note}</p>
    </.feed_item>
    """
  end

  @doc "The single author shared by every entry in a series group, or nil."
  def shared_author([first | rest]) do
    if Enum.all?(rest, &(&1.author == first.author)), do: first.author
  end
end
```

(`feed_item` and `format_date` are already imported via `use NewtonWeb, :html`, same as the current template's usage.)

- [ ] **Step 5: Render the feed shape in the template**

Replace `lib/newton_web/controllers/reading_html/index.html.heex` with:

```heex
<Layouts.app flash={@flash}>
  <article class="post">
    <header>
      <h1 class="post-title">Reading</h1>
    </header>

    <.feed>
      <%= for item <- @entries do %>
        <%= case item do %>
          <% {:series, name, entries} -> %>
            <section class="feed-series">
              <h3 class="feed-series-label">
                {name}<span :if={shared_author(entries)}> · {shared_author(entries)}</span>
              </h3>
              <.book_item
                :for={entry <- entries}
                entry={entry}
                show_author={is_nil(shared_author(entries))}
              />
            </section>
          <% entry -> %>
            <.book_item entry={entry} />
        <% end %>
      <% end %>
    </.feed>
  </article>
</Layouts.app>
```

- [ ] **Step 6: Add the group CSS**

In `assets/css/site.css`, directly after the `.feed-item-book-caption` rule (~line 664):

```css
.feed-series {
  margin-top: 1rem;
}

.feed-series:first-child {
  margin-top: 0;
}

.feed-series + .feed-item {
  margin-top: 1rem;
}

.feed-series-label {
  font-size: 0.78rem;
  font-weight: normal;
  text-transform: uppercase;
  letter-spacing: var(--label-tracking);
  color: var(--text-muted);
  padding: 0 24px;
  margin-bottom: 0.2rem;
}

.feed-series .feed-item {
  margin-left: 24px;
  padding: 14px 24px;
  border-left: 1px solid rgba(var(--dot), 0.18);
  border-radius: 0 var(--radius-lg) var(--radius-lg) 0;
}

.feed-series .feed-item + .feed-item {
  margin-top: 0;
}
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `mix test test/newton_web/controllers/reading_controller_test.exs`
Expected: all PASS (including the pre-existing flat-list test).

- [ ] **Step 8: Format and commit**

```bash
mix format
git add lib/newton_web/controllers assets/css/site.css test/newton_web/controllers/reading_controller_test.exs
git commit -m "Render series groups on the public reading page"
```

---

### Task 4: Admin series field with datalist autocomplete

**Files:**
- Modify: `lib/newton_web/components/admin/components.ex:68` (the `field` component's `:rest` include list)
- Modify: `lib/newton_web/live/admin/reading_live/index.ex`
- Test: `test/newton_web/live/admin/reading_live_test.exs`

**Interfaces:**
- Consumes: `Reading.series_names/0` from Task 1; `Entry.series` cast from Task 1
- Produces: nothing later tasks rely on

- [ ] **Step 1: Write the failing tests**

Append to `test/newton_web/live/admin/reading_live_test.exs` (inside the module, before the final `end`):

```elixir
  test "creates an entry with a series", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/reading/new")

    view
    |> form("#reading-form",
      entry: %{title: "New Book", author: "Auth", status: :read, series: "The Saga"}
    )
    |> render_submit()

    assert_patch(view, ~p"/admin/reading")
    assert Enum.any?(Reading.list_entries(), &(&1.series == "The Saga"))
  end

  test "series field suggests existing series names, including just-saved ones", %{conn: conn} do
    entry_fixture(%{title: "Earlier", series: "The Saga"})
    {:ok, view, _html} = live(conn, ~p"/admin/reading/new")

    assert has_element?(view, ~s(#series-names option[value="The Saga"]))
    refute has_element?(view, ~s(#series-names option[value="Fresh Series"]))

    view
    |> form("#reading-form",
      entry: %{title: "New Book", author: "Auth", status: :read, series: "Fresh Series"}
    )
    |> render_submit()

    {:ok, view, _html} = live(conn, ~p"/admin/reading/new")
    assert has_element?(view, ~s(#series-names option[value="Fresh Series"]))
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/newton_web/live/admin/reading_live_test.exs`
Expected: the two new tests FAIL (`series` is discarded — no form input for it — so the first test's `Enum.any?` is false; no `#series-names` datalist exists). If the form driver raises about a missing `series` input instead, that is the same failure.

- [ ] **Step 3: Allow `list` through the field component**

In `lib/newton_web/components/admin/components.ex`, line 68, change:

```elixir
  attr :rest, :global, include: ~w(rows placeholder autocomplete readonly required)
```

to:

```elixir
  attr :rest, :global, include: ~w(rows placeholder autocomplete readonly required list)
```

- [ ] **Step 4: Assign series names and render the field + datalist**

In `lib/newton_web/live/admin/reading_live/index.ex`:

In `mount/3`, add the assign:

```elixir
     |> assign(:status_options, @status_options)
     |> assign(:status_counts, Reading.status_counts())
     |> assign(:series_names, Reading.series_names())
     |> stream(:entries, Reading.list_entries())}
```

In `refresh_entries/1`, refresh it:

```elixir
  defp refresh_entries(socket) do
    socket
    |> stream(:entries, Reading.list_entries(), reset: true)
    |> assign(:status_counts, Reading.status_counts())
    |> assign(:series_names, Reading.series_names())
  end
```

In `render/1`, pass the names to the drawer:

```heex
      <.reading_drawer
        :if={@drawer_open}
        form={@form}
        entry={@entry}
        status_options={@status_options}
        series_names={@series_names}
      />
```

In `reading_drawer/1`, declare the attr and add the field between Author and Link:

```elixir
  attr :form, :map, required: true
  attr :entry, :map, required: true
  attr :status_options, :list, required: true
  attr :series_names, :list, required: true
```

```heex
        <Components.field field={@form[:author]} label="Author" />
        <Components.field field={@form[:series]} label="Series" list="series-names" />
        <datalist id="series-names">
          <option :for={name <- @series_names} value={name}></option>
        </datalist>
        <Components.field field={@form[:link]} label="Link" />
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `mix test test/newton_web/live/admin/reading_live_test.exs`
Expected: all PASS.

- [ ] **Step 6: Run the full precommit gate**

Run: `mix precommit`
Expected: clean (compile with warnings-as-errors, formatter, Credo, ExUnit, vitest, Dialyzer all pass).

- [ ] **Step 7: Format and commit**

```bash
git add lib/newton_web/components/admin/components.ex lib/newton_web/live/admin/reading_live/index.ex test/newton_web/live/admin/reading_live_test.exs
git commit -m "Add a series field with autocomplete to the reading drawer"
```
