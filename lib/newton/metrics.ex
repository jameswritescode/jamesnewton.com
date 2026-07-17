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
        unit: {:native, :millisecond},
        tags: [:result],
        reporter_options: [buckets: [10, 50, 100, 250, 500, 1_000, 2_500, 5_000]]
      )
    ]
  end
end
