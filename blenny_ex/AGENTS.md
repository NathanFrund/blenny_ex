# blenny_ex — Agent Briefing

An Elixir/Phoenix port of the Blenny framework (Pharo Smalltalk → Rust →
Clojure → TypeScript → Elixir). Multi-transport hypermedia engine for SSE
(Datastar) and LiveView.

---

## Key Idioms & Patterns

### Modules

- Modules implement `Blenny.Module` behaviour via `use Blenny.Module`.
- Auto-registered at compile time via `@before_compile` hook (replaces
  earlier `@after_compile` — `@before_compile` stores both the module name
  and its routes to the application env before the macro phase completes).
- Routes must be declared via `@blenny_routes` module attribute (with
  `accumulate: true`) in addition to the `routes/0` callback. The attribute
  enables compile-time route discovery for `blenny_modules/2`:

      # HTTP routes: {:http, method, path, plug, action}
      @blenny_routes {:http, :get, "/signin", __MODULE__, :render_sign_in}
      @blenny_routes {:http, :post, "/signin", __MODULE__, :handle_sign_in}

      # Auth-protected HTTP: {:http, method, path, plug, action, [auth: true]}
      @blenny_routes {:http, :post, "/avatar", __MODULE__, :handle_avatar, [auth: true]}

      # LiveView routes (no action, with action, with auth):
      @blenny_routes {:live, "/dashboard", MyAppWeb.DashboardLive}
      @blenny_routes {:live, "/dashboard", MyAppWeb.DashboardLive, :index}
      @blenny_routes {:live, "/admin", AdminLive, [auth: true]}

      @impl true
      def routes, do: @blenny_routes
- Lifecycle hooks: `initialize/1` (receives app state map), `child_spec/1`
  (returns `:skip` or OTP child spec).
- Declare `capabilities/0` like `["auth"]` for boot-time conflict detection.
- Routes tagged `auth: true` are automatically wrapped with `RequireUser`.
- Optional `auth/0` callback returns provider metadata (login route, etc.).

```elixir
defmodule MyApp.Blenny.Dashboard do
  use Blenny.Module

  @blenny_routes {:http, :get, "/dashboard", __MODULE__, :show}

  @impl true
  def name, do: "dashboard"

  @impl true
  def routes, do: @blenny_routes

  @impl true
  def capabilities, do: []
end
```

### App State

- Simple map passed into `initialize/1` during boot.
- Currently contains only `:pub_sub` (the configured `Phoenix.PubSub` adapter).

### Publisher API

- `Blenny.Publisher` is a stateless module — no GenServer, no state.
- Five functions: `broadcast_html/1`, `broadcast_data/1`, `execute_script/1`,
  `direct_html/2`, `direct_data/2`.
- All delegate to `Phoenix.PubSub.broadcast/3` under the hood.
- Prefer `Blenny.Publisher.*` from timers, event callbacks, and CLI tools.
- For intent-level control, publish directly with `:blenny_msg` tuples.

### Transport Architecture (PubSub-Direct)

Publisher writes to PubSub topics. Transport processes subscribe and receive
directly in their mailbox:

```
Blenny.Publisher.broadcast_html(...)
  → Phoenix.PubSub.broadcast("blenny:intent:ui", {:blenny_msg, :ui, payload})
    → SSEPlug process receives in mailbox, writes Datastar SSE frames
    → LiveViewBridge process receives in mailbox via handle_info
```

Hub is lifecycle-only: ETS registry, dedup `{user_id, conn_type}`, DOWN cleanup.
It never touches the wire format.

Intent types: `:ui` (HTML + signals), `:command` (scripts), `:notification`
(alerts). `:all` is a meta-intent. Per-user topic: `blenny:user:<id>`.

### Auth System

Auth is a module with `capabilities: ["auth"]`. Design:

1. Module `init/1` creates its stores and registers with `Blenny.AuthRegistry`
2. `Blenny.Router.blenny_modules/2` wraps `auth: true` routes with `RequireUser`
3. `FetchSession` runs in browser pipeline, delegates to registered provider
4. `RequireUser` / `RequireRole` halt unauthenticated/unauthorized

Framework provides: `AuthRegistry`, `FetchSession`, `RequireUser`,
`RequireRole`, `Router.blenny_modules/2`. Module provides: storage, UI,
crypto, `fetch_session/1` function.

### Storage Layer

`Blenny.Storage.User` behaviour (mirrors TS `UserStore`):

| Implementation | Backend | Durable | Best for |
|---|---|---|---|
| `Blenny.Storage.Impl.InMemory` | ETS | — | Dev/test (default) |
| `Blenny.Storage.Impl.DETS` | DETS | ✅ | Single-node production |
| `Blenny.Storage.Impl.FSBlob` | Filesystem | ✅ | Avatars, media blobs |

DETS uses file-path charlists (not atoms) for `:dets.open_file/2` to avoid
global name collisions. Two files per store: `users.dets` (primary) +
`usernames.dets` (secondary index). Writes flushed with `:dets.sync/1`.

`Blenny.Storage.UUID.generate/0` produces RFC 4122 compliant v4 UUIDs using
`:crypto.strong_rand_bytes` — zero external deps.

### Config

- `Blenny.Config` reads from `Application.get_env(:blenny_ex, ...)`.
- `Blenny.Module.Loader` checks `Application.get_env(:blenny_ex, :modules)`
  for explicit module registration (overrides auto-discovery).
- `nimble_options` validates `:blenny_ex` config at boot via `Blenny.Config.validate!/0`. The schema covers `:pub_sub` (required), `:hub`, and `:transport`. Internal keys (`:module_routes`, `:registered_modules`) are excluded from validation.

---

## Important Decisions & Rationale

| Decision | Rationale |
|---|---|
| **PubSub-direct routing** | Hub is lifecycle-only (ETS + process monitor). Transports subscribe to PubSub directly. No single-process bottleneck, cluster-safe by Phoenix PubSub. |
| **Auth via modules** | Module owns storage, UI, crypto. Framework provides registry + plugs. Swapping the module swaps the entire auth UX. Reverses earlier "keep in host app" decision. |
| **DETS over SQLite/CubDB** | Zero external deps. Built into OTP since the 1990s. Single-file, ACID, crash-safe. 2GB/32M row limits sufficient for any single-node deployment. |
| **DETS with file-path (not atom)** | `:dets.open_file/2` with a string returns a process-local reference. Avoids global atom namespace collision, enabling multiple instances under one supervisor. |
| **WebSocket declined** | Phoenix LiveView already provides an optimized, clustered WebSocket channel. Adding a raw WS sidecar duplicates overhead for zero functional gain. Non-Phoenix clients use `Phoenix.Channel` directly. |
| **Connection recovery declined** | Datastar manages client-side reconnection. Frontend sends state via signals on reconnect. No server-side state buffer needed. |
| **Database/ORM: zero opinions** | No `Blenny.ORM` abstraction. Community uses Ecto. Blenny stays focused on transport and routing. |
| **DateTime: no tzdata** | `:calendar.local_time()` + `:erlang.time_offset()` for local time. `DateTime.add/3` on OTP 29 takes 197ms — use `:calendar.gregorian_seconds_to_datetime/1` (11μs). |
| **ETS `async: false` tests** | Named ETS tables are process-global. Parallel test suites share them. Use `async: false` for ETS-backed stores or guard with `:ets.info` before delete. |
| **Publisher is stateless** | No GenServer, no state. Thin wrapper over `Phoenix.PubSub.broadcast`. Zero-ceremony from any code. |
| **Connection limits enforced at Hub** | `max_connections` (system-wide) and `max_per_user` (per dedup-key) checked in `register_connection` before any existing dedup logic. Returns `{:error, reason}` on limit hit — callers propagate 429 (SSEPlug) or halt mount (LiveViewBridge). |
| **max_per_user counts by dedup key** | Uses the same dedup-key logic as connection dedup: `user_id` for authenticated users, `conn.id` for anonymous. This protects anonymous routes (sign-in, registration) from bot exhaustion. |

---

## Architectural Guardrails & Invariants

**DO NOT REFACTOR AWAY.** These patterns must be preserved across all changes.

### Module Lifecycles & Self-Assembly

- **Bootstrap is a temporary GenServer:** `Blenny.Bootstrap` runs in the
  supervision tree as a `:temporary` child. Config validation and module
  `initialize/1` callbacks run synchronously in `init/1`. Background
  processes start asynchronously via `:start_supervised`. Bootstrap stops
  itself after boot completes. `Blenny.AuthRegistry` must be in the
  supervision tree before Bootstrap (it owns the ETS table for auth plugs).
  Legacy `Blenny.Bootstrap.boot/0` is preserved for backward compatibility.
- **Lifecycle Hooks:** Every module must respect `initialize/1` and `child_spec/1`.
- **Blenny.Module usage:** Use `use Blenny.Module` — never manually implement
  the behaviour without `__using__`.

### Transport & Real-Time Defaults

- **SSE Always Active:** SSE is the primary transport. LiveView is a sidecar,
  never a replacement.
- **Blenny.Publisher Exposed:** `broadcast_html`, `direct_html`,
  `broadcast_data`, `direct_data`, `execute_script` must be available from
  any code. Do not encapsulate behind module instances.
- **Intent Routing:** Messages must retain intent-based filtering (`:ui`,
  `:command`, `:notification`). Do not remove or collapse the intent system.
- **Datastar SDK Only:** The `dstar` Hex package is the sole SSE wire format.
  No custom encoder logic.
- **LiveView Delivers Pass-Through:** LiveView receives the same
  `{:blenny_msg, intent, payload}` tuples. No transport-specific message
  wrapping in the framework layer.
- **WS Sends Not Implemented:** WebSocket is consciously declined. Do not add
  a raw WebSocket sidecar.

### Auth & Security

- **Auth by Convention:** Auth is always a module claiming `capabilities: ["auth"]`.
  Framework must not hardcode auth logic.
- **AuthRegistry is a persistent GenServer:** Runs in the supervision tree
  before `Blenny.Bootstrap`. Owns the ETS table to keep it alive across the
  application lifetime. `AuthRegistry.register/1` raises on duplicate.
- **AuthRegistry is Singleton:** Exactly one module can claim `capabilities: ["auth"]`.
- **Role Checks via Plugs:** `RequireUser` and `RequireRole` are the only
  auth enforcement points. Do not add role-checking to the router macro.
- **fetch_session is a Function Reference:** The registered provider stores a
  function reference, not a module callback. This allows both stateless
  (JWT verify) and stateful (session store lookup) implementations.

### Storage

- **Zero External Deps:** ETS, DETS, and filesystem only. No SQLite, CubDB,
  or other external storage engines in the framework.
- **DETS File Path, Not Atom:** Always use charlist file paths for
  `:dets.open_file/2`. Never hardcode atom table names — they're globally
  registered across the VM node.
- **Two DETS Files:** Primary store + username index. Always sync both after
  writes.
- **Process-Free API:** The InMemory store uses direct `:ets` calls (not
  GenServer wrapping). The DETS and FSBlob stores use GenServer for lifecycle
  management (start/stop/close), not for access serialization.

### Testing

- **ETS-backed tests use `async: false`:** Named ETS tables are process-global.
  Parallel tests sharing the same table will interfere.
- **DETS tests use temp dirs:** `System.tmp_dir!()` + unique integer suffix.
  Clean up `File.rm_rf!` in `on_exit`.
- **Auth tests register `AuthTestModule`:** The test support module registers
  with `AuthRegistry` and provides a deterministic `fetch_session`.
- **Integration tests use Bandit on port 0:** Port read via
  `ThousandIsland.listener_info/1`.

---

## Code Style & Idioms

- **Formatting:** `mix format` (Elixir 1.19 defaults, no custom config).
- **Compile:** `mix compile --warnings-as-errors`.
- **Testing:** `mix test`.
- **Precommit:** `mix precommit` — compiles both projects, formats, and runs
  all tests (blenny_ex + blenny_example_app).
- **Comments:** No comments in code. `@moduledoc` and `@doc` for API docs.
- **Callbacks:** `@impl true` on every callback implementation.
- **Types:** `@type` and `@spec` on all public functions. Use `@typedoc` for
  complex types.
- **ETS naming:** Named tables prefixed `:blenny_` (e.g. `:blenny_storage_in_memory`).
- **ETS safety:** Guard `:ets.info(table)` before `:ets.delete` — tables may
  already be destroyed.
- **No any:** No dynamic typing abuse. Use union types (`| nil`, `| error`)
  for fallible functions.

---

## Current State (June 2026)

- Framework fully implemented: modules, PubSub-direct routing, SSE, LiveView,
  publisher, config, auth plugs, router macro, storage layer.
- 168 tests — all passing, zero warnings.
- `mix format` clean. `mix compile --warnings-as-errors` clean.
- Known gaps vs blenny-ts (see Gaps section below).

Testing summary:

| Area | Tests | Status |
|---|---|---|
| Auth (struct, registry, plugs, router) | 30 | ✅ |
| Connection (struct, registry) | 18 | ✅ |
| Intent | 12 | ✅ |
| Config | 5 | ✅ |
| Error | 2 | ✅ |
| Hub | 9 | ✅ |
| Publisher | 9 | ✅ |
| Module (behaviour, loader, lifecycle) | 11 | ✅ |
| Bootstrap | 3 | ✅ |
| SSEPlug (unit + integration) | 27 | ✅ |
| LiveView integration | 4 | ✅ |
| Storage (UUID, InMemory, DETS, FSBlob) | 37 | ✅ |
| FormAuth (test app — sign-in, register, sign-out, crypto) | 13 | ✅ |
| SSE dashboard integration | 4 | 🟡 Medium |

---

## How to Navigate the Codebase

```
blenny_ex/
  lib/blenny/
    auth.ex                        — %Blenny.Auth{} struct
    auth/registry.ex               — ETS singleton provider registry
    auth/plug.ex                   — FetchSession, RequireUser, RequireRole
    bootstrap.ex                   — Boot orchestrator
    config.ex                      — App env config reader
    connection/connection.ex       — Connection struct
    connection/registry.ex         — ETS connection registry
    error.ex                       — Structured exception
    hub/hub.ex                     — Hub GenServer (lifecycle only)
    hub/publisher.ex               — Blenny.Publisher (zero-ceremony broadcasts)
    intent.ex                      — Intent types, parsing, topic mapping
    module.ex                      — Module behaviour
    module/loader.ex               — Compile-time module discovery
    module/lifecycle.ex            — Init + supervise lifecycle
    router.ex                      — blenny_modules/2 macro
    storage.ex                     — Storage namespace doc
    storage/uuid.ex                — RFC 4122 v4 UUID (zero deps)
    storage/user.ex                — UserStore behaviour
    storage/blob.ex                — BlobStore behaviour
    storage/impl/in_memory.ex      — ETS-backed user store
    storage/impl/dets.ex           — DETS-backed user store
    storage/impl/fs_blob.ex        — Filesystem blob store
    transport/sse_plug.ex          — SSE endpoint (Datastar wire format)
    transport/liveview_bridge.ex   — LiveView on_mount hook
  test/
    support/
      test_modules.ex              — AuthTestModule, RouterTestModule, etc.
      sse_test_endpoint.ex         — Minimal Plug.Builder for Bandit tests
      sse_test_helpers.ex          — TCP/HTTP helpers for Bandit
    blenny/                        — One test file per source module

blenny_example_app/

  lib/blenny_example_app/             — Host app consuming blenny_ex

  lib/blenny_example_app_web/
    dashboard_live.ex              — LiveView dashboard with event log
  test/                            — Integration tests (LiveView, SSE)
```

---

## Common Pitfalls

- **DETS atom vs file path:** Never pass a hardcoded atom like
  `:my_table_name` to `:dets.open_file/2`. The atom becomes a globally
  registered table identifier. Pass a file path string (charlist) to get a
  process-local reference instead. This allows multiple store instances
  under the same supervisor.
- **Registry.clear/0:** Check `:ets.info(table) != :undefined` before calling
  `:ets.delete_all_objects/1` — the table may not exist yet if boot hasn't
  run.
- **child_spec/1 args format:** Must pass args as list:
  `{Mod, :start_link, [[]]}` not `{Mod, :start_link, []}`.
- **DateTime.add/3 on OTP 29:** Takes ~197ms per call — prohibitive. Use
  `:calendar.gregorian_seconds_to_datetime/1` (11μs) for Unix timestamp
  conversion.
- **LiveView on_mount context:** `Phoenix.PubSub.subscribe` from `on_mount`
  subscribes the LiveView process. Messages arrive as `handle_info` calls.
- **Blenny.Hub.register_connection/1:** Returns `{:ok, conn}` on success, `{:error, :too_many_connections}` or `{:error, :too_many_per_user}` on limit reached. Configure limits via `config :blenny_ex, hub: [max_connections: 10_000, max_per_user: 100]` or pass opts directly to `Blenny.Hub.start_link/1` (opts override config).
- **Named ETS tables in tests:** Use `async: false` when tests share named
  ETS tables, or guard deletes with `:ets.info`.
- **Connection.Registry.start_link/0 is idempotent:** Safe to call from
  multiple Hub instances — returns the existing table tid if the ETS tables
  already exist. Enables testing Hub limit configurations by starting
  additional Hub instances with different opts.
- **DETS crash safety:** Call `:dets.sync/1` after every write operation.
  DETS buffers writes in memory by default — sync flushes to disk.
- **`blenny_modules/2` test modules:** The handler module is used as a Phoenix
  controller. It must export `init/1` (from Plug). Add `def init(_opts),
  do: {:ok, nil}` to test modules that don't `use Phoenix.Controller`.
- **Compile-time route discovery:** `mod.routes()` cannot be called at compile
  time because modules aren't loaded into the VM until after compilation.
  Always declare routes via `@blenny_routes` attribute (with `accumulate: true`).
  The `routes/0` callback should return `@blenny_routes`.
- **`@before_compile` vs `@after_compile`:** Use `@before_compile` for module
  registration (writing to application env). `@after_compile` fires too late
  for macros that need to read the data in the same compilation pass.
- **`blenny_modules/2` needs explicit `:modules` at compile time:** Module
  auto-discovery via `Loader.modules()` is unreliable during compilation
  because Mix may compile independent files in any order. Always pass
  `modules: [Your.Modules]` to `blenny_modules/2` in the router, or set
  `config :blenny_ex, modules:` in config for compile-time discovery.
- **Plug init for test modules:** Modules used as route plugs must export
  `def init(_opts), do: {:ok, nil}` to satisfy the Plug behaviour. Add this
  to test modules that don't use `Phoenix.Controller`.

---

## Gaps vs blenny-ts

| Feature | blenny-ts | blenny_ex | Status |
|---|---|---|---|
| SSE transport | Datastar SDK | `dstar` Hex package | ✅ |
| WebSocket transport | Raw WS sidecar | 🚫 Declined (LiveView suffices) | Conscious decision |
| Auth module | `form-auth.tsx` | `BlennyTestApp.Blenny.FormAuth` | ✅ |
| Publisher API | 5 functions | 5 functions | ✅ |
| Config validation | Valibot | `nimble_options` validates at boot | ✅ |
| Telemetry | ? | No events | ❌ |
| Rate limiting | ✅ | Not implemented | ❌ |
| Graceful shutdown | ✅ | `drain/1` + `terminate/2` + transport `:blenny_drain` signaling | ✅ |
| CI pipeline | `deno task ci` | Not implemented | ❌ |
| Generators | ❌ | `mix blenny.gen.module` | ❌ |
| Hex publish | N/A (npm) | Not published | ❌ |
| Durable KV | Deno KV | DETS | ✅ |
| Blob store | `FsBlobStore` | `Blenny.Storage.Impl.FSBlob` | ✅ |
| Role-based access | `requireRole` | `RequireRole` plug | ✅ |
| Connection recovery | Cookie + restore | 🚫 Declined (Datastar handles it) | Conscious decision |
| Logger middleware | LogTape + requestLogger | Not implemented | ❌ |
| Boot-time conflict detection | Capability check | ✅ | ✅ |

---

_See `ROADMAP.md` for milestone tracking and release checklists._
