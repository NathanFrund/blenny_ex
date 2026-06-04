# BlennyEx

Multi-transport hypermedia engine for Phoenix — SSE (Datastar) and LiveView.

Write unified HTML components that deliver over Server-Sent Events or LiveView
WebSockets, routing transport based on the client's runtime environment.

## Installation

```elixir
def deps do
  [
    {:blenny_ex, "~> 0.1.0"}
  ]
end
```

In an umbrella app or monorepo:

```elixir
def deps do
  [
    {:blenny_ex, path: "../blenny_ex"}
  ]
end
```

## Quickstart

These steps wire Blenny into a new Phoenix app. They assume you've already
generated an app with `mix phx.new my_app`.

### Step 1: Configure PubSub

Blenny needs your app's `Phoenix.PubSub` adapter. Add this to
`config/config.exs`:

```elixir
config :blenny_ex, pub_sub: MyApp.PubSub
```

### Step 2: Update the supervision tree

Open `lib/my_app/application.ex`. Add `Blenny.ModuleRegistry`,
`Blenny.ModuleSupervisor`, and `Blenny.Hub` before your Endpoint:

```elixir
def start(_type, _args) do
  children = [
    MyAppWeb.Telemetry,
    {Phoenix.PubSub, name: MyApp.PubSub},
    {Registry, keys: :unique, name: Blenny.ModuleRegistry},
    {DynamicSupervisor, name: Blenny.ModuleSupervisor, strategy: :one_for_one},
    MyAppWeb.Endpoint,
    {Blenny.Hub, [name: Blenny.Hub, shutdown: 35_000]}
  ]

  opts = [strategy: :one_for_one, name: MyApp.Supervisor]
  {:ok, sup} = Supervisor.start_link(children, opts)

  Blenny.Bootstrap.boot()

  {:ok, sup}
end
```

The `boot/0` call discovers Blenny modules, validates them, runs their
`initialize/1` callbacks, and starts any supervised child processes.

### Step 3: Add the session plug

Open `lib/my_app_web/router.ex` and add `Blenny.Plug.FetchSession` to your
browser pipeline, **after** `fetch_session`:

```elixir
pipeline :browser do
  plug :accepts, ["html"]
  plug :fetch_session
  plug Blenny.Plug.FetchSession
  plug :fetch_live_flash
  plug :put_root_layout, html: {MyAppWeb.Layouts, :root}
  plug :protect_from_forgery
  plug :put_secure_browser_headers
end
```

`FetchSession` delegates to the registered auth module (if any) to restore the
current user from the session cookie.

### Step 4: Add the request logger

Add `Blenny.Plug.RequestLogger` to your browser pipeline, after `FetchSession`:

```elixir
pipeline :browser do
  plug :accepts, ["html"]
  plug :fetch_session
  plug Blenny.Plug.FetchSession
  plug Blenny.Plug.RequestLogger
  plug :fetch_live_flash
  plug :put_root_layout, html: {MyAppWeb.Layouts, :root}
  plug :protect_from_forgery
  plug :put_secure_browser_headers
end
```

`RequestLogger` logs each completed request with method, path, status, and
duration. Pass options as the second argument:

```elixir
plug Blenny.Plug.RequestLogger, log_level: :warning, exclude_paths: ["/health"]
```

Set `log_level: false` to disable, or `exclude_paths` to skip health checks
and other noise routes.

### Step 5: Import the router macro

Still in `router.ex`, add the import:

```elixir
import Blenny.Router
```

### Step 6: Define your first module

Create `lib/my_app/blenny/dashboard_module.ex`:

```elixir
defmodule MyApp.Blenny.DashboardModule do
  use Blenny.Module

  @impl true
  def name, do: "dashboard"

  @blenny_routes {:live, "/dashboard", MyAppWeb.DashboardLive}

  @impl true
  def routes, do: @blenny_routes

  @impl true
  def capabilities, do: []
end
```

Routes are declared via the `@blenny_routes` attribute (accumulated) and
returned by the `routes/0` callback. Supported formats:

```elixir
# HTTP route
@blenny_routes {:http, :get, "/path", MyAppWeb.SomeController, :action}

# HTTP route with auth protection
@blenny_routes {:http, :post, "/path", MyAppWeb.SomeController, :action, [auth: true]}

# LiveView route
@blenny_routes {:live, "/path", MyAppWeb.SomeLive}

# LiveView route with action
@blenny_routes {:live, "/path", MyAppWeb.SomeLive, :index}

# LiveView route with auth protection
@blenny_routes {:live, "/admin", MyAppWeb.AdminLive, [auth: true]}
```

### Step 7: Wire the routes

Add a scope in `router.ex` that uses `blenny_modules/2`:

```elixir
scope "/" do
  pipe_through :browser

  blenny_modules("",
    modules: [
      MyApp.Blenny.DashboardModule
    ]
  )
end
```

The first argument is a path prefix. The `:modules` list tells Blenny which
modules to mount. Auth-protected routes are automatically wrapped with
`RequireUser`.

### Step 8: Add the SSE endpoint

Outside the browser scope, add the SSE plug:

```elixir
get "/sse", Blenny.Transport.SSEPlug, []
```

This establishes long-lived SSE connections using the Datastar wire format.
Clients connect with optional `?intent=ui,command&user_id=xxx` query params.

### Step 9: Create a LiveView

Create `lib/my_app_web/dashboard_live.ex` that receives real-time updates from
Blenny modules:

```elixir
defmodule MyAppWeb.DashboardLive do
  use MyAppWeb, :live_view
  use Blenny.Transport.LiveViewBridge, intents: [:ui]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, cpu: 0.0, mem: 0.0)}
  end

  @impl true
  def handle_info({:blenny_msg, _intent, payload}, socket) do
    socket =
      if payload[:signals] do
        assign(socket,
          cpu: payload[:signals]["cpu"],
          mem: payload[:signals]["mem"]
        )
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div>CPU: {@cpu}% | Memory: {@mem} MB</div>
    </Layouts.app>
    """
  end
end
```

The `LiveViewBridge` `on_mount` hook registers the connection with the Hub,
subscribes to PubSub topics, and tears down on unmount. Your `handle_info`
clause receives `{:blenny_msg, intent, payload}` tuples.

### Step 10: Publish data from a module

Make the dashboard module stateful so it emits metrics periodically:

```elixir
defmodule MyApp.Blenny.DashboardModule do
  use Blenny.Module
  use GenServer

  @impl true
  def name, do: "dashboard"

  @blenny_routes {:live, "/dashboard", MyAppWeb.DashboardLive}

  @impl true
  def routes, do: @blenny_routes

  @impl true
  def capabilities, do: []

  @impl true
  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [[]]},
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
    {:ok, %{}}
  end

  @impl true
  def handle_info(:tick, state) do
    Blenny.Publisher.broadcast_data(%{"cpu" => 42.0, "mem" => 128.5})
    schedule_tick()
    {:noreply, state}
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, 2_000)
  end
end
```

Use `Blenny.Publisher` to send data — it handles routing to the right PubSub
topics (`:ui` intents, per-user topics, etc.).

## Module Types

| Type | child_spec/1 | Process | Use case |
|------|-------------|---------|----------|
| **Declarative** | `:skip` (default) | None | Static routes, templates |
| **Stateful** | OTP child spec | Supervised under `Blenny.ModuleSupervisor` | Metrics loops, timers, state machines |

## Architecture

```
┌─────────────┐     ┌──────────────┐     ┌─────────────────┐
│  Publisher   │────>│  PubSub Bus  │────>│  Hub (GenServer) │
└─────────────┘     └──────────────┘     └────────┬────────┘
                                                   │
                     ┌─────────────────────────────┼─────┐
                     │                             │     │
                     ▼                             ▼     │
           ┌─────────────────┐          ┌──────────────────┐
           │  SSEPlug         │          │ LiveViewBridge   │
           │  (Bandit chunk)  │          │ (on_mount hook)  │
           └─────────────────┘          └──────────────────┘
```

- **Blenny.Module** — behaviour for defining reusable modules (routes, capabilities, lifecycle)
- **Blenny.Publisher** — `broadcast_data/1`, `broadcast_html/1`, `execute_script/1`, `direct_data/2`, `direct_html/2`
- **Blenny.Hub** — lifecycle coordinator, connection registry, dedup enforcement, limit enforcement
- **Blenny.Connection.Registry** — ETS-backed registry with per-user dedup and connection tracking
- **Blenny.Transport.SSEPlug** — long-lived SSE via Bandit `send_chunked/1` using Datastar wire format
- **Blenny.Transport.LiveViewBridge** — `on_mount` hook for LiveView transport integration

## Configuration

```elixir
# Required
config :blenny_ex, pub_sub: MyApp.PubSub

# Optional — connection limits and shutdown
config :blenny_ex, hub: [
  max_connections: 10_000,
  max_per_user: 100,
  drain_timeout: 30_000
]
```

## Graceful Shutdown

Blenny coordinates a **two-phase drain** when the OTP application shuts down,
preventing the thundering herd problem where thousands of clients reconnect
simultaneously after a hard drop.

### How it works

1. **Hub stops first** — The Hub must appear **after** the Endpoint in your
   supervision tree (see Step 2). OTP stops children in reverse start order,
   so the Hub drains before the web server terminates.

2. **`:draining` state** — The Hub transitions to `:draining`, rejecting new
   registrations with `{:error, :draining}`.

3. **Signal transports** — The Hub sends `{:blenny_drain, deadline}` to every
   active transport PID:
   - **SSE connections** receive a Datastar `execute_script` frame that
     staggers reconnection: `setTimeout(() => location.reload(), random(1-6s))`
   - **LiveView connections** receive the same signal — the LiveView process
     stops, and Phoenix's built-in WebSocket exponential backoff handles
     staggered reconnection automatically.

4. **Wait for DOWN** — The Hub blocks in its `terminate/2` callback, waiting
   for all transport processes to exit. Once all connections are cleaned up
   (or `drain_timeout` expires), the Hub exits and the supervisor proceeds
   with normal shutdown.

### Configuring drain timeout

```elixir
config :blenny_ex, hub: [
  drain_timeout: 30_000  # milliseconds (default)
]
```

The Hub's `shutdown` in the supervision tree should be set to at least
`drain_timeout + 5_000` to give `terminate/2` room to complete.

### Explicit drain

You can also drain programmatically:

```elixir
Blenny.Hub.drain()
# => :drained (or :already_draining)
```

This is useful for blue-green deployments or custom shutdown sequences.

## Telemetry

Blenny emits three `:telemetry` events from the Hub on connection lifecycle
changes. Add metrics to your app's `MyApp.Telemetry.metrics/0` to see live
graphs in Phoenix LiveDashboard:

```elixir
def metrics do
  [
    # Active connections (streaming gauge)
    last_value("blenny.hub.connection.register.count",
      description: "Active Blenny connections"
    ),

    # Rejected connections — tag by :limit_type to distinguish
    # :max_connections (system-wide) from :max_per_user (per-client)
    counter("blenny.hub.connection.rejected.count",
      tags: [:limit_type],
      description: "Rejected Blenny connections"
    )
  ]
end
```

Then add the `:blenny.hub` prefix to LiveDashboard in your router:

```elixir
live_dashboard "/dashboard",
  metrics: MyApp.Telemetry,
  additional_page: [
    blenny: %{metrics: ~r/^blenny\.hub/}
  ]
```

### Event reference

| Event prefix | Measurements | Metadata | Fires when |
|---|---|---|---|
| `[:blenny, :hub, :connection, :register]` | `count` | `user_id`, `conn_type` | Connection registered successfully |
| `[:blenny, :hub, :connection, :unregister]` | `count` | `user_id`, `conn_type`, `reason` (`:explicit` \| `:process_down`) | Connection removed |
| `[:blenny, :hub, :connection, :rejected]` | `count` | `user_id`, `conn_type`, `limit_type` (`:max_connections` \| `:max_per_user`) | Connection rejected by a limit |

## License

MIT
