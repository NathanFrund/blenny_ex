defmodule Blenny.Bootstrap do
  @moduledoc """
  Orchestrates the Blenny boot sequence.

  Can be started in the supervision tree or called via `boot/0` for backward
  compatibility. The boot sequence is split into three phases:

   1. **Synchronous (in `init/1`)** — config validation, registry checks,
      module discovery, capability validation, and module `initialize/1`
      callbacks. All fast, in-memory operations that must complete before
      the next child starts.

   2. **Asynchronous (via `:start_supervised` message)** — starting background
      processes (GenServers, metrics loops) under `ModuleSupervisor`. This
      avoids blocking the supervisor during potentially slow `child_spec` /
      `GenServer.init` operations.

   3. **Asynchronous (via `:wire_subscriptions` message)** — wiring PubSub
      subscriptions for modules that define `subscriptions/0`. This runs
      after module processes are started so they can subscribe directly.

  ## Supervision tree usage (recommended)

      children = [
        Blenny.AuthRegistry,
        {Registry, keys: :unique, name: Blenny.ModuleRegistry},
        {DynamicSupervisor, name: Blenny.ModuleSupervisor, strategy: :one_for_one},
        Blenny.Bootstrap,
        {Blenny.Hub, [name: Blenny.Hub]},
        MyAppWeb.Endpoint
      ]

  Bootstrap stops itself after boot completes. Because it uses
  `restart: :temporary`, the supervisor will not restart it.

  ## Legacy `boot/0` usage

      {:ok, sup} = Supervisor.start_link(children, opts)
      Blenny.Bootstrap.boot()
      {:ok, sup}

  The `boot/0` function starts the GenServer and blocks until boot completes
  or fails.
  """

  use GenServer

  require Logger

  # ── Public API ──────────────────────────────────────────────────

  @doc """
  Starts the Bootstrap GenServer.

  `init/1` validates configuration synchronously (fast), then sends a
  `:boot` message to perform module initialization asynchronously.
  """
  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Starts the Bootstrap GenServer and blocks until the boot sequence
  completes (or raises on failure).

  Provided for backward compatibility with host apps that call
  `Blenny.Bootstrap.boot()` after `Supervisor.start_link`.
  """
  @spec boot() :: :ok
  def boot do
    # Use GenServer.start (no link) so init failures don't crash the caller
    case GenServer.start(__MODULE__, [], name: __MODULE__) do
      {:ok, pid} ->
        ref = Process.monitor(pid)

        receive do
          {:DOWN, ^ref, :process, ^pid, :normal} ->
            :ok

          {:DOWN, ^ref, :process, ^pid, {exception, _stacktrace}}
          when is_exception(exception) ->
            raise exception

          {:DOWN, ^ref, :process, ^pid, {:shutdown, _}} ->
            :ok

          {:DOWN, ^ref, :process, ^pid, _reason} ->
            :ok
        end

      {:error, reason} ->
        raise reason
    end
  end

  @doc false
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary,
      type: :worker
    }
  end

  # ── GenServer callbacks ────────────────────────────────────────

  @impl true
  def init(_opts) do
    Blenny.Config.validate!()

    with :ok <- try_ensure_running(Blenny.ModuleRegistry, "Blenny.ModuleRegistry"),
         :ok <- try_ensure_running(Blenny.ModuleSupervisor, "Blenny.ModuleSupervisor") do
      modules = Blenny.Module.Loader.modules()
      Blenny.Module.Loader.validate!(modules)

      app_state = %{pub_sub: Blenny.pub_sub()}
      Blenny.Module.Lifecycle.initialize_all(modules, app_state)

      names = Enum.map_join(modules, ", ", & &1.name())
      Logger.info("Blenny boot complete — loaded: #{names}")

      send(self(), :start_supervised)
      {:ok, %{modules: modules}}
    else
      {:error, msg} -> {:stop, msg}
    end
  end

  @impl true
  def handle_info(:start_supervised, %{modules: modules}) do
    Blenny.Module.Lifecycle.start_supervised(modules, Blenny.ModuleSupervisor)
    send(self(), :wire_subscriptions)
    {:noreply, %{modules: modules}}
  end

  @impl true
  def handle_info(:wire_subscriptions, %{modules: modules}) do
    Blenny.Module.Lifecycle.wire_subscriptions(modules)
    {:stop, :normal, :done}
  end

  defp try_ensure_running(name, label) do
    case Process.whereis(name) do
      nil ->
        {:error,
         """
         #{label} is not running.

         Add it to your application's supervision tree before calling Blenny.Bootstrap.boot/0:

             children = [
               {Registry, keys: :unique, name: Blenny.ModuleRegistry},
               {DynamicSupervisor, name: Blenny.ModuleSupervisor, strategy: :one_for_one},
               ...
             ]
         """}

      _pid ->
        :ok
    end
  end
end
