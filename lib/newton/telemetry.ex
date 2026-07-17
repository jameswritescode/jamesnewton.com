defmodule Newton.Telemetry do
  @moduledoc """
  Emission facade for app telemetry: owns the [:newton, ...] event prefix so
  event names stay consistent. App code emits through here, never via raw
  :telemetry calls.
  """

  @spec span(atom(), atom(), map(), (-> {result, map()})) :: result when result: term()
  def span(subsystem, operation, start_metadata, fun) do
    :telemetry.span([:newton, subsystem, operation], start_metadata, fun)
  end
end
