defmodule Blenny.Bootstrap do
  @moduledoc """
  Orchestrates the Blenny boot sequence.

  Called from the host application's `Application.start/2` after the
  supervision tree is running.

  ## Boot Sequence

  1. Discover and validate modules
  2. Initialize modules
  3. Start supervised modules under `Blenny.ModuleSupervisor`

  ## Requirements

  The host application's supervision tree must include:

      {Registry, keys: :unique, name: Blenny.ModuleRegistry}
      {DynamicSupervisor, name: Blenny.ModuleSupervisor, strategy: :one_for_one}

  ## Usage

      defmodule MyApp.Application do
        use Application

        def start(_type, _args) do
          children = [
            {Registry, keys: :unique, name: Blenny.ModuleRegistry},
            {DynamicSupervisor, name: Blenny.ModuleSupervisor, strategy: :one_for_one},
            {Blenny.Hub, [name: Blenny.Hub]},
            MyAppWeb.Endpoint
          ]

          opts = [strategy: :one_for_one, name: MyApp.Supervisor]
          {:ok, _sup} = Supervisor.start_link(children, opts)

          Blenny.Bootstrap.boot()
        end
      end
  """

  require Logger

  @doc """
  Runs the full boot sequence after the supervision tree is started.

  Returns `:ok`.
  """
  @spec boot() :: :ok
  def boot do
    Blenny.Config.validate!()

    modules = Blenny.Module.Loader.modules()

    ensure_running!(Blenny.ModuleRegistry, "Blenny.ModuleRegistry")
    ensure_running!(Blenny.ModuleSupervisor, "Blenny.ModuleSupervisor")

    Blenny.AuthRegistry.start()

    app_state = %{
      pub_sub: Blenny.pub_sub()
    }

    Blenny.Module.Loader.validate!(modules)
    Blenny.Module.Lifecycle.initialize_all(modules, app_state)
    Blenny.Module.Lifecycle.start_supervised(modules, Blenny.ModuleSupervisor)

    names = Enum.map_join(modules, ", ", & &1.name())
    Logger.info("Blenny boot complete — loaded: #{names}")
    :ok
  end

  defp ensure_running!(name, label) do
    case Process.whereis(name) do
      nil ->
        raise """
        #{label} is not running.

        Add it to your application's supervision tree before calling Blenny.Bootstrap.boot/0:

            children = [
              {Registry, keys: :unique, name: Blenny.ModuleRegistry},
              {DynamicSupervisor, name: Blenny.ModuleSupervisor, strategy: :one_for_one},
              ...
            ]
        """

      _pid ->
        :ok
    end
  end
end
