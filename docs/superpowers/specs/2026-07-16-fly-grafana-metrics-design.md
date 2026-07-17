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
- **LiveDashboard and `Newton.Telemetry` stay as-is.** PromEx is an additional
  consumer of the same telemetry events; emission code does not change. The
  IndexNow `summary` in `NewtonWeb.Telemetry` is kept (dev viewer) alongside
  the new PromEx declaration (prod viewer) — the "one emitter, two metric
  declarations" pattern now recorded in AGENTS.md's Observability section.

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
  Newton.PromEx.Plugins.IndexNow
]
```

`dashboards/0` returns `[]`. Supervision: `Newton.PromEx` added to
`Newton.Application` children before `NewtonWeb.Endpoint` (PromEx docs: start
early so it captures boot telemetry).

### 2. `Newton.PromEx.Plugins.IndexNow` (`lib/newton/prom_ex/plugins/index_now.ex`)

A `PromEx.Plugin` declaring one event metric:

- `distribution` on event `[:newton, :indexnow, :submit, :stop]`, measurement
  `:duration`, unit `{:native, :millisecond}`, tags `[:result]` (bounded per
  AGENTS.md), buckets `[10, 50, 100, 250, 500, 1_000, 2_500, 5_000]` ms.
- The histogram's `_count` series doubles as submissions-by-result counter.
- Flat until IndexNow's prod flag is re-enabled at launch; wired now so no
  observability work is needed then.

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

Already updated (Observability section: "one emitter, two metric
declarations") — no further doc work.

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

1. After executing a `[:newton, :indexnow, :submit, :stop]` telemetry event
   (via `:telemetry.execute/3` in the test), the scrape text from
   `PromEx.get_metrics(Newton.PromEx)` contains the IndexNow series with a
   `result` tag.
2. The scrape text contains core plugin families (a `beam_` series and a
   `phoenix_` series), proving the plugin set is live.

## Deploy verification

After the next deploy: fly-metrics.net → the app → Explore → query a
`phoenix_*` or `newton_*` series and see datapoints from the staging host.
