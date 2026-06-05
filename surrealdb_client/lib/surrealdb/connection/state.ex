defmodule SurrealDB.Connection.State do
  @moduledoc """
  Holds the state of a SurrealDB WebSocket connection.

  Tracks:
    * Pending request tasks by request ID
    * Active live queries by query UUID
    * Live query SQL statements for re-subscription after reconnect
    * Authentication readiness
  """

  defstruct pending: %{},
            lq_running: %{},
            lq_sql: MapSet.new(),
            auth_ready: false,
            config: %{}

  @type t :: %__MODULE__{
          pending: map(),
          lq_running: map(),
          lq_sql: MapSet.t(),
          auth_ready: boolean(),
          config: keyword()
        }

  def new(config) do
    %__MODULE__{config: config}
  end

  def register_task(state, id, task) do
    %{state | pending: Map.put(state.pending, id, task)}
  end

  def get_task(state, id) do
    Map.get(state.pending, id)
  end

  def delete_task(state, id) do
    %{state | pending: Map.delete(state.pending, id)}
  end

  def register_live_query(state, sql, query_id, callback) do
    lq_sql = MapSet.put(state.lq_sql, {sql, callback})
    item = %{sql: sql, query_id: query_id, callback: callback}

    %{state | lq_running: Map.put(state.lq_running, query_id, item), lq_sql: lq_sql}
  end

  def get_live_query(state, query_id) do
    Map.get(state.lq_running, query_id)
  end

  def delete_live_query(state, query_id) do
    case Map.pop(state.lq_running, query_id) do
      {nil, _} -> state
      {item, lq_running} ->
        lq_sql = MapSet.delete(state.lq_sql, {item.sql, item.callback})
        %{state | lq_running: lq_running, lq_sql: lq_sql}
    end
  end

  def all_live_queries(state) do
    MapSet.to_list(state.lq_sql)
  end

  def reset_live_queries(state) do
    %{state | lq_running: %{}, lq_sql: MapSet.new()}
  end

  def set_auth_ready(state, value) do
    %{state | auth_ready: value}
  end
end
