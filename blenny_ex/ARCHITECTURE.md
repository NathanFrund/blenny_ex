# blenny_ex — Architecture

## Project Identity

An Elixir/Phoenix library for building multi-transport hypermedia applications.
Blenny lets you write unified HTML components that can be delivered over
Server-Sent Events (Datastar) **or** Phoenix LiveView WebSockets, routing
transport based on the client's runtime environment. Library is published to Hex
as an independent dependency; the test app ships in the same monorepo.

## Core Design Principles

1. **Self-assembling modules** — modules implement `Blenny.Module`, declare
   routes and lifecycle hooks, auto-register at compile time via
   `@after_compile`
2. **Real-time by default** — SSE and LiveView are first-class transport
   primitives, not afterthoughts
3. **Datastar wire format** — server-side SSE uses `dstar` Hex package for
   `patch_elements`, `patch_signals`, `execute_script`
4. **Connection intents** — per-connection intent filtering (`:ui`,
   `:command`, `:notification`, `:all`) prevents redundant deliveries when a
   user has multiple connections open
5. **Hex-publishable library** — `blenny_ex` is a standalone Hex package;
   host apps add it as a dependency
6. **Publisher-first API** — modules call `Blenny.Publisher` to reach
   clients; they never write to transport sockets directly
7. **Auth via modules** — Auth is delivered by modules declaring
   `capabilities: [:auth]`. The module owns storage, UI, and crypto;
   Blenny provides the registry, pipeline plugs, and router macro.
8. **No framework lock-in** — bring your own database and session
   management; Blenny handles transport routing, lifecycle, and
   auth plumbing

## What's Built

| Component                                                   | Status |
| ----------------------------------------------------------- | ------ |
| `Blenny.Module` behaviour + compile-time discovery          | ✅     |
| `Blenny.Hub` GenServer (lifecycle coordination)             | ✅     |
| `Blenny.Connection.Registry` (ETS-backed dedup)             | ✅     |
| `Blenny.Publisher` (zero-ceremony broadcasting API)          | ✅     |
| `Blenny.Intent` (intent types + topic mapping)              | ✅     |
| `/sse` endpoint via `Blenny.Transport.SSEPlug` (Datastar)   | ✅     |
| `LiveViewBridge` on_mount hook (LiveView transport)          | ✅     |
| `dstar` wire format (replaces ~35 lines of manual chunk())  | ✅     |
| Connection dedup (`{user_id, conn_type}`)                   | ✅     |
| Per-user messaging (`blenny:user:<id>` topic)               | ✅     |
| Monorepo structure (lib + test app)                         | ✅     |

## Architectural Decisions

### PubSub-Direct Routing

No central TransportHub bottleneck. Publishers publish to `Phoenix.PubSub`
topics; transport processes (SSE, LiveView) subscribe directly to those
topics in their own receive loop:

```
Blenny.Publisher.broadcast_html("<div>hi</div>")
        │
        ▼
Phoenix.PubSub.broadcast("blenny:intent:ui",
  {:blenny_msg, :ui, %{html: "<div>hi</div>"}})
        │
        ┌────────────────┴────────────────┐
        ▼                                  ▼
  SSE process                         LiveView process
  (subscribed in call/2)              (subscribed in on_mount)
  filters by conn.intents             filters by conn.intents
        │
        ▼
  Dstar.patch_elements(conn, html, selector: "#my-id")
```

The Hub is **lifecycle only** — it registers connections, monitors transport
PIDs, enforces `{user_id, conn_type}` dedup, and cleans up on DOWN. It
never touches message payloads.

### Connection Model (UUID-per-connection)

Each connection gets a unique 32-char hex UUID (`:crypto.strong_rand_bytes/1`).
The ETS registry tracks:

| ETS Table                    | Type       | Purpose                              |
| ---------------------------- | ---------- | ------------------------------------ |
| `:blenny_connections`        | ordered_set| Primary table, keyed by conn ID      |
| `:blenny_connections_by_dedup` | set      | `{user_id, conn_type}` → conn ID     |
| `:blenny_connections_by_user`  | bag       | `user_id` → conn ID (per-user list)  |

Dedup guarantees at most one SSE + one LiveView per authenticated user.
Anonymous connections fall back to `conn.id` as the dedup key (each gets its
own slot).

### Intent Model

Two independent concerns:

| Concern            | What it does                       | Stable interface                                |
| ------------------ | ---------------------------------- | ----------------------------------------------- |
| **Intents**        | Which connections should receive   | `:ui`, `:command`, `:notification`, `:all`      |
| **Payload action** | What the module wants the client   | `:html` → patch elements, `:signals` → patch    |
|                    | to do                              | signals, `:script` → execute                    |

Routing topics:

- `blenny:intent:ui` — HTML fragments + signal data
- `blenny:intent:command` — bidirectional request/response traffic
- `blenny:intent:notification` — system alerts, toasts
- `blenny:user:<user_id>` — per-user (all intents, subscriber filters)

Clients declare intents via query param: `/sse?intent=ui,command`. `:all` (or
empty/absent) subscribes to everything.

### Module System

Modules implement `Blenny.Module`:

- `name/0` — unique module name for conflict detection
- `routes/0` — HTTP routes the module contributes
- `capabilities/0` — capability strings (boot-time conflict checks)
- `subscriptions/0` — PubSub topic subscriptions
- `initialize/1` — optional boot-time setup (e.g., logging)
- `child_spec/1` — optional child spec for supervised background process

**Two kinds of modules:**

| Type | child_spec/1 | Process | Use case |
|------|-------------|---------|----------|
| Declarative | returns `:skip` (default) | none | Static routes, templates |
| Stateful | returns a `Supervisor.child_spec()` | supervised under `Blenny.ModuleSupervisor` | Metrics loops, timers, state machines |

Stateful modules register themselves in their `init/1` using
`{:via, Registry, {Blenny.ModuleRegistry, {scope, __MODULE__}}}` where
`scope` is `:global` (singleton) or a per-session key (multi-tenant).

Discovery is compile-time: `use Blenny.Module` installs an `@after_compile`
hook that appends the module to `Application.get_env(:blenny_ex,
:registered_modules)`.

### Boot Sequence

1. Discover and validate modules
2. Call `initialize/1` on each module (stateless setup)
3. For each module, call `child_spec/1`:
   - `:skip` → module is declarative-only, skip
   - child_spec → `DynamicSupervisor.start_child(Blenny.ModuleSupervisor, spec)`

The host application must include `Blenny.ModuleRegistry` (a built-in Elixir
`Registry`) and `Blenny.ModuleSupervisor` (a `DynamicSupervisor`) in its
supervision tree.

### Transport Lifecycle

**SSE** (`Blenny.Transport.SSEPlug`):
1. `call/2` — parse intents, set SSE headers, create connection struct,
   register with Hub
2. Subscribe to all routing PubSub topics + user topic
3. Enter `sse_loop/3` — `receive` loop matching `{:blenny_msg, intent, payload}`
4. Write Datastar events via `Dstar.*` with `try/rescue` for closed connections
5. On `{:blenny_replaced, ...}` or `{:EXIT, ...}`, unregister and close

**LiveView** (`Blenny.Transport.LiveViewBridge`):
1. `on_mount` — read `intents` from opts, create connection struct,
   register with Hub, subscribe to PubSub topics
2. LiveView receives `{:blenny_msg, intent, payload}` directly in its
   process mailbox (Phoenix PubSub delivers to subscribing process)
3. Unmount is implicit — process crash triggers Hub's `{:DOWN, ...}` cleanup

### Publisher API

Modules never talk to transport sockets. The `Blenny.Publisher` module
provides five public functions that all route through Phoenix PubSub:

```elixir
Blenny.Publisher.broadcast_html(html)    # → blenny:intent:ui
Blenny.Publisher.broadcast_data(data)    # → blenny:intent:ui (signals)
Blenny.Publisher.execute_script(script)  # → blenny:intent:command
Blenny.Publisher.direct_html(html, uid)  # → blenny:user:<uid>
Blenny.Publisher.direct_data(data, uid)  # → blenny:user:<uid>
```

### Configuration

Required in the host application:

```elixir
config :blenny_ex, pub_sub: MyApp.PubSub
```

Accessed at runtime via `Blenny.pub_sub/0`, used by Publisher, SSE plug,
LiveView bridge, and Hub.

### Storage Durability

Auth modules default to in-memory storage (`:memory`), which is ephemeral. To
persist user accounts across restarts, configure the auth module to use DETS:

```elixir
# config/config.exs or config/runtime.exs
config :blenny_ex, :form_auth_store, :dets
```

The `FormAuth` module's `initialize/1` reads this config and starts the
`Blenny.Storage.Impl.DETS` backend instead of `Blenny.Storage.Impl.InMemory`.
Data is written to `./data/form_auth/` (DETS: `users.dets` + `usernames.dets`)
and flushed with `:dets.sync/1` after every write. Existing accounts survive
server restarts; the admin account is only seeded when the store is empty.

## Dependency Stack

| Dependency               | Purpose                                    |
| ------------------------ | ------------------------------------------ |
| `phoenix` ~> 1.7        | HTTP server, routing, PubSub               |
| `phoenix_live_view` ~> 1.0 | LiveView WebSocket transport            |
| `bandit` ~> 1.5         | HTTP server (optional)                     |
| `jason` ~> 1.2          | JSON encoding/decoding                     |
| `dstar` ~> 0.0.10       | Datastar SSE wire format (server-side)     |
| `telemetry` ~> 1.0      | Instrumentation                            |
| `nimble_options` ~> 1.0 | Configuration validation                   |

## Monorepo Structure

```
blenny_elixir/
├── blenny_ex/                  ← Hex-publishable library
│   ├── lib/blenny/
│   │   ├── connection/         ← Connection struct + ETS registry
│   │   ├── hub/                ← Hub lifecycle GenServer + Publisher
│   │   ├── transport/          ← SSE plug + LiveView bridge
│   │   ├── intent.ex           ← Intent types + topic mapping
│   │   └── module.ex           ← Module behaviour + discovery
│   ├── mix.exs                 ← Hex metadata + dependencies
│   └── ARCHITECTURE.md         ← This file
│
└── blenny_example_app/            ← Phoenix example application

    ├── lib/blenny_example_app/

    │   └── blenny_example_app_web/← Web controllers, templates, LiveViews
    ├── mix.exs                 ← Depends on blenny_ex via path:
    │                               {:blenny_ex, path: "../blenny_ex"}
    └── test/                   ← Integration tests
```

---

_Based on patterns from blenny-ts (TypeScript/Deno), blenny-rs (Rust),
blenny-clj (Clojure), and the original blenny (Pharo Smalltalk)._
