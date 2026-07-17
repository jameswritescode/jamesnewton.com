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
