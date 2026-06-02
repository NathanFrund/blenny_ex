defmodule Blenny.Hub do
  @moduledoc """
  Central connection registry and message dispatcher for Blenny.

  The Hub is a GenServer that:
    - Maintains the ETS-based connection registry
    - Subscribes to Phoenix PubSub topics for intent-based routing
    - Dispatches messages to the appropriate transport processes (LiveView/SSE)
    - Enforces session-level dedup (one connection per session)

  ## PubSub Topics

  The Hub subscribes to the following topics at boot:

    - `"blenny:intent:<intent>"` — for each of the 5 intent types
    - `"blenny:direct"` — for targeted (per-user) messages

  When a message arrives on a PubSub topic, the Hub looks up matching
  connections from the ETS registry and forwards the message to each
  connection's transport process via `send(transport_pid, {:blenny_message, msg})`.
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

  Enforces session-level dedup: if a connection already exists for the
  given `session_id`, the old connection is replaced and its transport
  process is notified to stop.
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

  # ── Server callbacks ───────────────────────────────────────────

  @impl true
  def init(opts) do
    pub_sub = opts[:pub_sub] || Blenny.pub_sub()

    Blenny.Connection.Registry.start_link()

    topics = Enum.map(Blenny.Intent.all(), &Blenny.Intent.to_topic/1)
    topics = topics ++ ["blenny:direct"]

    for topic <- topics do
      :ok = Phoenix.PubSub.subscribe(pub_sub, topic, link: true)
    end

    {:ok,
     %{
       pub_sub: pub_sub,
       topics: topics,
       monitors_by_ref: %{},
       monitors_by_conn: %{}
     }}
  end

  @impl true
  def handle_call({:register_connection, conn}, _from, state) do
    state =
      case Blenny.Connection.Registry.lookup_by_session(conn.session_id) do
        [existing] ->
          Blenny.Connection.Registry.unregister(existing.id)
          state = demonitor_if_pid(state, existing.transport_pid)

          if existing.transport_pid do
            send(existing.transport_pid, {:blenny_replaced, conn.id})
          end

          state

        _ ->
          state
      end

    {:ok, _} = Blenny.Connection.Registry.register(conn)
    state = monitor_if_pid(state, conn)

    {:reply, {:ok, conn}, state}
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

  # ── Message dispatch ───────────────────────────────────────────

  defp dispatch_to_intent(_intent, msg) do
    filter_user_id = msg[:user_id]

    connections =
      if filter_user_id do
        Blenny.Connection.Registry.lookup_by_user(filter_user_id)
      else
        Blenny.Connection.Registry.all()
      end

    connections
    |> Enum.each(&send_to_connection(&1, msg))
  end

  defp send_to_connection(%{transport_pid: nil}, _msg), do: :ok

  defp send_to_connection(%{transport_pid: pid} = conn, msg) when is_pid(pid) do
    send(pid, {:blenny_message, conn.id, msg})
  end

  @impl true
  def handle_info(%{__struct__: _}, state) do
    # Skip structs (e.g. Phoenix.Socket.Broadcast from LiveView)
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) when is_map(msg) do
    dispatch_to_intent(nil, msg)
    {:noreply, state}
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
