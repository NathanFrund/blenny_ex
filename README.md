# Blenny (Elixir)

Multi-transport hypermedia engine for Phoenix — SSE (Datastar) and LiveView.
Write unified components that deliver over Server-Sent Events or LiveView
WebSockets, routing transport based on the client's runtime environment.

## Repository structure

```
blenny_ex/              — Hex-publishable library (the framework)
  lib/blenny/
    module.ex           — Module lifecycle (routes, capabilities, init)
    router.ex           — blenny_modules/2 macro for Phoenix routers
    hub/                — Connection lifecycle, ETS registry, limits, drain
    transport/          — SSEPlug (Datastar), LiveViewBridge (on_mount hook)
    publisher.ex        — broadcast_html/data/script, direct delivery
    plug/               — FetchSession, RequestLogger, RequireUser, RequireRole
    auth/               — AuthRegistry, session plugs
    config.ex           — NimbleOptions schema, validated at boot
    bootstrap.ex        — Boot orchestrator
    rate_limiter.ex     — Per-connection sliding window (process-local)

blenny_example_app/     — Example Phoenix app consuming blenny_ex
  /blenny/form_auth.ex  — Auth provider with ETS/DETS storage
  /blenny/dashboard_module.ex — Stateful module with periodic metrics
  /dashboard_live.ex    — LiveView dashboard consuming Blenny events
```

## Quick start

Add `blenny_ex` to your Phoenix project:

```elixir
def deps do
  [
    {:blenny_ex, "~> 0.1.0"}
  ]
end
```

Or from this monorepo:

```elixir
{:blenny_ex, path: "../blenny_ex"}
```

See [`blenny_ex/README.md`](blenny_ex/README.md) for the full 10-step
quickstart guide.
