# Fly Grafana Metrics Design

**Goal:** App-level metrics (Phoenix, Ecto, BEAM, IndexNow) visible in Fly.io's
managed Grafana (`fly-metrics.net`) for the staging app, starting with the next
deploy.

**Context:** Fly's managed Prometheus scrapes any app that declares a
`[metrics]` section in `fly.toml`; results appear in the managed Grafana
automatically. The app currently exposes nothing in Prometheus format —
telemetry is consumed only by LiveDashboard in dev.

## Decisions

- **PromEx (~> 1.12)** over `telemetry_metrics_prometheus`: the lightweight
  option cannot export `summary()` metrics — and `NewtonWeb.Telemetry.metrics/0`
  is entirely summaries — so it would force a rework of every metric anyway.
  PromEx ships maintained plugins (Phoenix, Ecto, BEAM, LiveView) with proper
  Prometheus histogram/counter definitions and pre-built dashboard JSONs.
- **Standalone metrics server on port 9091, prod-only.** Enabled in
  `config/prod.exs`; disabled (PromEx default) in dev/test so nothing binds
  local ports or collides in CI. `/metrics` never touches the public HTTP
  service — Fly's Prometheus scrapes machines over the private network.
- **No Grafana auto-upload.** Fly's managed Grafana doesn't take API-token
  dashboard provisioning. `dashboards/0` returns `[]`; if the pre-built
  dashboards prove wanted, export JSONs via `mix prom_ex.dashboard.export` and
  import manually in the UI. Start with Explore.
- **Custom metrics are declared once, in `Newton.Metrics`.** Research finding:
  `use PromEx.Plugin` imports `Telemetry.Metrics`'s own constructors
  (`counter/2`, `distribution/2`, `last_value/2`, `sum/2`) — PromEx plugin
  metrics ARE `Telemetry.Metrics` structs, the same structs LiveDashboard
  consumes. No bridge library exists in the ecosystem (the documented stance is
  coexistence as independent handlers), but a shared definitions module gives a
  single source of truth: `NewtonWeb.Telemetry.metrics/0` splices it in for
  LiveDashboard, and one generic adapter plugin feeds it to PromEx. Constraint:
  the shared list may use only the intersection of types — no `summary()`
  (PromEx deliberately excludes it; Prometheus cannot represent client-side
  summaries); distributions carry explicit `reporter_options: [buckets: ...]`
  (Prometheus needs them, LiveDashboard ignores them). The existing IndexNow
  `summary` in `NewtonWeb.Telemetry` is therefore **replaced** by a shared
  `distribution` — strictly better (histograms give percentiles in Grafana).
  Emission code (`Newton.Telemetry`) does not change. AGENTS.md's Observability
  section records the rule: declare once, in `Newton.Metrics.definitions/0`.

## Components

### 1. `Newton.PromEx` (`lib/newton/prom_ex.ex`)

```elixir
use PromEx, otp_app: :newton
```

Plugins:

```elixir
[
  PromEx.Plugins.Application,
  PromEx.Plugins.Beam,
  {PromEx.Plugins.Phoenix, router: NewtonWeb.Router, endpoint: NewtonWeb.Endpoint},
  {PromEx.Plugins.Ecto, repos: [Newton.Repo]},
  PromEx.Plugins.PhoenixLiveView,
  Newton.PromEx.Plugins.App
]
```

`dashboards/0` returns `[]`. Supervision: `Newton.PromEx` added to
`Newton.Application` children before `NewtonWeb.Endpoint` (PromEx docs: start
early so it captures boot telemetry).

### 2. `Newton.Metrics` (`lib/newton/metrics.ex`) — single source of truth

Every custom app metric lives here, as plain `Telemetry.Metrics` structs:

```elixir
defmodule Newton.Metrics do
  import Telemetry.Metrics

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

Tags stay bounded per AGENTS.md. The histogram's `_count` series doubles as a
submissions-by-result counter. Flat until IndexNow's prod flag is re-enabled at
launch; wired now so no observability work is needed then.

Consumers:

- `NewtonWeb.Telemetry.metrics/0` appends `Newton.Metrics.definitions()` and
  **drops its IndexNow `summary`** (replaced by the shared distribution).
- `Newton.PromEx.Plugins.App` (`lib/newton/prom_ex/plugins/app.ex`) — the
  generic adapter, written once, never per-metric:

  ```elixir
  defmodule Newton.PromEx.Plugins.App do
    use PromEx.Plugin

    @impl true
    def event_metrics(_opts) do
      [Event.build(:newton, Newton.Metrics.definitions())]
    end
  end
  ```

### 3. Configuration

- `config/config.exs`: none needed (PromEx defaults: grafana `:disabled`,
  metrics server `:disabled`).
- `config/prod.exs`:

  ```elixir
  config :newton, Newton.PromEx,
    metrics_server: [port: 9091]
  ```

### 4. `fly.toml`

```toml
[metrics]
  port = 9091
  path = "/metrics"
```

### 5. AGENTS.md

Already updated (Observability section: declare custom metrics once in
`Newton.Metrics.definitions/0`; Prometheus-exportable types only, never
`summary`) — no further doc work.

## Out of scope

- Grafana dashboard import (manual, optional, post-deploy).
- Alerting.
- OpenTelemetry tracing (unchanged from the sitemap spec's decision: no trace
  backend exists).
- Re-enabling IndexNow (separate launch decision).

## Error handling

PromEx runs as its own supervised subtree; a metrics failure never affects
request serving. The prod metrics server binds a port Fly does not expose
publicly. No new failure modes in app code paths.

## Testing

Behavior-level, no test binds the real 9091 server:

1. Guard on the shared list: every `Newton.Metrics.definitions/0` entry is a
   Prometheus-exportable type (no `Telemetry.Metrics.Summary`), and every
   distribution carries `reporter_options[:buckets]` — this is the rule that
   keeps the single-source pattern working, enforced by test rather than by
   review vigilance.
2. After executing a `[:newton, :indexnow, :submit, :stop]` telemetry event
   (via `:telemetry.execute/3` in the test), the scrape text from
   `PromEx.get_metrics(Newton.PromEx)` contains the IndexNow series with a
   `result` tag.
3. After a request through the endpoint (ConnCase `get "/"`), the scrape text
   contains a `phoenix_` series, proving the built-in plugin set is live.
   (Beam-plugin series are polled on an interval, so they are not asserted —
   nondeterministic at test time.)

## Deploy verification

After the next deploy: fly-metrics.net → the app → Explore → query a
`phoenix_*` or `newton_*` series and see datapoints from the staging host.
