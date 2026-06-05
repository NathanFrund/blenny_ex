defmodule Blenny.SurrealDB.PublisherBridge do
  @moduledoc """
  Bridges SurrealDB live query notifications into Blenny's Publisher pipeline.

  Starts a GenServer that subscribes to `LIVE SELECT * FROM <table>` for each
  configured table and forwards change notifications to connected SSE clients
  via `Blenny.Publisher.broadcast_data/1`.

  ## Usage

      {:ok, conn} = SurrealDB.start_link(...)

      config = [
        connection: conn,
        subscriptions: [
          %{table: "user", intent: :ui},
          %{table: "order", intent: :ui}
        ]
      ]

      {:ok, bridge} = Blenny.SurrealDB.PublisherBridge.start_link(config)

  ## Notification format

  Live query notifications are published as signal data with the following shape:

      %{
        table: "user",
        action: "CREATE" | "UPDATE" | "DELETE",
        data: %{...}  # the changed record
      }
  """

  require Logger

  use GenServer

  @doc """
  Starts the bridge with the given configuration.

  ## Options

    * `:connection` — (required) SurrealDB connection PID
    * `:subscriptions` — (required) list of `%{table: String.t(), intent: atom()}` maps
    * `:name` — optional registered name
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @doc "Adds a new table subscription at runtime."
  @spec subscribe(pid(), String.t(), atom()) :: :ok
  def subscribe(pid, table, intent \\ :ui) do
    GenServer.cast(pid, {:subscribe, table, intent})
  end

  @doc "Unsubscribes from a table's live query."
  @spec unsubscribe(pid(), String.t()) :: :ok
  def unsubscribe(pid, table) do
    GenServer.cast(pid, {:unsubscribe, table})
  end

  @doc "Returns the list of active subscriptions."
  @spec subscriptions(pid()) :: [%{table: String.t(), intent: atom()}]
  def subscriptions(pid) do
    GenServer.call(pid, :subscriptions)
  end

  # ── GenServer callbacks ────────────────────────────────────────────

  @impl true
  def init(opts) do
    conn = Keyword.fetch!(opts, :connection)
    subscriptions = Keyword.fetch!(opts, :subscriptions)

    state = %{
      conn: conn,
      subscriptions: Map.new(subscriptions, &{&1.table, &1.intent}),
      live_query_ids: %{}
    }

    {:ok, state, {:continue, :subscribe}}
  end

  @impl true
  def handle_continue(:subscribe, state) do
    {:noreply, subscribe_all(state)}
  end

  @impl true
  def handle_continue({:subscribe_one, table, intent}, state) do
    case do_subscribe(state, table, intent) do
      {:ok, new_state} -> {:noreply, new_state}
      {:error, _reason} -> {:noreply, state}
    end
  end

  @impl true
  def handle_call(:subscriptions, _from, state) do
    subs = Enum.map(state.subscriptions, fn {table, intent} -> %{table: table, intent: intent} end)
    {:reply, subs, state}
  end

  @impl true
  def handle_cast({:subscribe, table, intent}, state) do
    if Map.has_key?(state.subscriptions, table) do
      {:noreply, state}
    else
      subscriptions = Map.put(state.subscriptions, table, intent)
      {:noreply, %{state | subscriptions: subscriptions}, {:continue, {:subscribe_one, table, intent}}}
    end
  end

  @impl true
  def handle_cast({:unsubscribe, table}, state) do
    case Map.pop(state.live_query_ids, table) do
      {nil, _} ->
        {:noreply, state}

      {lq_id, live_query_ids} ->
        SurrealDB.kill(state.conn, lq_id)
        subscriptions = Map.delete(state.subscriptions, table)
        {:noreply, %{state | subscriptions: subscriptions, live_query_ids: live_query_ids}}
    end
  end

  # ── Live query callback ────────────────────────────────────────────

  defp subscribe_all(state) do
    Enum.reduce(state.subscriptions, state, fn {table, _intent}, acc ->
      case do_subscribe(acc, table, acc.subscriptions[table]) do
        {:ok, new_state} -> new_state
        {:error, _reason} -> acc
      end
    end)
  end

  defp do_subscribe(state, table, intent) do
    case SurrealDB.live_query(state.conn, "LIVE SELECT * FROM #{table}", %{}, fn json, _lq_id ->
           handle_notification(json, table, intent)
         end) do
      {:ok, %{query_id: lq_id}} ->
        {:ok, %{state | live_query_ids: Map.put(state.live_query_ids, table, lq_id)}}

      {:error, reason} ->
        Logger.warning("[PublisherBridge] Failed to subscribe to #{table}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp handle_notification(json, table, intent) do
    action = get_in(json, ["result", "action"]) || "UNKNOWN"
    data = get_in(json, ["result", "result"]) || %{}

    payload = %{table: table, action: action, data: data}

    case intent do
      :command ->
        script = "window.__blenny_surreal_event({table: '#{table}', action: '#{action}'})"
        Blenny.Publisher.execute_script(script)

      _ ->
        Blenny.Publisher.broadcast_data(payload)
    end
  end
end
