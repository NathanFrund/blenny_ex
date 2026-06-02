defmodule Blenny.Module do
  @moduledoc """
  Behaviour for Blenny modules.

  Modules are automatically discovered at compile time. Each module defines
  routes, capabilities, event subscriptions, and lifecycle hooks.

  ## Example

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

        @impl true
        def subscriptions do
          [%{topic: "metrics:update", handler: &handle_metrics/1}]
        end

        @impl true
        def initialize(state) do
          :ok
        end

        @impl true
        def start, do: :ok

        @impl true
        def stop, do: :ok
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
  Called after all modules have been initialized and routes are registered.
  Use for starting background tasks, timers, etc.
  """
  @callback start() :: :ok | {:error, term()}

  @doc """
  Called during shutdown in reverse initialization order.
  Use for cleaning up timers, closing connections, etc.
  """
  @callback stop() :: :ok | {:error, term()}

  @optional_callbacks initialize: 1, start: 0, stop: 0

  defmacro __using__(_opts) do
    quote do
      @behaviour Blenny.Module
      @after_compile Blenny.Module
    end
  end

  @doc false
  def __after_compile__(env, _bytecode) do
    mod = env.module
    mods = Application.get_env(:blenny_ex, :registered_modules, [])
    Application.put_env(:blenny_ex, :registered_modules, [mod | mods])
  end
end
