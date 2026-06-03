defmodule Blenny.Module do
  @moduledoc """
  Behaviour for Blenny modules.

  Modules are automatically discovered at compile time. Each module defines
  routes, capabilities, and optionally a background process via `child_spec/1`.

  ## Declarative Modules (no process)

  Most modules are purely declarative — they define routes and capabilities
  but don't need a long-running process:

      defmodule MyApp.Blenny.Dashboard do
        use Blenny.Module

        @impl true
        def name, do: "dashboard"

        @impl true
        def routes do
          [
            %{method: :get, path: "/dashboard", handler: &MyAppWeb.DashboardController.index/2}
          ]
        end

        @impl true
        def capabilities, do: []
      end

  ## Stateful Modules (background process)

  Modules that need a background process (metrics loops, timers, state
  machines) implement `child_spec/1` returning a standard OTP child spec.
  The framework starts them under `Blenny.ModuleSupervisor`:

      defmodule MyApp.Blenny.Dashboard do
        use Blenny.Module
        use GenServer

        @impl true
        def name, do: "dashboard"

        @impl true
        def routes, do: [...]

        @impl true
        def child_spec(_opts) do
          %{
            id: __MODULE__,
            start: {__MODULE__, :start_link, []},
            restart: :permanent,
            type: :worker
          }
        end

        def start_link(opts) do
          GenServer.start_link(__MODULE__, opts,
            name: {:via, Registry, {Blenny.ModuleRegistry, {:global, __MODULE__}}}
          )
        end

        @impl true
        def init(_opts) do
          schedule_tick()
          {:ok, %{cpu: 0, mem: 0}}
        end

        def handle_info(:tick, state) do
          # ...
          {:noreply, state}
        end
      end
  """

  @type route :: %{
          required(:method) => :get | :post | :put | :delete | :patch,
          required(:path) => String.t(),
          required(:handler) => atom(),
          optional(:auth) => boolean() | String.t()
        }

  @type subscription :: %{
          required(:topic) => String.t(),
          required(:handler) => function()
        }

  @type state :: map()

  @doc """
  Unique module name string.
  """
  @callback name() :: String.t()

  @doc """
  List of HTTP routes this module provides.

  Each route is a map with `:method`, `:path`, and `:handler`.
  Optionally `:auth` can be `true` (requires any auth) or a role string.
  """
  @callback routes() :: [route()]

  @doc """
  List of capability strings this module provides (e.g. `["auth"]`).
  Used for boot-time conflict detection.
  """
  @callback capabilities() :: [String.t()]

  @doc """
  List of event subscriptions for the typed PubSub event bus.

  The handler receives the decoded payload map.
  """
  @callback subscriptions() :: [subscription()]

  @doc """
  Called during boot after all modules are discovered and before routes are registered.

  Receives the app state map which may contain `:pub_sub`, `:hub`, `:config`, etc.
  """
  @callback initialize(state()) :: :ok | {:error, term()}

  @doc """
  Returns a child spec for starting this module under `Blenny.ModuleSupervisor`.

  Return `:skip` (the default) for purely declarative modules that don't need
  a background process. Return a `Supervisor.child_spec()` for stateful modules
  that need supervised lifecycle (GenServer, Task, etc.).
  """
  @callback child_spec(keyword()) :: :skip | Supervisor.child_spec()

  @optional_callbacks initialize: 1, child_spec: 1

  defmacro __using__(_opts) do
    quote do
      @behaviour Blenny.Module
      @after_compile Blenny.Module

      @doc false
      def child_spec(_opts), do: :skip
    end
  end

  @doc false
  def __after_compile__(env, _bytecode) do
    mod = env.module
    mods = Application.get_env(:blenny_ex, :registered_modules, [])
    Application.put_env(:blenny_ex, :registered_modules, [mod | mods])
  end
end
