# Fly Grafana Metrics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose app metrics (Phoenix, Ecto, BEAM, custom) in Prometheus format for Fly.io's managed Grafana, with custom metrics declared once in `Newton.Metrics` and consumed by both LiveDashboard (dev) and PromEx (prod).

**Architecture:** A `Newton.Metrics` module holds custom `Telemetry.Metrics` definitions. `NewtonWeb.Telemetry` splices them into LiveDashboard; a generic `Newton.PromEx.Plugins.App` adapter feeds the same list to PromEx alongside its built-in Phoenix/Ecto/BEAM plugins. PromEx serves `/metrics` on a private port 9091 in prod only; `fly.toml` tells Fly's Prometheus to scrape it.

**Tech Stack:** `prom_ex ~> 1.12` (new dep), `Telemetry.Metrics` (existing), Fly.io `[metrics]` scraping.

**Spec:** `docs/superpowers/specs/2026-07-16-fly-grafana-metrics-design.md`

## Global Constraints

- **Custom metrics live only in `Newton.Metrics.definitions/0`** (AGENTS.md observability rule). Prometheus-exportable types only: `counter`, `sum`, `last_value`, `distribution` — **never `summary`**. Distributions carry explicit `reporter_options: [buckets: [...]]`.
- Metric tags must be bounded values — never URLs, slugs, or IDs (AGENTS.md).
- IndexNow distribution buckets, exactly: `[10, 50, 100, 250, 500, 1_000, 2_500, 5_000]` (milliseconds).
- Metrics server: port **9091**, prod only (`config/prod.exs`); PromEx defaults (disabled metrics server, disabled Grafana upload) everywhere else.
- No narrating comments (AGENTS.md).
- **Working tree note:** the repo carries the uncommitted sitemap/IndexNow feature. Do NOT run `git add`/`git commit` for files outside this plan's file list, and stage only the hunks belonging to this plan in shared files (`lib/newton_web/telemetry.ex`, `lib/newton/application.ex` are both also touched by the uncommitted feature — commit instructions below handle this).
- Finish with `mix precommit` (Task 2, final step) and fix anything it raises.

---

### Task 1: `Newton.Metrics` single source + LiveDashboard splice

**Files:**
- Create: `lib/newton/metrics.ex`
- Modify: `lib/newton_web/telemetry.ex` (metrics/0: remove IndexNow summary at ~line 24-28, append shared definitions at ~line 89)
- Test: `test/newton/metrics_test.exs`

**Interfaces:**
- Consumes: nothing new (the `[:newton, :indexnow, :submit, :stop]` event already exists).
- Produces: `Newton.Metrics.definitions() :: [Telemetry.Metrics.t()]` — Task 2's adapter plugin calls it.

- [ ] **Step 1: Write the failing test**

Create `test/newton/metrics_test.exs`:

```elixir
defmodule Newton.MetricsTest do
  use ExUnit.Case, async: true

  test "definitions use only Prometheus-exportable metric types" do
    definitions = Newton.Metrics.definitions()

    assert definitions != []

    for metric <- definitions do
      refute match?(%Telemetry.Metrics.Summary{}, metric),
             "#{inspect(metric.name)} is a summary; PromEx cannot export it"
    end
  end

  test "every distribution declares explicit Prometheus buckets" do
    for %Telemetry.Metrics.Distribution{} = metric <- Newton.Metrics.definitions() do
      assert Keyword.has_key?(metric.reporter_options, :buckets),
             "#{inspect(metric.name)} needs reporter_options: [buckets: ...]"
    end
  end

  test "the IndexNow span is measured as a duration distribution tagged by result" do
    assert %Telemetry.Metrics.Distribution{} =
             indexnow =
             Enum.find(Newton.Metrics.definitions(), fn m ->
               m.event_name == [:newton, :indexnow, :submit, :stop]
             end)

    assert indexnow.measurement == :duration
    assert indexnow.tags == [:result]
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/newton/metrics_test.exs`
Expected: FAIL — `Newton.Metrics` is undefined.

- [ ] **Step 3: Implement `Newton.Metrics`**

Create `lib/newton/metrics.ex`:

```elixir
defmodule Newton.Metrics do
  @moduledoc """
  The single source of truth for custom app metrics. Both viewers consume this
  list: NewtonWeb.Telemetry (LiveDashboard, dev) and the PromEx adapter plugin
  (Prometheus/Fly Grafana, prod). Prometheus-exportable types only — never
  summary/2, which PromEx cannot export.
  """
  import Telemetry.Metrics

  @spec definitions() :: [Telemetry.Metrics.t()]
  def definitions do
    [
      distribution("newton.indexnow.submit.stop.duration",
        event_name: [:newton, :indexnow, :submit, :stop],
        measurement: :duration,
        unit: {:native, :millisecond},
        tags: [:result],
        reporter_options: [buckets: [10, 50, 100, 250, 500, 1_000, 2_500, 5_000]]
      )
    ]
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/newton/metrics_test.exs`
Expected: 3 tests, 0 failures.

- [ ] **Step 5: Splice into LiveDashboard, drop the summary**

In `lib/newton_web/telemetry.ex`, `def metrics do` — remove the IndexNow block at the top of the list:

```elixir
      # IndexNow Metrics
      summary("newton.indexnow.submit.stop.duration",
        unit: {:native, :millisecond},
        tags: [:result]
      ),

```

and change the end of the list to append the shared definitions:

```elixir
      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ] ++ Newton.Metrics.definitions()
  end
```

- [ ] **Step 6: Run the telemetry-adjacent suites**

Run: `mix test test/newton/metrics_test.exs test/newton/telemetry_test.exs test/newton/index_now_test.exs`
Expected: all pass (the IndexNow client tests assert telemetry events, not metric definitions, so they are unaffected).

- [ ] **Step 7: Commit (hunk-scoped for the shared file)**

`lib/newton_web/telemetry.ex` also carries an uncommitted hunk from the sitemap feature? **No** — the IndexNow summary being removed IS that feature's uncommitted hunk. Check first:

Run: `git diff lib/newton_web/telemetry.ex`

If the diff shows ONLY this plan's changes relative to the last commit (the summary block was never committed — it is part of the uncommitted sitemap feature), then after this task the file's total uncommitted diff = sitemap hunk + this task's changes, which cancel to just the `++ Newton.Metrics.definitions()` append. Stage the whole file ONLY if the resulting staged diff contains no `summary("newton.indexnow...` addition; otherwise stage by hunk (`git apply --cached` a filtered patch, as the controller directs).

```bash
git add lib/newton/metrics.ex test/newton/metrics_test.exs
# telemetry.ex staging per the check above — controller adjudicates
git commit -m "Declare custom metrics once in Newton.Metrics"
```

**Note for the controller:** this commit-ordering interaction (sitemap feature commits pending, this plan modifying the same region) means the controller may instead choose to hold this task's commit until the sitemap feature's four commits land. The implementer should report status and let the controller sequence commits.

---

### Task 2: PromEx — module, adapter plugin, config, fly.toml, scrape tests

**Files:**
- Modify: `mix.exs` (deps)
- Create: `lib/newton/prom_ex.ex`
- Create: `lib/newton/prom_ex/plugins/app.ex`
- Modify: `lib/newton/application.ex` (children, ~line 10)
- Modify: `config/prod.exs` (append)
- Modify: `fly.toml` (add `[metrics]` block)
- Test: `test/newton/prom_ex_test.exs`

**Interfaces:**
- Consumes: `Newton.Metrics.definitions/0` (Task 1).
- Produces: `Newton.PromEx` supervised process; `GET :9091/metrics` in prod.

- [ ] **Step 1: Add the dependency**

In `mix.exs`, in `defp deps`, after `{:xml_builder, "~> 2.4"}`:

```elixir
      {:xml_builder, "~> 2.4"},
      {:prom_ex, "~> 1.12"}
```

Run: `mix deps.get`
Expected: resolves `prom_ex 1.12.x` plus transitive deps (`telemetry_metrics_prometheus_core`, `octo_fetch`, etc.), updates `mix.lock`.

- [ ] **Step 2: Write the failing tests**

Create `test/newton/prom_ex_test.exs`:

```elixir
defmodule Newton.PromExTest do
  use NewtonWeb.ConnCase, async: false

  test "the shared IndexNow metric appears in the scrape after its event fires" do
    duration = System.convert_time_unit(120, :millisecond, :native)

    :telemetry.execute(
      [:newton, :indexnow, :submit, :stop],
      %{duration: duration},
      %{result: :ok, status: 200, url_count: 2}
    )

    metrics = PromEx.get_metrics(Newton.PromEx)

    assert metrics =~ "newton_indexnow_submit_stop_duration"
    assert metrics =~ ~s(result="ok")
  end

  test "a request through the endpoint lands in the Phoenix plugin's series", %{conn: conn} do
    get(conn, ~p"/")

    assert PromEx.get_metrics(Newton.PromEx) =~ "phoenix_"
  end
end
```

(`async: false`: PromEx's metrics store is a global accumulator; keeping this file serial avoids cross-test scrape noise.)

- [ ] **Step 3: Run tests to verify they fail**

Run: `mix test test/newton/prom_ex_test.exs`
Expected: FAIL — `Newton.PromEx` is not started / module undefined.

- [ ] **Step 4: Create the PromEx module**

Create `lib/newton/prom_ex.ex`:

```elixir
defmodule Newton.PromEx do
  use PromEx, otp_app: :newton

  alias PromEx.Plugins

  @impl true
  def plugins do
    [
      Plugins.Application,
      Plugins.Beam,
      {Plugins.Phoenix, router: NewtonWeb.Router, endpoint: NewtonWeb.Endpoint},
      {Plugins.Ecto, repos: [Newton.Repo]},
      Plugins.PhoenixLiveView,
      Newton.PromEx.Plugins.App
    ]
  end

  @impl true
  def dashboards, do: []
end
```

- [ ] **Step 5: Create the adapter plugin**

Create `lib/newton/prom_ex/plugins/app.ex`:

```elixir
defmodule Newton.PromEx.Plugins.App do
  @moduledoc "Feeds Newton.Metrics.definitions/0 to PromEx unchanged."
  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    [Event.build(:newton, Newton.Metrics.definitions())]
  end
end
```

- [ ] **Step 6: Supervise PromEx**

In `lib/newton/application.ex`, add `Newton.PromEx` as the FIRST child (PromEx docs: start it early to capture boot telemetry):

```elixir
    children = [
      Newton.PromEx,
      NewtonWeb.Telemetry,
```

- [ ] **Step 7: Prod config + fly.toml**

`config/prod.exs`, at the end:

```elixir
config :newton, Newton.PromEx, metrics_server: [port: 9091]
```

`fly.toml`, after the `[http_service]` block:

```toml
[metrics]
port = 9091
path = "/metrics"
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `mix test test/newton/prom_ex_test.exs`
Expected: 2 tests, 0 failures.

- [ ] **Step 9: Full suite + precommit**

Run: `mix test`
Expected: 0 failures.

Run: `mix precommit`
Expected: clean compile (no warnings), format, credo, tests, pnpm tests, dialyzer. Fix anything raised. If PromEx logs startup noise in test output (e.g. Grafana-disabled info lines), note it in the report — pristine output is the bar.

- [ ] **Step 10: Commit**

`lib/newton/application.ex` also carries the uncommitted sitemap-feature hunk (`Task.Supervisor`). Stage only this plan's hunk (the `Newton.PromEx` child line) — the controller adjudicates, same as Task 1's telemetry.ex.

```bash
git add mix.exs mix.lock lib/newton/prom_ex.ex lib/newton/prom_ex/plugins/app.ex config/prod.exs fly.toml test/newton/prom_ex_test.exs
# application.ex staging per the note above — controller adjudicates
git commit -m "Export metrics to Fly's Prometheus via PromEx"
```
