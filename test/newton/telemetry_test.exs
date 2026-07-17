defmodule Newton.TelemetryTest do
  use ExUnit.Case, async: true

  test "span emits [:newton | suffix] start/stop events and returns the fun's result" do
    ref =
      :telemetry_test.attach_event_handlers(self(), [
        [:newton, :demo, :op, :start],
        [:newton, :demo, :op, :stop]
      ])

    result = Newton.Telemetry.span(:demo, :op, %{items: 2}, fn -> {:done, %{result: :ok}} end)

    assert result == :done
    assert_received {[:newton, :demo, :op, :start], ^ref, %{}, %{items: 2}}
    assert_received {[:newton, :demo, :op, :stop], ^ref, %{duration: _}, %{result: :ok}}
  end
end
