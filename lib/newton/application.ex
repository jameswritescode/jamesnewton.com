defmodule Newton.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Newton.PromEx,
      NewtonWeb.Telemetry,
      Newton.Repo,
      {DNSCluster, query: Application.get_env(:newton, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Newton.PubSub},
      {Task.Supervisor, name: Newton.TaskSupervisor},
      Newton.Analytics.Collector,
      Newton.SocialCard.Cache,
      # Start to serve requests, typically the last entry
      NewtonWeb.Endpoint,
      {Newton.MCP.Server,
       transport: {:streamable_http, start: true},
       authorization: [
         authorization_servers: [
           Newton.OAuth.canonical_resource() |> String.trim_trailing("/mcp")
         ],
         resource: Newton.OAuth.canonical_resource(),
         validator: {Newton.MCP.TokenValidator, []}
       ]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Newton.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    NewtonWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
