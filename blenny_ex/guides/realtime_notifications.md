# Realtime Notifications with SurrealDB

Broadcast database changes to connected SSE clients using SurrealDB live queries and `Blenny.SurrealDB.PublisherBridge`.

## How it works

SurrealDB's `LIVE SELECT * FROM <table>` fires a notification on every `CREATE`, `UPDATE`, or `DELETE` against that table. `Blenny.SurrealDB.PublisherBridge` subscribes to these notifications and forwards them through Blenny's Publisher pipeline to all connected SSE clients.

```
SurrealDB live query notification
  → PublisherBridge.handle_notification/3
    → Blenny.Publisher.broadcast_data(payload)
      → Connected SSE clients receive signal
```

## Setup

Add `Blenny.SurrealDB.PublisherBridge` to your module's `initialize/1` callback. It runs under the module's `DynamicSupervisor` alongside your other supervised children.

```elixir
def initialize(_app_state) do
  conn = DynamicSupervisor.start_child(
    Blenny.ModuleSupervisor,
    {SurrealDB, name: MyApp.SurrealDB, endpoint: "ws://localhost:8000/rpc", ...}
  )

  case conn do
    {:ok, pid} ->
      SurrealDB.Connection.wait_for_ready(pid)

      DynamicSupervisor.start_child(
        Blenny.ModuleSupervisor,
        {Blenny.SurrealDB.PublisherBridge,
         connection: pid,
         subscriptions: [%{table: "user", intent: :ui}]}
      )

    {:error, reason} ->
      Logger.warning("SurrealDB unavailable: #{inspect(reason)}")
  end

  :ok
end
```

The `:connection` option expects a connected SurrealDB PID or registered name. The `:subscriptions` option is a list of maps with `:table` (the SurrealDB table name) and `:intent` (one of `:ui`, `:command`, `:notification`).

## Notification payload

Every live query event produces a map broadcast via `Blenny.Publisher.broadcast_data/1`:

```elixir
%{
  table: "user",
  action: "CREATE",    # "CREATE" | "UPDATE" | "DELETE"
  data: %{             # the changed record
    uuid: "abc-123",
    username: "jane",
    ...
  }
}
```

SSE clients receive this as a Datastar signal. In your frontend JavaScript:

```javascript
Blenny.listen("data", (payload) => {
  if (payload.table === "user" && payload.action === "CREATE") {
    console.log("New user:", payload.data.username);
  }
});
```

## Example: broadcasting user changes from an auth module

A typical use case is broadcasting new user registrations or profile updates. Wire `PublisherBridge` in your auth module's `initialize/1` with a subscription to the `user` table, then handle the events in your LiveView or frontend code.

```elixir
def initialize(_app_state) do
  # ... connect to SurrealDB, start blob store, etc. ...

  DynamicSupervisor.start_child(
    Blenny.ModuleSupervisor,
    {Blenny.SurrealDB.PublisherBridge,
     connection: conn,
     subscriptions: [%{table: "user", intent: :ui}]}
  )

  # ... register auth provider, seed admin, etc. ...
end
```

This is intentionally minimal — the bridge handles the subscription lifecycle, reconnect, and notification dispatch. Your module only needs to start it with the right connection and table list.

## Security considerations

- **Be deliberate about table exposure.** Broadcasting user records to all clients may leak information you don't want public. Consider which tables and which fields to expose.
- **Use intent filtering** to control where notifications are delivered. `:ui` targets SSE and LiveView browsers. `:command` executes JavaScript. `:notification` targets alert channels.
- **Intent filtering per-transport is already handled by Blenny's Hub.** A subscription with `intent: :command` will only reach processes that registered with that capability.

## Adding and removing subscriptions at runtime

`PublisherBridge` exposes `subscribe/3` and `unsubscribe/2` for runtime management:

```elixir
# Add a new subscription
Blenny.SurrealDB.PublisherBridge.subscribe(bridge_pid, "order", :ui)

# Remove a subscription (kills the live query)
Blenny.SurrealDB.PublisherBridge.unsubscribe(bridge_pid, "order")

# Inspect current subscriptions
Blenny.SurrealDB.PublisherBridge.subscriptions(bridge_pid)
```

## Reconnection behavior

When the SurrealDB connection drops and reconnects (handled by the `SurrealDB.Connection` GenServer), `PublisherBridge` automatically re-subscribes to all configured tables. Failed re-subscriptions are retried with a 2-second backoff.
