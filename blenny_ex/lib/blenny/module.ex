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

  @type route ::
          {:http, method(), path :: String.t(), plug :: module(), opts :: term()}
          | {:http, method(), path :: String.t(), plug :: module(), opts :: term(), keyword()}
          | {:live, path :: String.t(), live_view :: module()}
          | {:live, path :: String.t(), live_view :: module(), term()}

  @type method :: :get | :post | :put | :patch | :delete

  @type subscription :: %{
          required(:topic) => String.t(),
          required(:handler) => function()
        }

  @type state :: map()

  @doc """
  List of routes this module provides.

  Routes must be declared via `@blenny_routes` (module attribute with
  `accumulate: true`) AND returned from `routes/0`. The attribute enables
  compile-time route discovery for `Blenny.Router.blenny_modules/2`.

  ## HTTP Routes

      @blenny_routes {:http, :get, "/signin", __MODULE__, :render_sign_in}
      @blenny_routes {:http, :post, "/avatar", __MODULE__, :handle_avatar}

  ## LiveView Routes

      @blenny_routes {:live, "/dashboard", MyAppWeb.DashboardLive}
      @blenny_routes {:live, "/dashboard", MyAppWeb.DashboardLive, :index}

  ## Auth-Protected Routes

  Append an opts keyword list with `auth: true`:

      @blenny_routes {:http, :post, "/avatar", __MODULE__, :handle_avatar, [auth: true]}
      @blenny_routes {:live, "/admin", AdminLive, [auth: true]}

  Routes tagged `auth: true` are automatically wrapped with
  `Blenny.Plug.RequireUser` when mounted via `blenny_modules/2`.
  """
  @callback name() :: String.t()

  @doc """
  List of HTTP routes this module provides.

  Each route can be a map or tuple:

      # Map format
      %{method: :get, path: "/signin", handler: :render_sign_in}
      %{method: :post, path: "/avatar", handler: :handle_avatar, auth: true}

      # Tuple format
      {:get, "/signin", :render_sign_in}
      {:post, "/avatar", :handle_avatar, [auth: true]}

  The handler must be an atom (controller action name). Routes tagged with
  `auth: true` are automatically wrapped with `Blenny.Plug.RequireUser`
  when mounted via `Blenny.Router.blenny_modules/1`.
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

  @doc """
  Returns auth provider metadata.

  Only meaningful for modules with `capabilities: ["auth"]`. Returns a keyword
  list with:

    - `:login_route` — path to redirect unauthenticated users (default: `"/auth/signin"`)
  """
  @callback auth() :: keyword()

  @optional_callbacks initialize: 1, child_spec: 1, auth: 0

  defmacro __using__(_opts) do
    quote do
      @behaviour Blenny.Module
      Module.register_attribute(__MODULE__, :blenny_routes, accumulate: true)
      @before_compile {Blenny.Module, :register_module}

      @doc false
      def child_spec(_opts), do: :skip
    end
  end

  @doc false
  def register_module(env) do
    mod = env.module
    mods = Application.get_env(:blenny_ex, :registered_modules, [])
    Application.put_env(:blenny_ex, :registered_modules, [mod | mods])

    routes = Module.get_attribute(mod, :blenny_routes) |> Enum.reverse()
    all_routes = Application.get_env(:blenny_ex, :module_routes, [])
    Application.put_env(:blenny_ex, :module_routes, [{mod, routes} | all_routes])
  end
end
