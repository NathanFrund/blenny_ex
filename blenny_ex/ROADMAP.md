# blenny_ex Roadmap

Multi-transport hypermedia engine for Phoenix — SSE (Datastar) and LiveView.

## Project Identity

An Elixir/Phoenix library for building multi-transport hypermedia applications.
Blenny lets you write unified HTML components that can be delivered over
Server-Sent Events (Datastar) **or** Phoenix LiveView WebSockets, routing
transport based on the client's runtime environment. The library is published
to Hex as an independent dependency; the test app ships in the same monorepo.

### Design Principles

1. **Self-assembling modules** — modules implement `Blenny.Module`, declare
   routes, capabilities, subscriptions, lifecycle hooks, and auto-register at
   compile time
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
   `capabilities: [:auth]`. The module owns its storage strategy, UI,
   and cryptography. It registers verification plugs with
   `Blenny.AuthRegistry` during initialization. Blenny provides the
   `Blenny.Router` macro for auto-mounting, and pipeline plugs
   (`FetchSession`, `RequireUser`, `RequireRole`) that delegate to
   the registered provider. Swapping the module swaps the entire auth UX.
8. **No framework lock-in** — bring your own database and session
   management; Blenny handles transport routing, lifecycle, and
   auth plumbing

## Definition of Done

`blenny_ex` is **done** when each of these is true:

1. A developer can `{:blenny_ex, "~> 1.0"}` and have SSE + LiveView delivery
   working with a few lines of config
2. All `Blenny.Module` callbacks are wired into the framework (routes
   auto-mounted via `Blenny.Router` macro, subscriptions auto-wired)
3. All production-hardening features are implemented (telemetry, rate
   limiting, connection draining, graceful shutdown, config validation)
4. WebSocket transport consciously declined with documented rationale (see
   Transport Layer section); SSE + LiveView cover all real-time use cases
5. Auth integration recipes documented for common patterns (Pow,
   AshAuthentication, `pipe_through`)
6. Library is published on Hex with docs on HexDocs
7. At least one external production user exists outside the monorepo
8. API surface is stable (no breaking changes for 1.x)

## The Full Blenny Spec (Elixir)

### A. Module System

The module system is the core abstraction. Every feature — routes, auth,
subscriptions, lifecycle, capabilities — flows through `Blenny.Module`.

| Feature | Status | Notes |
|---------|--------|-------|
| Behaviour with all callbacks (`name/0`, `routes/0`, `capabilities/0`, `subscriptions/0`, `initialize/1`, `child_spec/1`) | ✅ Done | — |
| `auth/0` callback | ✅ Done | Returns provider metadata; registered in `AuthRegistry` at boot |
| `subscriptions/0` optional callback | ✅ Done | `@optional_callbacks`, return type `[String.t()]` |
| Compile-time discovery via `@before_compile` | ✅ Done | — |
| Declarative modules (`:skip` child_spec) | ✅ Done | — |
| Stateful modules (DynamicSupervisor) | ✅ Done | — |
| Capability conflict detection at boot | ✅ Done | — |
| Route auto-registration (`Blenny.Router` macro) | ✅ Done | `import Blenny.Router; blenny_modules("/m")` |
| Subscription auto-wiring (`wire_subscriptions/1`) | ✅ Done | Third bootstrap phase |
| `handle_info({:blenny_subscribe, topics}, state)` injection | ✅ Done | Injected via `__using__` |
| Module-level middleware (before/after hooks) | 🟡 Partial | `RequestLogger` plug exists; no formal before/after hook system |
| Boot sequence orchestrator | ✅ Done | Three-phase: start_supervised → wire_subscriptions → stop |

### B. Transport Layer

| Feature | Status | Notes |
|---------|--------|-------|
| SSE via `Blenny.Transport.SSEPlug` (Datastar wire format) | ✅ Done | 28 unit tests |
| LiveView via `Blenny.Transport.LiveViewBridge` (`on_mount` hook) | ✅ Done | — |
| LiveView `handle_info({:blenny_msg, intent, payload})` | ✅ Done | — |
| Intent filtering per-transport | ✅ Done | — |
| `{:blenny_replaced, pid}` handling | ✅ Done | — |
| WebSocket transport (optional sidecar for non-Phoenix clients) | 🚫 Declined | See rationale below table |
| Connection recovery (session token cookie, restore state on reconnect) | 🚫 Declined | Datastar manages client-side reconnection. Frontend sends state via signals on reconnect. See Resolved Decisions. |
| SSE reconnection backoff strategy | ✅ Done | Staggered reconnect (setTimeout + random 1-6s delay) in drain path |
| Transport-level graceful disconnect (close frame on SIGTERM) | ✅ Done | Hub drain state machine signals transports; SSEPlug sends execute_script + exits; LiveViewBridge does `{:stop, :shutdown, socket}` |

**WebSocket Transport — Declined Rationale:**

Phoenix LiveView already provides an ultra-optimized, clustered WebSocket
channel implementation via `LiveViewBridge`. Adding a parallel raw WebSocket
sidecar within `blenny_ex` duplicates network overhead for zero functional
gain. Non-Phoenix clients (Rust CLI, Go microservice, etc.) that need to
communicate with Blenny can use Phoenix's native `Phoenix.Channel` API over
WebSocket — Blenny does not need its own WebSocket layer. Blenny remains
focused on being the hypermedia delivery layer between modules and clients,
not re-implementing what Phoenix already provides.

### C. Publisher API

| Feature | Status | Notes |
|---------|--------|-------|
| `broadcast_html/1` | ✅ Done | — |
| `broadcast_data/1` | ✅ Done | — |
| `execute_script/1` | ✅ Done | — |
| `direct_html/2` | ✅ Done | — |
| `direct_data/2` | ✅ Done | — |
| Typed event system (beyond raw maps) | ❌ Missing | Define `Blenny.Event` struct with `:type`, `:payload`, `:metadata` for structured pub-sub |
| Publisher telemetry (emit on each publish) | ❌ Missing | Hub and SSEPlug emit telemetry; Publisher does not |

### D. Connection Management

| Feature | Status | Notes |
|---------|--------|-------|
| ETS registry (primary, dedup, user index) | ✅ Done | — |
| `{user_id, conn_type}` dedup (max 1 SSE + 1 LV per user) | ✅ Done | — |
| Per-user connection list | ✅ Done | — |
| Transport process monitoring (DOWN cleanup) | ✅ Done | — |
| `max_connections` enforcement | ✅ Done | Checked in `Hub.register_connection/1` |
| `max_per_user` enforcement | ✅ Done | Checked in `Hub.register_connection/1` |
| `connected_users/0` listing | ❌ Missing | Could be derived from user index, no public API |
| Stale connection sweeper (periodic cleanup of dead but undelivered-DOWN entries) | ✅ Done | Timer-based ETS sweep for entries with no matching process |
| Connection draining on deploy | ✅ Done | Hub drain state machine (`:accepting` → `:draining` → `:stopped`) |
| Rate limiting per connection | ✅ Done | `Blenny.RateLimiter` process-local sliding window; enforced in SSEPlug |
| Connection metadata (connect time, last activity, bytes sent) | ❌ Missing | Extend ETS entry with metadata map |

### E. Auth System

| Feature | Status | Notes |
|---------|--------|-------|
| Module `auth/0` callback | ✅ Done | Module declares `auth/0` returning provider metadata; `Blenny.AuthRegistry` stores it at boot |
| SSE token auth (`?token=...`) | 🚫 Deferred | Document as a recipe — auth module validates tokens in its `fetch_session` plug |
| Role-based access for module routes | ✅ Done | `Blenny.Plug.RequireRole` reads `blenny_auth.role` from `conn.assigns` |
| LiveView auth via Phoenix plug pipeline | ✅ Done | Host app handles in `live_session`; Blenny doesn't interfere |
| Auth integration recipes (Pow, AshAuthentication, etc.) | 📝 Needed | Document common patterns in "Getting Started" guide and HexDocs |
| Anonymous vs authenticated connection distinction | ✅ Done | `user_id` field on Connection struct |

### F. Production Infrastructure

| Feature | Status | Notes |
|---------|--------|-------|
| Telemetry events from Hub (register, unregister, rejected) | ✅ Done | `[:blenny, :hub, :connection, :register]`, `:unregister`, `:rejected` |
| Telemetry events from Publisher (publish per intent) | ❌ Missing | Publisher does not emit telemetry |
| Telemetry events from SSEPlug (connect, disconnect, bytes) | ✅ Done | Bytes telemetry on message dispatch |
| Graceful shutdown (SIGTERM → drain connections → stop modules) | ✅ Done | Hub drain state machine with staggered reconnect; `drain_timeout` configurable |
| Config validation with `nimble_options` | ✅ Done | Schema covers `:pub_sub`, `:hub`, `:transport`; validated in `Blenny.Config.validate!/0` at boot |
| Cluster support (distributed PubSub via PG) | 🟡 Partial | Phoenix PubSub handles this; Blenny just uses configured PubSub |
| Rate limiting | ✅ Done | `Blenny.RateLimiter` (process-local sliding window); enforced in SSEPlug |
| Logger middleware | ✅ Done | `Blenny.Plug.RequestLogger` logs method, path, status, duration |
| Logger metadata (connection_id, user_id on each log line) | 🟡 Partial | `RequestLogger` logs request_id, method, path, status, duration. No connection_id/user_id metadata yet |

### G. Developer Experience

| Feature | Status | Notes |
|---------|--------|-------|
| `README.md` — installation, architecture, quickstart | 🟡 Partial | Needs full "Getting Started" guide |
| `ROADMAP.md` — this file | ✅ Done | — |
| `AGENTS.md` — agent briefing | ✅ Done | — |
| `CHANGELOG.md` | ❌ Missing | Start with current state, update per release |
| `mix blenny.gen.module MyModule` — scaffold a module | ❌ Missing | Generator template |
| `mix blenny.install` — add dep + config to host app | ❌ Missing | Installer |
| `mix blenny.init` — full application scaffold | ❌ Missing | Mix task |
| HexDocs publish (module docs, guides) | ❌ Missing | Enable in mix.exs, push on release |
| `@moduledoc` on all public modules (some are sparse) | 🟡 Partial | Fill in gaps |
| `@doc` on all public functions | 🟡 Partial | Fill in gaps — 19 added across 7 files in latest pass |
| CI pipeline | ❌ Missing | GitHub Actions: test, format, unused deps |
| Dialyzer | ❌ Missing | — |
| Coverage reporting | ❌ Missing | — |

## Milestones

### M0: Foundation (Phases 1-4)

The core architecture: connection layer, intents, transports, module system.

**Status: ✅ Complete**

Exit criteria:
- [x] `Blenny.Connection` struct created and tested
- [x] ETS registry with primary + dedup + user indexes
- [x] Hub GenServer for lifecycle coordination (register, monitor, dedup, DOWN cleanup)
- [x] Intent types, topic mapping, parsing, `accepts?/2`
- [x] Publisher with 5 broadcast/direct functions
- [x] SSE endpoint via `Blenny.Transport.SSEPlug` with Datastar wire format
- [x] LiveView `on_mount` hook via `Blenny.Transport.LiveViewBridge`
- [x] Module behaviour with all callbacks
- [x] Compile-time module discovery + capability conflict detection
- [x] Module lifecycle (initialize, start_supervised)
- [x] Boot sequence orchestrator
- [x] Monorepo with test app
- [x] 65+ unit tests passing
- [x] All files formatted, precommit passing

### M1: Integration-Ready (v0.2.0)

Production-light: enough for a brave early adopter to integrate into a real
app without fighting the framework.

**Status: 🟡 In Progress**

Exit criteria:
- [x] Telemetry events emitted from Hub (register, unregister, count)
- [x] Telemetry events from SSEPlug (bytes on message dispatch)
- [x] `max_connections` and `max_per_user` enforced in Hub
- [x] `nimble_options` validates `:blenny_ex` config at boot
- [x] Rate limiting per connection (process-local sliding window in SSEPlug)
- [x] Logger middleware (`Blenny.Plug.RequestLogger`)
- [x] Graceful shutdown (Hub drain state machine + transport signaling)
- [x] `subscriptions/0` callback wired (modules subscribed at boot)
- [x] `auth/0` callback implemented
- [x] SSEPlug unit tests written
- [x] Integration test for SSE dashboard via `Blenny.Publisher` public API (signals + HTML events through full pipeline)
- [ ] `Blenny.Router` macro documented and battle-tested
- [ ] "Getting Started" guide in `README.md` covering: add dep, config PubSub, add ModuleRegistry/Supervisor to tree, define first module, boot
- [ ] CI pipeline (GitHub Actions: test, format check, unused deps check)
- [ ] `CHANGELOG.md` started
- [x] Auth integration recipes documented (Pow, AshAuthentication, pipe_through patterns)

### M2: Production-Ready (v0.5.0-beta)

Hardened for production: comprehensive telemetry, load testing,
comprehensive testing.

**Status: 🔮 Future**

Exit criteria:
- [ ] All M1 items complete
- [ ] Telemetry from Publisher (emit per publish)
- [ ] Graceful shutdown tested (SIGTERM → SSE close frame → Hub cleanup → module stop)
- [ ] Load test: 100 concurrent SSE connections with metrics
- [ ] SSE reconnection backoff documented (or Datastar's built-in backoff deemed sufficient)
- [x] Stale connection sweeper (periodic ETS cleanup)
- [ ] Auth integration recipes complete, in HexDocs
- [ ] Connection draining tested (deploy scenario)
- [ ] Dialyzer passing with no unknown warnings
- [ ] Credo passing with ≤ 10 warnings
- [ ] Test coverage ≥ 80% (ExCoveralls)
- [ ] `connected_users/0` API
- [ ] Connection metadata (connect time, last activity, bytes sent)
- [ ] GitHub Actions passing on every push
- [ ] Published to Hex as `0.5.0-beta`

### M3: Stable (v1.0.0)

Feature-complete, stable API, external validation.

**Status: 🔮 Future**

Exit criteria:
- [ ] All M2 items complete
- [x] WebSocket transport consciously declined with documented rationale
- [x] Session-level state serialization across reconnects consciously declined (rationale in Resolved Decisions)
- [ ] API surface stable (no breaking changes planned for 1.x)
- [ ] `mix blenny.gen.module` generator shipped
- [ ] All `@moduledoc` and `@doc` tags complete
- [ ] Docs published on HexDocs
- [ ] `CHANGELOG.md` reflects all releases
- [ ] At least one external production user outside the monorepo
- [ ] `mix blenny.install` shipped
- [ ] Hex release v1.0.0

## Component Tracking

| Component | Status | Blockers |
|-----------|--------|----------|
| Connection struct | ✅ Done | — |
| ETS Registry | ✅ Done | — |
| Hub GenServer | ✅ Done | — |
| Dedup enforcement | ✅ Done | — |
| `max_connections` enforcement | ✅ Done | — |
| `max_per_user` enforcement | ✅ Done | — |
| Stale connection sweeper | ✅ Done | — |
| Connection draining | ✅ Done | — |
| Intent types + routing | ✅ Done | — |
| Intent filtering per transport | ✅ Done | — |
| Publisher (5 functions) | ✅ Done | — |
| Publisher telemetry | ❌ Missing | — |
| SSEPlug | ✅ Done | 28 unit tests |
| LiveViewBridge | ✅ Done | — |
| WebSocket transport | 🚫 Declined | See rationale in Transport Layer section |
| Module behaviour | ✅ Done | — |
| Module discovery | ✅ Done | — |
| Module lifecycle | ✅ Done | — |
| Route registration (Blenny.Router macro) | ✅ Done | — |
| `auth/0` callback | ✅ Done | — |
| Subscription wiring | ✅ Done | — |
| `handle_info({:blenny_subscribe, ...})` injection | ✅ Done | — |
| Config validation (`nimble_options`) | ✅ Done | — |
| Telemetry (Hub + SSEPlug) | ✅ Done | Publisher still missing |
| Graceful shutdown | ✅ Done | — |
| Rate limiting | ✅ Done | — |
| Logger middleware | ✅ Done | — |
| Boot sequence | ✅ Done | — |
| CI pipeline | ❌ Missing | — |
| Dialyzer | ❌ Missing | — |
| Coverage reporting | ❌ Missing | — |
| Hex metadata | ✅ Done | — |
| Hex publish | ❌ Missing | — |
| Docs on HexDocs | ❌ Missing | — |
| Generators (mix tasks) | ❌ Missing | — |
| SSE token auth | 🚫 Deferred | Auth module's `fetch_session` plug handles token validation |
| Auth integration patterns | 📝 Needed | Document Pow, AshAuthentication, pipe_through patterns |

## Dangling / Partial Items

These are features described in `ARCHITECTURE.md` or the module behaviour that
are partially implemented or not yet wired into the framework:

| Item | Status | Impact |
|------|--------|--------|
| `routes/0` callback auto-mounting | Macro exists and works (`blenny_modules/2`), needs battle-testing and docs | Generally usable |
| `max_connections` / `max_per_user` config defaults | Defaults exist, Hub enforces them | Working |
| `initialize/1` state | Only gets `%{pub_sub: pub_sub}` | No access to Hub ref, config, or registry |
| Publisher telemetry | Hub and SSEPlug emit telemetry; Publisher doesn't | No per-publish instrumentation |
| `connected_users/0` API | Not exposed | Must query ETS manually |
| Stale connection sweeper | ✅ Done | Periodic ETS sweep catches dead entries where DOWN was missed |
| Connection metadata | Not extended | Only dedup key stored, no timestamps/activity |
| Typed event system | Not started | Raw maps only |

## Resolved Decisions

These were previously listed as open questions.

1. **Auth integration** — **Auth via modules with framework plumbing.**
   Blenny provides the `Blenny.AuthRegistry`, pipeline plugs
   (`FetchSession`, `RequireUser`, `RequireRole`), and the
   `Blenny.Router` macro. Auth modules implement `Blenny.Module` with
   `capabilities: [:auth]` and an `auth/0` callback returning provider
   metadata. The module owns its storage strategy, UI, and cryptography.
   It registers its verification function with `AuthRegistry` during
   `initialize/1`. The framework plugs delegate to the registered
   provider at runtime. This preserves full encapsulation while
   eliminating the boilerplate of manual route wiring and plug
   configuration.

2. **Connection recovery** — **Consciously declined.** Datastar manages its own
   client-side reconnection loop. Blenny modules are either stateless
   (declarative) or cleanly addressable via `Blenny.ModuleRegistry`. No
   server-side state buffer cache needed. If an SSE stream drops and
   reconnects, the frontend sends current state via its signals payload; the
   backend reads signals, identifies the user, and resumes rendering.

3. **Database / ORM** — **Zero opinions.** No `Blenny.ORM` abstraction. Elixir
   community has rallied behind Ecto. Blenny stays focused on interactive
   delivery and routing.

4. **Route mounting** — **Provide `Blenny.Router` macro.** Idiomatic Elixir
   (mirrors Phoenix.LiveDashboard, Oban.Web, Ash):
   `import Blenny.Router` then `blenny_modules("/m")` in `router.ex`.

## Release Checklist

### Pre-Release (v0.2.0-pre)
- [x] Telemetry: Hub events (register, unregister, rejected)
- [x] Telemetry: SSEPlug (bytes)
- [x] Enforcement: max_connections, max_per_user
- [x] Validation: nimble_options config check at boot
- [x] Rate limiting per connection
- [x] Logger middleware
- [x] Graceful shutdown (Hub drain + transport signaling)
- [x] Wiring: subscriptions/0 callback + wire_subscriptions
- [x] auth/0 callback
- [x] Tests: SSEPlug unit tests (28)
- [x] Tests: SSE dashboard integration test (Publisher API through full pipeline)
- [x] Docs: "Getting Started" guide (10-step guide in README)
- [x] CI: GitHub Actions workflow (test, format, unused deps on push/PR)
- [ ] Changelog: v0.2.0-pre entry
- [x] Auth: integration recipes documented (Pow, AshAuthentication, pipe_through patterns)
- [ ] Publish to Hex as 0.2.0-pre

### Beta (v0.5.0-beta)
- [ ] All pre-release items complete
- [ ] Telemetry: Publisher events (per publish)
- [ ] Graceful shutdown tested
- [ ] Load test: 100 concurrent SSE
- [x] Stale connection sweeper
- [ ] Auth: integration recipes complete, in docs
- [ ] Connection draining tested
- [ ] Dialyzer + Credo clean
- [ ] Coverage ≥ 80%
- [ ] `connected_users/0` API
- [ ] Connection metadata (connect time, last activity, bytes)
- [ ] Publish to Hex as 0.5.0-beta

### Stable (v1.0.0)
- [ ] All beta items complete
- [x] WebSocket consciously declined (rationale documented in Transport Layer)
- [x] Session recovery consciously declined (rationale in Resolved Decisions)
- [ ] API surface stable
- [ ] mix blenny.gen.module
- [ ] mix blenny.install
- [ ] All docs complete on HexDocs
- [ ] Changelog complete
- [ ] External production user
- [ ] Publish to Hex as 1.0.0

## Dependency Stack

| Dependency | Purpose | Status |
|-----------|---------|--------|
| `phoenix` ~> 1.7 | HTTP server, routing, PubSub | ✅ Used |
| `phoenix_live_view` ~> 1.0 | LiveView WebSocket transport | ✅ Used (optional) |
| `bandit` ~> 1.5 | HTTP server | ✅ Used (optional) |
| `jason` ~> 1.2 | JSON encoding/decoding | ✅ Used |
| `dstar` ~> 0.0.10 | Datastar SSE wire format | ✅ Used |
| `telemetry` ~> 1.0 | Instrumentation | ✅ Used (Hub + SSEPlug events) |
| `nimble_options` ~> 1.0 | Configuration validation | ✅ Used (validated at boot) |
| `ex_doc` | Documentation generator | ✅ Used (dev only) |

## Testing Summary

### Current: 226 tests (204 blenny_ex + 22 example app) — all passing

#### blenny_ex (204 tests)

| Area | Tests | Status |
|------|-------|--------|
| Auth struct (`Blenny.Auth`) | 4 | ✅ |
| AuthRegistry | 5 | ✅ |
| Auth plugs (FetchSession, RequireUser, RequireRole) | 12 | ✅ |
| Router macro | 10 | ✅ |
| Connection struct | 3 | ✅ |
| Connection Registry | 13 | ✅ |
| Intent | 12 | ✅ |
| Config | 12 | ✅ |
| Error | 2 | ✅ |
| Hub (lifecycle, drain, telemetry, limits) | 19 | ✅ |
| Publisher | 9 | ✅ |
| Module behaviour | 3 | ✅ |
| Module Loader | 4 | ✅ |
| Module Lifecycle (initialize, wire_subscriptions) | 8 | ✅ |
| Bootstrap | 3 | ✅ |
| SSEPlug (unit + Bandit integration) | 30 | ✅ |
| Rate Limiter | 5 | ✅ |
| Request Logger | 7 | ✅ |
| Storage (UUID) | 5 | ✅ |
| Storage (InMemory) | 15 | ✅ |
| Storage (DETS) | 15 | ✅ |
| Storage (FSBlob) | 8 | ✅ |

#### blenny_example_app (22 tests)

| Area | Tests | Status |
|------|-------|--------|
| SSE dashboard integration | 4 | ✅ |
| FormAuth (sign-in, register, sign-out, crypto) | 13 | ✅ |
| Error pages | 4 | ✅ |
| Page controller | 1 | ✅ |

---

_Based on patterns from blenny-ts (TypeScript/Deno), blenny-rs (Rust),
blenny-clj (Clojure), and the original blenny (Pharo Smalltalk)._
