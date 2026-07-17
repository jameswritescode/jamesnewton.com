defmodule Newton.PromEx.Plugins.App do
  @moduledoc "Feeds Newton.Metrics.definitions/0 to PromEx unchanged."
  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    [Event.build(:newton, Newton.Metrics.definitions())]
  end
end
