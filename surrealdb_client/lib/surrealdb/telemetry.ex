defmodule SurrealDB.Telemetry do
  @moduledoc """
  Telemetry events emitted by the SurrealDB client.

  ## Events

    * `[:surrealdb, :query, :start]` — before a query is sent
      * Measurements: %{system_time: system_time}
      * Metadata: %{method: String.t(), args: map()}
    * `[:surrealdb, :query, :stop]` — after a query completes
      * Measurements: %{duration: native_time}
      * Metadata: %{method: String.t(), args: map()}
    * `[:surrealdb, :query, :exception]` — on query error
      * Measurements: %{duration: native_time}
      * Metadata: %{method: String.t(), args: map(), error: term()}
    * `[:surrealdb, :live_query, :notification]` — live query event received
      * Measurements: %{}
      * Metadata: %{query_id: String.t(), action: String.t(), data: map()}
    * `[:surrealdb, :connection, :connect]` — WebSocket connected
      * Measurements: %{}
      * Metadata: %{hostname: String.t(), port: integer()}
    * `[:surrealdb, :connection, :disconnect]` — WebSocket disconnected
      * Measurements: %{}
      * Metadata: %{reason: term()}
    * `[:surrealdb, :connection, :reconnect]` — reconnection attempt
      * Measurements: %{attempt: pos_integer()}
      * Metadata: %{}
  """

  @doc "Emits a start event for a query method."
  def query_start(method, args) do
    :telemetry.execute(
      [:surrealdb, :query, :start],
      %{system_time: System.system_time()},
      %{method: method, args: args}
    )
  end

  @doc "Emits a stop event for a query method."
  def query_stop(method, args, start_time) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:surrealdb, :query, :stop],
      %{duration: duration},
      %{method: method, args: args}
    )
  end

  @doc "Emits an exception event for a query method."
  def query_exception(method, args, start_time, error) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:surrealdb, :query, :exception],
      %{duration: duration},
      %{method: method, args: args, error: error}
    )
  end

  @doc "Emits a live query notification event."
  def live_query_notification(query_id, action, data) do
    :telemetry.execute(
      [:surrealdb, :live_query, :notification],
      %{},
      %{query_id: query_id, action: action, data: data}
    )
  end

  @doc "Emits a connection event (connect, disconnect, reconnect)."
  def connection_event(event, metadata) do
    :telemetry.execute(
      [:surrealdb, :connection, event],
      %{},
      metadata
    )
  end
end
