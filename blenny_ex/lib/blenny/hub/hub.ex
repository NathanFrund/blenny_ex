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
  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = opts[:name] || Blenny.Hub
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Initiates graceful shutdown.

  Transitions the Hub into `:draining` mode — new registrations are
  rejected with `{:error, :draining}`, all transport processes receive
  a `{:blenny_drain, deadline}` signal, and the call blocks until all
  connections are cleaned up or the timeout expires.

  Returns `:drained` on success or `:already_draining` if already draining.

  Normally called automatically by OTP via `terminate/2` during
  application shutdown, but can also be called explicitly.
  """
  @spec drain(GenServer.server(), timeout()) :: :drained | :already_draining
  def drain(hub \\ __MODULE__, timeout \\ 30_000) do
    GenServer.call(hub, {:drain, timeout})
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
  @spec register_connection(GenServer.server(), Blenny.Connection.t()) ::
          {:ok, Blenny.Connection.t()} | {:error, atom()}
  def register_connection(hub \\ __MODULE__, conn) when is_struct(conn, Blenny.Connection) do
    GenServer.call(hub, {:register_connection, conn})
  end

  @doc """
  Unregisters a connection by ID.
  """
  @spec unregister_connection(GenServer.server(), String.t()) :: Blenny.Connection.t() | nil
  def unregister_connection(hub \\ __MODULE__, conn_id) when is_binary(conn_id) do
    GenServer.call(hub, {:unregister_connection, conn_id})
  end

  @doc """
  Looks up a connection by ID.
  """
  @spec lookup_connection(GenServer.server(), String.t()) :: Blenny.Connection.t() | nil
  def lookup_connection(hub \\ __MODULE__, conn_id) when is_binary(conn_id) do
    GenServer.call(hub, {:lookup_connection, conn_id})
  end

  @doc """
  Returns all connections.
  """
  @spec list_connections(GenServer.server()) :: [Blenny.Connection.t()]
  def list_connections(hub \\ __MODULE__) do
    GenServer.call(hub, :list_connections)
  end

  @doc """
  Returns connection count.
  """
  @spec connection_count(GenServer.server()) :: non_neg_integer()
  def connection_count(hub \\ __MODULE__) do
    GenServer.call(hub, :connection_count)
  end

  @doc """
  Returns unique user IDs with active connections.
  """
  @spec connected_users(GenServer.server()) :: [String.t()]
  def connected_users(hub \\ __MODULE__) do
    GenServer.call(hub, :connected_users)
  end

  @doc """
  Builds the dedup key for a connection.

  Uses `user_id` if present, otherwise falls back to `conn.id` (each
  anonymous connection is its own dedup group).
  """
  @spec dedup_key(map()) :: String.t()
  def dedup_key(%{user_id: user_id}) when is_binary(user_id), do: user_id
  def dedup_key(%{id: id}), do: id

  # ── Server callbacks ───────────────────────────────────────────

  @impl true
  def init(opts) do
    Blenny.Connection.Registry.start_link()

    stale_sweep_interval =
      if Keyword.has_key?(opts, :stale_sweep_interval) do
        opts[:stale_sweep_interval]
      else
        Blenny.Config.get([:hub, :stale_sweep_interval])
      end

    if stale_sweep_interval do
      Process.send_after(self(), :sweep_stale_connections, stale_sweep_interval)
    end

    {:ok,
     %{
       monitors_by_ref: %{},
       monitors_by_conn: %{},
       max_connections: opts[:max_connections] || Blenny.Config.get([:hub, :max_connections]),
       max_per_user: opts[:max_per_user] || Blenny.Config.get([:hub, :max_per_user]),
       drain_state: :accepting,
       drain_timeout: opts[:drain_timeout] || Blenny.Config.get([:hub, :drain_timeout]),
       stale_sweep_interval: stale_sweep_interval
     }}
  end

  @impl true
  def handle_call({:register_connection, _conn}, _from, %{drain_state: :draining} = state) do
    {:reply, {:error, :draining}, state}
  end

  @impl true
  def handle_call({:register_connection, conn}, _from, state) do
    conn_count = Blenny.Connection.Registry.count()

    if conn_count >= state.max_connections do
      :telemetry.execute(
        [:blenny, :hub, :connection, :rejected],
        %{count: conn_count},
        %{user_id: conn.user_id, conn_type: conn.conn_type, limit_type: :max_connections}
      )

      {:reply, {:error, :too_many_connections}, state}
    else
      dedup_key = dedup_key(conn)
      per_user_count = Blenny.Connection.Registry.count_by_dedup_key(dedup_key)

      if per_user_count >= state.max_per_user do
        :telemetry.execute(
          [:blenny, :hub, :connection, :rejected],
          %{count: conn_count},
          %{user_id: conn.user_id, conn_type: conn.conn_type, limit_type: :max_per_user}
        )

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

        :telemetry.execute(
          [:blenny, :hub, :connection, :register],
          %{count: Blenny.Connection.Registry.count()},
          %{user_id: conn.user_id, conn_type: conn.conn_type}
        )

        {:reply, {:ok, conn}, state}
      end
    end
  end

  @impl true
  def handle_call({:unregister_connection, conn_id}, _from, state) do
    conn = Blenny.Connection.Registry.lookup(conn_id)
    Blenny.Connection.Registry.unregister(conn_id)
    state = demonitor_if_pid(state, conn && conn.transport_pid)

    if conn do
      :telemetry.execute(
        [:blenny, :hub, :connection, :unregister],
        %{count: Blenny.Connection.Registry.count()},
        %{user_id: conn.user_id, conn_type: conn.conn_type, reason: :explicit}
      )
    end

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
  def handle_call(:connected_users, _from, state) do
    {:reply, Blenny.Connection.Registry.connected_users(), state}
  end

  @impl true
  def handle_call({:drain, _timeout}, _from, %{drain_state: :draining} = state) do
    {:reply, :already_draining, state}
  end

  @impl true
  def handle_call({:drain, timeout}, _from, state) do
    signal_transports(state.monitors_by_conn)
    drained_state = drain_wait(state, timeout)
    {:reply, :drained, drained_state}
  end

  @impl true
  def terminate(_reason, %{drain_state: :draining} = state) do
    drain_wait(state, state.drain_timeout)
  end

  @impl true
  def terminate(_reason, state) do
    signal_transports(state.monitors_by_conn)
    drain_wait(state, state.drain_timeout)
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case state.monitors_by_ref[ref] do
      nil ->
        {:noreply, state}

      conn_id ->
        conn = Blenny.Connection.Registry.lookup(conn_id)
        Blenny.Connection.Registry.unregister(conn_id)

        if conn do
          :telemetry.execute(
            [:blenny, :hub, :connection, :unregister],
            %{count: Blenny.Connection.Registry.count()},
            %{user_id: conn.user_id, conn_type: conn.conn_type, reason: :process_down}
          )
        end

        {:noreply,
         %{
           state
           | monitors_by_ref: Map.delete(state.monitors_by_ref, ref),
             monitors_by_conn: Map.delete(state.monitors_by_conn, conn_id)
         }}
    end
  end

  @impl true
  def handle_info(:sweep_stale_connections, state) do
    stale_conns =
      Blenny.Connection.Registry.all()
      |> Enum.filter(fn conn ->
        conn.transport_pid && !Process.alive?(conn.transport_pid)
      end)

    for conn <- stale_conns do
      Blenny.Connection.Registry.unregister(conn.id)

      :telemetry.execute(
        [:blenny, :hub, :connection, :unregister],
        %{count: Blenny.Connection.Registry.count()},
        %{user_id: conn.user_id, conn_type: conn.conn_type, reason: :stale_sweep}
      )
    end

    if state.stale_sweep_interval do
      Process.send_after(self(), :sweep_stale_connections, state.stale_sweep_interval)
    end

    {:noreply, state}
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

  # ── Graceful Drain ─────────────────────────────────────────────

  defp signal_transports(monitors_by_conn) do
    deadline = System.monotonic_time(:millisecond) + 30_000

    for {_conn_id, %{pid: pid}} <- monitors_by_conn do
      send(pid, {:blenny_drain, deadline})
    end
  end

  defp drain_wait(state, timeout) do
    monitors = state.monitors_by_ref

    if map_size(monitors) > 0 do
      wait_for_down(monitors, timeout)
    end

    %{state | monitors_by_ref: %{}, monitors_by_conn: %{}, drain_state: :draining}
  end

  defp wait_for_down(monitors, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout

    wait_for_down_loop(monitors, deadline)
  end

  defp wait_for_down_loop(monitors, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining > 0 and map_size(monitors) > 0 do
      receive do
        {:DOWN, ref, :process, _pid, _reason} ->
          case monitors[ref] do
            nil ->
              wait_for_down_loop(monitors, deadline)

            conn_id ->
              Blenny.Connection.Registry.unregister(conn_id)
              wait_for_down_loop(Map.delete(monitors, ref), deadline)
          end
      after
        remaining ->
          :ok
      end
    end
  end
end
