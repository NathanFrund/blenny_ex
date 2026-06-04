defmodule BlennyExampleApp.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BlennyExampleAppWeb.Telemetry,
      {DNSCluster,
       query: Application.get_env(:blenny_example_app, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: BlennyExampleApp.PubSub},
      Blenny.AuthRegistry,
      {Registry, keys: :unique, name: Blenny.ModuleRegistry},
      {DynamicSupervisor, name: Blenny.ModuleSupervisor, strategy: :one_for_one},
      Blenny.Bootstrap,
      {Blenny.Hub, [name: Blenny.Hub, pub_sub: BlennyExampleApp.PubSub]},
      BlennyExampleAppWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: BlennyExampleApp.Supervisor]
    {:ok, _sup} = Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BlennyExampleAppWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
