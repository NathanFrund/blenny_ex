defmodule Blenny.Bootstrap do
  @moduledoc """
  Orchestrates the Blenny boot sequence.

  Called from the host application's `Application.start/2`.

  ## Boot Sequence

  1. Discover and validate modules
  2. Initialize modules
  3. Start modules

  ## Usage

      defmodule MyApp.Application do
        use Application

        def start(_type, _args) do
          children = [
            {Blenny.Hub, [name: Blenny.Hub]},
            BlennyTestAppWeb.Endpoint
          ]

          opts = [strategy: :one_for_one, name: MyApp.Supervisor]
          {:ok, sup} = Supervisor.start_link(children, opts)

          Blenny.Bootstrap.boot()
          {:ok, sup}
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
    modules = Blenny.Module.Loader.modules()

    app_state = %{
      pub_sub: Blenny.pub_sub()
    }

    Blenny.Module.Loader.validate!(modules)
    Blenny.Module.Lifecycle.initialize_all(modules, app_state)
    Blenny.Module.Lifecycle.start_all(modules)

    Logger.info("Blenny boot complete — #{Enum.count(modules)} module(s) loaded")
    :ok
  end

  @doc """
  Stops all modules gracefully.
  """
  @spec shutdown([module()]) :: :ok
  def shutdown(modules \\ Blenny.Module.Loader.modules()) do
    Blenny.Module.Lifecycle.stop_all(modules)
    :ok
  end
end
