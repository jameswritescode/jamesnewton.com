# View Analytics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Server-side page/post view counts collected from Phoenix's existing router telemetry, rolled up daily in Postgres, displayed in the admin dashboard.

**Architecture:** `Newton.Analytics` owns a `daily_views` rollup table (one row per date+path). `Newton.Analytics.Collector` (GenServer) attaches to `[:phoenix, :router_dispatch, :stop]`, filters in the request process (public routes, GET 200, no preview token, anonymous, non-bot), buffers counts, and flushes a batched upsert every 10s. The admin `DashboardLive` gains a Views card and a top-posts list.

**Tech Stack:** Ecto (upsert via `insert_all` + `EXCLUDED`), `:telemetry` (existing Phoenix events; `Newton.Telemetry` facade for the flush span), no new deps.

**Spec:** `docs/superpowers/specs/2026-07-17-view-analytics-design.md`

## Global Constraints

- **NO GIT COMMITS.** James is remote (commit signing unavailable). Do not run `git add` or `git commit` at any step — leave all changes in the working tree. The controller sequences commits later. (The working tree already carries one staged, uncommitted spec file — leave it alone.)
- **The telemetry handler must never raise** — `:telemetry` permanently detaches a raising handler (silent data stop). Every filter falls through to "don't count" on unexpected shapes; no `Map.fetch!`, no bracket-`Access` on possibly-Unfetched conn fields — pattern matching only.
- Counted routes, exactly: `/`, `/posts`, `/posts/:slug`, `/reading`, `/photos`, `/links`, `/resume`. Only `GET` with status `200`, no `p` param, no authenticated session, non-bot non-empty user-agent.
- The user-agent string is examined in memory only — **never stored**.
- Custom metrics: declare only in `Newton.Metrics.definitions/0` (AGENTS.md rule); the flush metric uses buckets exactly `[5, 10, 25, 50, 100, 250]` ms, tag `:result` only.
- Migrations via `mix ecto.gen.migration` (Ecto guidelines).
- Test mechanics (from spec): `Phoenix.ConnTest` sends no user-agent, so counting tests set `put_req_header("user-agent", "TestBrowser/1.0")`; counting assertions target uniquely-slugged post paths, never `/`; collector test files are `async: false` (global buffer + sandbox allowance).
- No narrating comments. Domain modules carry `@spec`s (existing convention).
- Finish with `mix precommit` (Task 3, final step) and fix anything it raises.

---

### Task 1: `Newton.Analytics` context + `daily_views` rollups

**Files:**
- Create: migration via `mix ecto.gen.migration create_daily_views` (lands in `priv/repo/migrations/`)
- Create: `lib/newton/analytics/daily_view.ex`
- Create: `lib/newton/analytics.ex`
- Test: `test/newton/analytics_test.exs`

**Interfaces:**
- Consumes: nothing new.
- Produces (Tasks 2 and 3 depend on these exact signatures):
  - `Newton.Analytics.record_views(%{optional({Date.t(), String.t()}) => pos_integer()}) :: :ok`
  - `Newton.Analytics.total_since(Date.t()) :: non_neg_integer()`
  - `Newton.Analytics.total_all_time() :: non_neg_integer()`
  - `Newton.Analytics.top_paths(Date.t(), pos_integer()) :: [%{path: String.t(), count: non_neg_integer()}]`

- [ ] **Step 1: Generate the migration**

Run: `mix ecto.gen.migration create_daily_views`

Edit the generated file's `change/0` to:

```elixir
  def change do
    create table(:daily_views) do
      add :date, :date, null: false
      add :path, :string, null: false
      add :count, :integer, null: false, default: 0

      timestamps()
    end

    create unique_index(:daily_views, [:date, :path])
  end
```

Run: `mix ecto.migrate`
Expected: migration runs; `mix test` DB picks it up automatically on next run.

- [ ] **Step 2: Write the failing tests**

Create `test/newton/analytics_test.exs`:

```elixir
defmodule Newton.AnalyticsTest do
  use Newton.DataCase, async: true

  alias Newton.Analytics

  @today Date.utc_today()

  test "record_views inserts new rollup rows and increments existing ones" do
    :ok = Analytics.record_views(%{{@today, "/posts/hello"} => 2, {@today, "/photos"} => 1})
    :ok = Analytics.record_views(%{{@today, "/posts/hello"} => 3})

    assert Analytics.total_all_time() == 6
    assert [%{path: "/posts/hello", count: 5}, %{path: "/photos", count: 1}] =
             Analytics.top_paths(@today, 10)
  end

  test "record_views with an empty map is a no-op" do
    assert Analytics.record_views(%{}) == :ok
    assert Analytics.total_all_time() == 0
  end

  test "total_since sums only rows on or after the date" do
    old = Date.add(@today, -30)
    :ok = Analytics.record_views(%{{old, "/posts/old"} => 10, {@today, "/posts/new"} => 4})

    assert Analytics.total_since(Date.add(@today, -6)) == 4
    assert Analytics.total_all_time() == 14
  end

  test "top_paths groups across dates, orders by total, and honors the limit" do
    yesterday = Date.add(@today, -1)

    :ok =
      Analytics.record_views(%{
        {yesterday, "/posts/a"} => 3,
        {@today, "/posts/a"} => 3,
        {@today, "/posts/b"} => 4,
        {@today, "/posts/c"} => 1
      })

    assert [%{path: "/posts/a", count: 6}, %{path: "/posts/b", count: 4}] =
             Analytics.top_paths(yesterday, 2)
  end
end
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `mix test test/newton/analytics_test.exs`
Expected: FAIL — `Newton.Analytics` is undefined.

- [ ] **Step 4: Create the schema**

Create `lib/newton/analytics/daily_view.ex`:

```elixir
defmodule Newton.Analytics.DailyView do
  @moduledoc "One day's view count for one public path."
  use Ecto.Schema

  schema "daily_views" do
    field :date, :date
    field :path, :string
    field :count, :integer, default: 0

    timestamps()
  end
end
```

(No changeset — rows are written only programmatically by `record_views/1`.)

- [ ] **Step 5: Create the context**

Create `lib/newton/analytics.ex`:

```elixir
defmodule Newton.Analytics do
  @moduledoc "Server-side view analytics: daily per-path rollups."
  import Ecto.Query

  alias Newton.Analytics.DailyView
  alias Newton.Repo

  @spec record_views(%{optional({Date.t(), String.t()}) => pos_integer()}) :: :ok
  def record_views(counts) when map_size(counts) == 0, do: :ok

  def record_views(counts) do
    now = NaiveDateTime.utc_now(:second)

    rows =
      for {{date, path}, count} <- counts do
        %{date: date, path: path, count: count, inserted_at: now, updated_at: now}
      end

    Repo.insert_all(DailyView, rows,
      conflict_target: [:date, :path],
      on_conflict:
        from(d in DailyView,
          update: [
            inc: [count: fragment("EXCLUDED.count")],
            set: [updated_at: fragment("EXCLUDED.updated_at")]
          ]
        )
    )

    :ok
  end

  @spec total_since(Date.t()) :: non_neg_integer()
  def total_since(date) do
    Repo.one(from d in DailyView, where: d.date >= ^date, select: coalesce(sum(d.count), 0))
  end

  @spec total_all_time() :: non_neg_integer()
  def total_all_time do
    Repo.one(from d in DailyView, select: coalesce(sum(d.count), 0))
  end

  @spec top_paths(Date.t(), pos_integer()) :: [%{path: String.t(), count: non_neg_integer()}]
  def top_paths(since, limit) do
    Repo.all(
      from d in DailyView,
        where: d.date >= ^since,
        group_by: d.path,
        order_by: [desc: sum(d.count)],
        limit: ^limit,
        select: %{path: d.path, count: sum(d.count)}
    )
  end
end
```

Note: if `NaiveDateTime.utc_now(:second)` raises on this Elixir version, use `NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)`.

- [ ] **Step 6: Run tests to verify they pass**

Run: `mix test test/newton/analytics_test.exs`
Expected: 4 tests, 0 failures.

**Do NOT commit (global constraint). Report and stop here.**

---

### Task 2: `Newton.Analytics.Collector` + supervision + flush metric

**Files:**
- Create: `lib/newton/analytics/collector.ex`
- Modify: `lib/newton/application.ex` (children — insert after `{Task.Supervisor, name: Newton.TaskSupervisor},`)
- Modify: `config/test.exs` (append)
- Modify: `lib/newton/metrics.ex` (add the flush distribution)
- Test: `test/newton/analytics/collector_test.exs`

**Interfaces:**
- Consumes: `Newton.Analytics.record_views/1` (Task 1), `Newton.Telemetry.span/4` (existing: `span(subsystem :: atom, operation :: atom, start_meta :: map, (-> {result, stop_meta :: map})) :: result`).
- Produces: `Newton.Analytics.Collector.flush() :: :ok` (synchronous; used by tests and Task 3's dashboard tests if needed); the `[:newton, :analytics, :flush]` telemetry span.

- [ ] **Step 1: Add test config**

Append to `config/test.exs`:

```elixir
config :newton, Newton.Analytics.Collector, flush_interval: :manual
```

- [ ] **Step 2: Write the failing tests**

Create `test/newton/analytics/collector_test.exs`:

```elixir
defmodule Newton.Analytics.CollectorTest do
  use NewtonWeb.ConnCase, async: false

  alias Newton.Analytics
  alias Newton.Analytics.Collector

  import Newton.AccountsFixtures

  @ua {"user-agent", "TestBrowser/1.0"}

  setup do
    Ecto.Adapters.SQL.Sandbox.allow(Newton.Repo, self(), Process.whereis(Collector))
    Collector.flush()
    :ok
  end

  defp browse(conn, path, headers \\ [@ua]) do
    Enum.reduce(headers, conn, fn {k, v}, c -> put_req_header(c, k, v) end) |> get(path)
  end

  defp count_for(path) do
    Analytics.top_paths(Date.add(Date.utc_today(), -1), 100)
    |> Enum.find_value(0, fn %{path: p, count: c} -> if p == path, do: c end)
  end

  defp published_post(slug) do
    {:ok, post} =
      Newton.Blog.create_post(%{
        slug: slug,
        title: "Post #{slug}",
        body_markdown: "Body.",
        published_at: DateTime.utc_now()
      })

    post
  end

  test "a public page view lands in daily_views and repeats increment", %{conn: conn} do
    published_post("count-me")

    browse(conn, "/posts/count-me")
    Collector.flush()
    assert count_for("/posts/count-me") == 1

    browse(conn, "/posts/count-me")
    Collector.flush()
    assert count_for("/posts/count-me") == 2
  end

  test "bot user-agents are not counted", %{conn: conn} do
    published_post("bot-bait")

    browse(conn, "/posts/bot-bait", [{"user-agent", "Mozilla/5.0 (compatible; Googlebot/2.1)"}])
    Collector.flush()

    assert count_for("/posts/bot-bait") == 0
  end

  test "requests without a user-agent are not counted", %{conn: conn} do
    published_post("no-ua")

    get(conn, "/posts/no-ua")
    Collector.flush()

    assert count_for("/posts/no-ua") == 0
  end

  test "preview-token requests are not counted", %{conn: conn} do
    published_post("previewed")

    browse(conn, "/posts/previewed?p=sometoken")
    Collector.flush()

    assert count_for("/posts/previewed") == 0
  end

  test "authenticated sessions are not counted", %{conn: conn} do
    published_post("own-visit")

    conn |> log_in_user(user_fixture()) |> browse("/posts/own-visit")
    Collector.flush()

    assert count_for("/posts/own-visit") == 0
  end

  test "non-public routes are not counted", %{conn: conn} do
    browse(conn, "/sitemap.xml")
    Collector.flush()

    assert count_for("/sitemap.xml") == 0
  end

  test "404s are not counted", %{conn: conn} do
    assert_error_sent 404, fn -> browse(conn, "/posts/nope") end
    Collector.flush()

    assert count_for("/posts/nope") == 0
  end

  test "flush emits the analytics telemetry span" do
    ref = :telemetry_test.attach_event_handlers(self(), [[:newton, :analytics, :flush, :stop]])

    send(Process.whereis(Collector), {:"$gen_cast", {:view, "/posts/span-check"}})
    Collector.flush()

    assert_received {[:newton, :analytics, :flush, :stop], ^ref, %{duration: _},
                     %{result: :ok, row_count: 1}}
  end
end
```

Note on the last test: casting directly exercises the flush span without an HTTP request; `{:"$gen_cast", ...}` is what `GenServer.cast/2` sends — if you prefer, call `GenServer.cast(Collector, {:view, "/posts/span-check"})` (equivalent and clearer; use that form).

- [ ] **Step 3: Run tests to verify they fail**

Run: `mix test test/newton/analytics/collector_test.exs`
Expected: FAIL — `Newton.Analytics.Collector` is undefined / not started.

- [ ] **Step 4: Implement the collector**

Create `lib/newton/analytics/collector.ex`:

```elixir
defmodule Newton.Analytics.Collector do
  @moduledoc """
  Buffers public page views from Phoenix router telemetry and flushes them to
  Newton.Analytics as daily rollups.
  """
  use GenServer
  require Logger

  alias Newton.Analytics

  @handler_id "newton-analytics-collector"
  @event [:phoenix, :router_dispatch, :stop]
  @public_routes ~w(/ /posts /posts/:slug /reading /photos /links /resume)
  @bot_ua ~r/bot|crawl|spider|slurp|curl|wget|python|java|httpclient|http.client|scan|monitor|probe|fetch|preview/i
  @flush_ms 10_000

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @spec flush() :: :ok
  def flush, do: GenServer.call(__MODULE__, :flush)

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)
    :telemetry.detach(@handler_id)
    :ok = :telemetry.attach(@handler_id, @event, &__MODULE__.handle_event/4, nil)
    {:ok, %{buffer: %{}}, {:continue, :schedule}}
  end

  @impl true
  def handle_continue(:schedule, state) do
    schedule_flush()
    {:noreply, state}
  end

  # Runs in the request process. Must never raise: :telemetry permanently
  # detaches a raising handler. Every clause falls through to "don't count".
  def handle_event(_event, _measurements, metadata, _config) do
    with %{conn: conn, route: route} when route in @public_routes <- metadata,
         %Plug.Conn{method: "GET", status: 200} <- conn,
         false <- preview?(conn),
         false <- authenticated?(conn),
         true <- human?(conn) do
      GenServer.cast(__MODULE__, {:view, conn.request_path})
    else
      _ -> :ok
    end
  end

  defp preview?(%Plug.Conn{params: %{"p" => p}}) when not is_nil(p), do: true
  defp preview?(_conn), do: false

  defp authenticated?(%Plug.Conn{assigns: %{current_scope: %{user: %{}}}}), do: true
  defp authenticated?(_conn), do: false

  defp human?(conn) do
    case Plug.Conn.get_req_header(conn, "user-agent") do
      [ua | _] when byte_size(ua) > 0 -> not Regex.match?(@bot_ua, ua)
      _ -> false
    end
  end

  @impl true
  def handle_cast({:view, path}, state) do
    key = {Date.utc_today(), path}
    {:noreply, %{state | buffer: Map.update(state.buffer, key, 1, &(&1 + 1))}}
  end

  @impl true
  def handle_info(:flush, state) do
    do_flush(state.buffer)
    schedule_flush()
    {:noreply, %{state | buffer: %{}}}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    do_flush(state.buffer)
    {:reply, :ok, %{state | buffer: %{}}}
  end

  @impl true
  def terminate(_reason, state), do: do_flush(state.buffer)

  defp do_flush(buffer) when map_size(buffer) == 0, do: :ok

  defp do_flush(buffer) do
    Newton.Telemetry.span(:analytics, :flush, %{row_count: map_size(buffer)}, fn ->
      try do
        :ok = Analytics.record_views(buffer)
        {:ok, %{result: :ok, row_count: map_size(buffer)}}
      rescue
        e ->
          Logger.warning("analytics flush failed, dropping buffer: #{Exception.message(e)}")
          {:error, %{result: :error, row_count: map_size(buffer)}}
      end
    end)

    :ok
  end

  defp schedule_flush do
    case Application.get_env(:newton, __MODULE__, [])[:flush_interval] || @flush_ms do
      :manual -> :ok
      ms -> Process.send_after(self(), :flush, ms)
    end
  end
end
```

- [ ] **Step 5: Supervise it**

In `lib/newton/application.ex`, children list — insert after the Task.Supervisor line:

```elixir
      {Task.Supervisor, name: Newton.TaskSupervisor},
      Newton.Analytics.Collector,
```

- [ ] **Step 6: Declare the flush metric**

In `lib/newton/metrics.ex`, add to the list in `definitions/0` after the IndexNow entry:

```elixir
      distribution("newton.analytics.flush.stop.duration",
        event_name: [:newton, :analytics, :flush, :stop],
        unit: {:native, :millisecond},
        tags: [:result],
        reporter_options: [buckets: [5, 10, 25, 50, 100, 250]]
      )
```

(Match the existing IndexNow entry's shape — no explicit `measurement:` option; the `.duration` name suffix derives it. The guard tests in `test/newton/metrics_test.exs` will fail if the shape is wrong.)

- [ ] **Step 7: Run tests to verify they pass**

Run: `mix test test/newton/analytics/collector_test.exs test/newton/metrics_test.exs`
Expected: all pass.

- [ ] **Step 8: Run the full suite**

Run: `mix test`
Expected: 0 failures, no new warnings or log noise. If the collector's flush produces sandbox-ownership errors from stray test requests, something is wrong with the `:manual` config — stop and re-check Step 1 rather than papering over it.

**Do NOT commit (global constraint). Report and stop here.**

---

### Task 3: Dashboard Views card + top posts

**Files:**
- Modify: `lib/newton_web/live/admin/dashboard_live.ex` (mount assigns ~line 9-18; render grid ~line 27-38; new private helpers)
- Test: `test/newton_web/live/admin/dashboard_views_test.exs` (new file — `dashboard_live_test.exs` stays untouched)

**Interfaces:**
- Consumes (Task 1): `Newton.Analytics.total_since(Date.t())`, `Newton.Analytics.total_all_time()`, `Newton.Analytics.top_paths(Date.t(), pos_integer())` returning `[%{path: String.t(), count: non_neg_integer()}]`. Also existing `Newton.Blog.list_published_posts/0` (post summaries with `.slug` and `.title`).
- Produces: nothing downstream.

- [ ] **Step 1: Write the failing tests**

Create `test/newton_web/live/admin/dashboard_views_test.exs`:

```elixir
defmodule NewtonWeb.Admin.DashboardViewsTest do
  use NewtonWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Newton.AccountsFixtures

  alias Newton.Analytics

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture())}
  end

  defp seed_views do
    today = Date.utc_today()

    {:ok, _} =
      Newton.Blog.create_post(%{
        slug: "top-post",
        title: "The Top Post",
        body_markdown: "Body.",
        published_at: DateTime.utc_now()
      })

    :ok =
      Analytics.record_views(%{
        {today, "/posts/top-post"} => 7,
        {today, "/posts/deleted-post"} => 3,
        {Date.add(today, -30), "/photos"} => 10
      })
  end

  test "the Views card shows 7-day and all-time totals", %{conn: conn} do
    seed_views()

    {:ok, view, _html} = live(conn, ~p"/admin")

    # 7-day total is 10 (7 + 3; the /photos views are 30 days old), all-time 20.
    assert has_element?(view, "#card-views", "10")
    assert has_element?(view, "#card-views", "20 all-time")
  end

  test "top posts list shows titles with counts and falls back to the raw path", %{conn: conn} do
    seed_views()

    {:ok, view, _html} = live(conn, ~p"/admin")

    assert has_element?(view, "#top-posts")
    assert render(view) =~ "The Top Post"
    assert render(view) =~ "/posts/deleted-post"
  end

  test "no views yet renders the card with zeros and no top-posts list", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/admin")

    assert has_element?(view, "#card-views")
    assert html =~ "0 all-time"
    refute has_element?(view, "#top-posts")
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/newton_web/live/admin/dashboard_views_test.exs`
Expected: FAIL — no `#card-views` element.

- [ ] **Step 3: Implement the dashboard additions**

In `lib/newton_web/live/admin/dashboard_live.ex`:

Mount gains three assigns (add to the existing pipeline):

```elixir
     |> assign(:views_week, Newton.Analytics.total_since(Date.add(Date.utc_today(), -6)))
     |> assign(:views_total, Newton.Analytics.total_all_time())
     |> assign(:top_posts, top_posts())
```

New private helpers (place near `media_drift/0`):

```elixir
  defp top_posts do
    titles = Map.new(Newton.Blog.list_published_posts(), &{&1.slug, &1.title})

    Date.utc_today()
    |> Date.add(-6)
    |> Newton.Analytics.top_paths(20)
    |> Enum.flat_map(fn %{path: path, count: count} ->
      case path do
        "/posts/" <> slug -> [%{slug: slug, count: count, title: Map.get(titles, slug, path)}]
        _ -> []
      end
    end)
    |> Enum.take(5)
  end
```

Render — add a fourth card inside the existing grid div:

```heex
        <.card id="card-views" title="Views" primary={@views_week} path="/admin">
          {@views_total} all-time
        </.card>
```

And after the grid div (before the media-drift link), the top-posts list:

```heex
      <div
        :if={@top_posts != []}
        id="top-posts"
        class="mt-4 rounded-xl border border-(--admin-border) bg-(--admin-surface) p-4"
      >
        <h2 class="mb-3 text-[0.78rem] uppercase tracking-wide text-(--admin-text-subtle)">
          Top posts — last 7 days
        </h2>
        <ol class="flex flex-col gap-1.5">
          <li :for={post <- @top_posts} class="flex items-baseline justify-between gap-3">
            <.link
              href={~p"/posts/#{post.slug}"}
              class="truncate text-[0.85rem] text-(--admin-text) no-underline hover:text-(--admin-accent)"
            >
              {post.title}
            </.link>
            <span class="font-mono text-[0.8rem] text-(--admin-text-muted)">{post.count}</span>
          </li>
        </ol>
      </div>
```

(Style detail may be adapted to match the admin theme, but keep the `id="top-posts"`, `id="card-views"` anchors — the tests use them.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/newton_web/live/admin/dashboard_views_test.exs test/newton_web/live/admin/dashboard_live_test.exs`
Expected: all pass (existing dashboard tests unaffected).

- [ ] **Step 5: Run precommit**

Run: `mix precommit`
Expected: clean compile (no warnings), format, credo, full mix suite, pnpm tests, dialyzer (3 known skipped phoenix_seo errors). Fix anything it raises.

**Do NOT commit (global constraint). Report and stop here.**
