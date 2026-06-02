# BlennyEx

Multi-transport hypermedia engine for Phoenix — SSE (Datastar) and LiveView.

Blenny provides a reusable module system, connection registry, PubSub-based
message routing, and zero-ceremony broadcast APIs across SSE and LiveView
transports.

## Installation

Add `blenny_ex` to your `mix.exs`:

```elixir
def deps do
  [
    {:blenny_ex, "~> 0.1.0"}
  ]
end
```

In an umbrella app or monorepo, use a path dependency:

```elixir
def deps do
  [
    {:blenny_ex, path: "../blenny_ex"}
  ]
end
```

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
- **Blenny.Publisher** — `broadcast_data/1`, `broadcast_html/1`, `execute_script/1`
- **Blenny.Hub** — PubSub subscriber that dispatches to registered transport processes
- **Blenny.Connection.Registry** — ETS-backed registry with session-level dedup
- **Blenny.Transport.SSEPlug** — long-lived SSE via Bandit `send_chunked/1`
- **Blenny.Transport.LiveViewBridge** — `on_mount` for LiveView transport integration

