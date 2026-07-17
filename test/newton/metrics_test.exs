defmodule Newton.MetricsTest do
  use ExUnit.Case, async: true

  test "definitions use only Prometheus-exportable metric types" do
    definitions = Newton.Metrics.definitions()

    refute Enum.empty?(definitions)

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

    assert is_function(indexnow.measurement, 1),
           "measurement must be a function that extracts duration from the event"

    # The measurement fun also converts native time units to milliseconds
    assert indexnow.measurement.(%{duration: 1_000_000}) == 1
    assert indexnow.tags == [:result]

    assert Keyword.get(indexnow.reporter_options, :buckets) ==
             [10, 50, 100, 250, 500, 1_000, 2_500, 5_000]
  end
end
