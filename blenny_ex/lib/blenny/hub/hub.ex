defmodule Blenny.Hub do
  @moduledoc """
  Lifecycle coordinator for Blenny connections.

  The Hub is a lightweight GenServer that:
    - Maintains the ETS-based connection registry (observability)
    - Enforces `{user_id, conn_type}` dedup (one SSE + one LiveView per user)
    - Monitors transport processes and cleans up on crash

  The Hub does **not** route messages. Publishers publish directly to
  `Phoenix.PubSub` topics (`blenny:intent:*`, `blenny:user:*`) and transport
  processes subscribe to those topics themselves.
  """

  use GenServer

  # ── Client API ─────────────────────────────────────────────────

  @doc """
  Starts the Hub GenServer. Called during boot.
  """
  def start_link(opts \\ []) do
    name = opts[:name] || Blenny.Hub
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Registers a connection.

  Enforces connection limits before registering:
    - `max_connections` — system-wide cap, returns `{:error, :too_many_connections}` when exceeded
    - `max_per_user` — per-dedup-key cap (user_id for authenticated, conn.id for anonymous),
      returns `{:error, :too_many_per_user}` when exceeded

  Enforces `{user_id, conn_type}` dedup: if a connection already exists for
  the same user and type, the old connection receives a
  `{:blenny_replaced, new_pid}` message and the new one takes its place.
  """
  def register_connection(hub \\ __MODULE__, conn) when is_struct(conn, Blenny.Connection) do
    GenServer.call(hub, {:register_connection, conn})
  end

  @doc """
  Unregisters a connection by ID.
  """
  def unregister_connection(hub \\ __MODULE__, conn_id) when is_binary(conn_id) do
    GenServer.call(hub, {:unregister_connection, conn_id})
  end

  @doc """
  Looks up a connection by ID.
  """
  def lookup_connection(hub \\ __MODULE__, conn_id) when is_binary(conn_id) do
    GenServer.call(hub, {:lookup_connection, conn_id})
  end

  @doc """
  Returns all connections.
  """
  def list_connections(hub \\ __MODULE__) do
    GenServer.call(hub, :list_connections)
  end

  @doc """
  Returns connection count.
  """
  def connection_count(hub \\ __MODULE__) do
    GenServer.call(hub, :connection_count)
  end

  @doc """
  Builds the dedup key for a connection.

  Uses `user_id` if present, otherwise falls back to `conn.id` (each
  anonymous connection is its own dedup group).
  """
  def dedup_key(%{user_id: user_id}) when is_binary(user_id), do: user_id
  def dedup_key(%{id: id}), do: id

  # ── Server callbacks ───────────────────────────────────────────

  @impl true
  def init(opts) do
    Blenny.Connection.Registry.start_link()

    {:ok,
     %{
       monitors_by_ref: %{},
       monitors_by_conn: %{},
       max_connections: opts[:max_connections] || Blenny.Config.get([:hub, :max_connections]),
       max_per_user: opts[:max_per_user] || Blenny.Config.get([:hub, :max_per_user])
     }}
  end

  @impl true
  def handle_call({:register_connection, conn}, _from, state) do
    conn_count = Blenny.Connection.Registry.count()

    if conn_count >= state.max_connections do
      {:reply, {:error, :too_many_connections}, state}
    else
      dedup_key = dedup_key(conn)
      per_user_count = Blenny.Connection.Registry.count_by_dedup_key(dedup_key)

      if per_user_count >= state.max_per_user do
        {:reply, {:error, :too_many_per_user}, state}
      else
        existing = Blenny.Connection.Registry.lookup_by_dedup_key(dedup_key, conn.conn_type)

        state =
          if existing do
            send(existing.transport_pid, {:blenny_replaced, conn.transport_pid})
            demonitor_if_pid(state, existing.transport_pid)
            Blenny.Connection.Registry.unregister(existing.id)
            state
          else
            state
          end

        {:ok, _} = Blenny.Connection.Registry.register(conn)
        state = monitor_if_pid(state, conn)

        {:reply, {:ok, conn}, state}
      end
    end
  end

  @impl true
  def handle_call({:unregister_connection, conn_id}, _from, state) do
    conn = Blenny.Connection.Registry.unregister(conn_id)
    state = demonitor_if_pid(state, conn && conn.transport_pid)
    {:reply, conn, state}
  end

  @impl true
  def handle_call({:lookup_connection, conn_id}, _from, state) do
    {:reply, Blenny.Connection.Registry.lookup(conn_id), state}
  end

  @impl true
  def handle_call(:list_connections, _from, state) do
    {:reply, Blenny.Connection.Registry.all(), state}
  end

  @impl true
  def handle_call(:connection_count, _from, state) do
    {:reply, Blenny.Connection.Registry.count(), state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case state.monitors_by_ref[ref] do
      nil ->
        {:noreply, state}

      conn_id ->
        Blenny.Connection.Registry.unregister(conn_id)

        {:noreply,
         %{
           state
           | monitors_by_ref: Map.delete(state.monitors_by_ref, ref),
             monitors_by_conn: Map.delete(state.monitors_by_conn, conn_id)
         }}
    end
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  defp monitor_if_pid(state, %{transport_pid: pid, id: conn_id}) when is_pid(pid) do
    ref = Process.monitor(pid)

    %{
      state
      | monitors_by_ref: Map.put(state.monitors_by_ref, ref, conn_id),
        monitors_by_conn: Map.put(state.monitors_by_conn, conn_id, %{ref: ref, pid: pid})
    }
  end

  defp monitor_if_pid(state, _conn), do: state

  defp demonitor_if_pid(state, pid) when is_pid(pid) do
    {refs, monitors_by_conn} =
      Enum.reduce(state.monitors_by_conn, {[], %{}}, fn {conn_id, %{ref: ref, pid: p}},
                                                        {refs_acc, rest_acc} ->
        if p == pid do
          Process.demonitor(ref, [:flush])
          {[ref | refs_acc], rest_acc}
        else
          {refs_acc, Map.put(rest_acc, conn_id, %{ref: ref, pid: p})}
        end
      end)

    monitors_by_ref =
      Enum.reduce(refs, state.monitors_by_ref, fn ref, acc -> Map.delete(acc, ref) end)

    %{
      state
      | monitors_by_ref: monitors_by_ref,
        monitors_by_conn: monitors_by_conn
    }
  end

  defp demonitor_if_pid(state, _pid), do: state
end
