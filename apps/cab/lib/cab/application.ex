defmodule Cab.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      CabWeb.Telemetry,
      Cab.Repo,
      {DNSCluster, query: Application.get_env(:cab, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Cab.PubSub},
      Cab.Standings.Cache,
      # Start a worker by calling: Cab.Worker.start_link(arg)
      # {Cab.Worker, arg},
      # Start to serve requests, typically the last entry
      CabWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Cab.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CabWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
