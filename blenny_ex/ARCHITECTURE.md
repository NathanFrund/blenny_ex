# blenny_ex — Architecture & Implementation Roadmap

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
- `initialize/1` — optional boot-time setup
- `start/0` — optional start hook (e.g., spawn metrics loop)
- `stop/0` — optional shutdown hook

Discovery is compile-time: `use Blenny.Module` installs an `@after_compile`
hook that appends the module to `Application.get_env(:blenny_ex,
:registered_modules)`.

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

## Implementation Roadmap

### Phase 1: Connection Core (✅)

- `Blenny.Connection` struct
- `Blenny.Connection.Registry` (ETS tables)
- `Blenny.Hub` GenServer (lifecycle, monitoring, dedup)

### Phase 2: Intents (✅)

- `Blenny.Intent` — types, topic mapping, parsing
- Connection-level intent filtering
- SSE and LiveView subscribe to PubSub topics directly

### Phase 3: Publisher + Transports (✅)

- `Blenny.Publisher` — zero-ceremony broadcast/direct API
- `Blenny.Transport.SSEPlug` — long-lived SSE with Datastar wire format
- `Blenny.Transport.LiveViewBridge` — LiveView on_mount hook

### Phase 4: Module System (✅)

- `Blenny.Module` behaviour + compile-time discovery
- Lifecycle hooks (initialize, start, stop)
- Per-module route registration

### Phase 5: Production Hardening (🔜)

- Graceful shutdown (SIGINT/SIGTERM → module stop hooks)
- Connection draining on deploy
- Telemetry/metrics instrumentation
- Rate limiting per connection
- Reconnection backoff strategy for SSE clients

### Phase 6: Advanced Features (🔮)

- WebSocket transport (optional sidecar)
- Auth module strategy pattern (pluggable middleware)
- Session-level state serialization across reconnects
- `blenny_ex` published to Hex.pm
- `mix blenny.gen.module` generator
- CLI scaffold for new applications

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
└── blenny_test_app/            ← Phoenix test application
    ├── lib/blenny_test_app/
    │   ├── blenny/             ← Test modules (DashboardModule, etc.)
    │   └── blenny_test_app_web/← Web controllers, templates, LiveViews
    ├── mix.exs                 ← Depends on blenny_ex via path:
    │                               {:blenny_ex, path: "../blenny_ex"}
    └── test/                   ← Integration tests
```

## Open Questions

1. **WebSocket transport** — should this exist as an optional sidecar (like
   Rust/Clojure versions) or fold into the existing LiveView transport? SSE
   alone covers most real-time use cases, and LiveView already provides
   WebSocket for Phoenix-native clients.
2. **Auth integration** — should `Blenny.Module` gain an optional
   `auth/0` callback that returns middleware config, or keep auth entirely
   in the host application?
3. **Connection recovery** — SSE clients that drop and reconnect get a new
   UUID. Should we track a "session token" cookie to restore the previous
   connection's state (subscriptions, filters)?
4. **Database** — leave it to the host app (zero framework opinions) or
   provide an optional `Blenny.ORM` behaviour for modules that need
   persistence?

---

_Based on patterns from blenny-ts (TypeScript/Deno), blenny-rs (Rust),
blenny-clj (Clojure), and the original blenny (Pharo Smalltalk)._
