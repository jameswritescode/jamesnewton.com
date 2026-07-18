# View Analytics Design

**Goal:** Server-side page/post view counts — collected from Phoenix's existing
telemetry, rolled up daily in Postgres, displayed in the admin dashboard.
Nothing per-visitor is ever stored.

**Context:** Prometheus/Grafana (just shipped) answers route-level traffic
questions but is the wrong analytics store: bounded retention, no per-post
history, bot noise baked into counters forever. External analytics
(Plausible/umami) is more than this site needs. The accepted approach: telemetry
as the event bus, a database as the store — no client-side JS, no cookies, no
consent surface.

## Decisions

- **Consume Phoenix's own `[:phoenix, :router_dispatch, :stop]` event** rather
  than emitting custom events from controllers — zero touch to controller code;
  the framework already carries route, conn, and status.
- **Counts only.** One rollup table `(date, path, count)`. No referrers, no
  uniques, no sessions, no per-visitor data (James chose counts-only).
- **James's own visits are excluded** — any request with an authenticated
  session is not counted (James chose this).
- **Paths stay bounded** because only allowlisted public GET routes count;
  junk URLs can't create rows (they don't match the allowlist, and non-200s are
  filtered anyway).
- **Buffered writes.** The telemetry handler runs in the request process, so it
  must be near-free: filter checks plus one `GenServer.cast`. The collector
  buffers in memory and flushes every 10 seconds as a single batched
  upsert-increment. A crash or restart loses at most one flush window of counts
  — acceptable for blog analytics.
- **Bot filtering at collection time** via a compiled user-agent heuristic
  (bot/crawler/spider/slurp/curl/wget/python/http-client/empty-UA). The UA
  string is examined in memory only, never persisted.
- **Counts start at deploy.** No backfill; historical traffic is unknowable
  server-side.

## Components

### 1. `Newton.Analytics` context + `daily_views` table

Migration:

```elixir
create table(:daily_views) do
  add :date, :date, null: false
  add :path, :string, null: false
  add :count, :integer, null: false, default: 0
  timestamps()
end

create unique_index(:daily_views, [:date, :path])
```

Schema `Newton.Analytics.DailyView` (fields `date`, `path`, `count`).

Context API:

```elixir
@spec record_views(%{optional({Date.t(), String.t()}) => pos_integer()}) :: :ok
def record_views(counts)
# insert_all with on_conflict: [inc: [count: n]] per row, conflict_target [:date, :path]

@spec total_since(Date.t()) :: non_neg_integer()
def total_since(date)   # sum of counts on/after date

@spec total_all_time() :: non_neg_integer()
def total_all_time()

@spec top_paths(Date.t(), pos_integer()) :: [%{path: String.t(), count: non_neg_integer()}]
def top_paths(since, limit)  # grouped + summed, descending
```

### 2. `Newton.Analytics.Collector` (GenServer)

- On `init`, attaches a telemetry handler to `[:phoenix, :router_dispatch, :stop]`.
- **Handler (request process — cheap path):** reads `metadata.conn` and
  `metadata.route`; when ALL filters pass, `GenServer.cast(collector, {:view, path})`
  with `conn.request_path`. Filters:
  1. `metadata.route` is one of: `/`, `/posts`, `/posts/:slug`, `/reading`,
     `/photos`, `/links`, `/resume`
  2. `conn.method == "GET"` and `conn.status == 200`
  3. `conn.params["p"]` is nil (preview-token links never count)
  4. `conn.assigns.current_scope` carries no user (excludes James's own
     browsing)
  5. user-agent does not match the bot regex and is not empty
- **State:** `%{{date, path} => count}` accumulated from casts, with
  `Date.utc_today()` stamped at cast-processing time.
- **Flush:** every 10s (`Process.send_after`), calls
  `Analytics.record_views(buffer)` and clears. Wrapped in
  `Newton.Telemetry.span(:analytics, :flush, ...)` with bounded metadata
  (`row_count`, `result`). A failed flush logs a warning and drops the buffer —
  never crash-loops, never grows unbounded.
- Traps exits and flushes on `terminate/2` so a clean shutdown loses nothing.
- **Supervision:** child after `Newton.Repo`, before `NewtonWeb.Endpoint`
  (needs Repo up to flush; must exist before requests arrive).
- **Test mode:** `config :newton, Newton.Analytics.Collector, flush_interval: :manual`
  in `config/test.exs` — no timer; tests call a synchronous `flush/0` after
  `Ecto.Adapters.SQL.Sandbox.allow`-ing the collector into their sandbox. This
  is required because the collector flushes from its own process, which the
  sandbox would otherwise reject; it also keeps stray requests from other tests
  from producing noisy ownership errors.

### 3. Metrics declaration

`Newton.Metrics.definitions/0` gains one entry (per the single-source rule):

```elixir
distribution("newton.analytics.flush.stop.duration",
  event_name: [:newton, :analytics, :flush, :stop],
  measurement: :duration,
  unit: {:native, :millisecond},
  tags: [:result],
  reporter_options: [buckets: [5, 10, 25, 50, 100, 250]]
)
```

Both LiveDashboard and Grafana pick it up with no further wiring.

### 4. Admin dashboard display

`NewtonWeb.Admin.DashboardLive`:

- A fourth `.card` in the existing grid — title "Views", primary = 7-day total
  (`total_since(Date.add(Date.utc_today(), -6))`), inner block = all-time total.
  Links to `/admin` (no dedicated views page yet — YAGNI).
- Below the grid: a "Top posts — last 7 days" list from `top_paths/2`
  (limit 5), filtered to `/posts/` paths, each row showing the post title
  (resolved by slug; paths whose post no longer exists fall back to the raw
  path) and its count, linking to the public post.
- Both queries run at mount, same pattern as the existing count cards.

## Out of scope

- Referrers, uniques, sessions, geographic data.
- Public-facing view counts on posts.
- A dedicated analytics page in the admin (the dashboard card may earn one
  later).
- Per-slug Prometheus series (route-level traffic already exists in Grafana).
- Backfill of historical traffic.
- Pruning: at one row per public path per day, years of data is thousands of
  rows — no cleanup needed.

## Error handling

- Collector flush failure: warning log, buffer dropped, next window starts
  clean. Repo down at flush = one lost window, not a crash.
- Collector crash: supervisor restarts it; handler re-attaches (attach in
  `init`, detach in `terminate` — re-attach must be idempotent via a stable
  handler id, detach-before-attach).
- The telemetry handler itself must never raise: any exception in a telemetry
  handler causes `:telemetry` to permanently detach it (silent data stop). The
  filter chain is pure pattern-matching/regex on values that may be missing —
  written to fall through to "don't count" on anything unexpected.

## Testing

Behavior-level:

1. **Counting behavior (ConnCase, collector in sandbox):** a GET to a public
   page + `flush` → one `daily_views` row with count 1; a second request +
   flush increments the same row (upsert path proven across flushes).
   Two mechanics these tests must respect: (a) `Phoenix.ConnTest` sends no
   user-agent header, and the empty-UA filter would reject the request — set
   one explicitly (`put_req_header("user-agent", "TestBrowser/1.0")`); (b) the
   collector buffer is global while async tests run, so counting assertions
   target a uniquely-slugged post path, never a shared path like `/` whose
   count other tests can inflate.
2. **Filters:** requests with a bot user-agent, a `?p=` preview token, an
   authenticated session, and a 404 path each produce no rows after flush.
3. **Rollup queries:** seeded rows across dates/paths → `total_since/1`,
   `total_all_time/0`, and `top_paths/2` return correct sums/ordering.
4. **Dashboard:** with seeded rows, the Views card and top-posts list render
   the expected numbers; a top path whose post was deleted renders the raw
   path without crashing.
5. **Telemetry:** flush emits the `[:newton, :analytics, :flush, :stop]` event
   (assert via `:telemetry_test`).
