defmodule BlennyTestApp.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BlennyTestAppWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:blenny_test_app, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: BlennyTestApp.PubSub},
      {Registry, keys: :unique, name: Blenny.ModuleRegistry},
      {DynamicSupervisor, name: Blenny.ModuleSupervisor, strategy: :one_for_one},
      {Blenny.Hub, [name: Blenny.Hub, pub_sub: BlennyTestApp.PubSub]},
      BlennyTestAppWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: BlennyTestApp.Supervisor]
    {:ok, sup} = Supervisor.start_link(children, opts)

    Blenny.Bootstrap.boot()

    {:ok, sup}
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BlennyTestAppWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
