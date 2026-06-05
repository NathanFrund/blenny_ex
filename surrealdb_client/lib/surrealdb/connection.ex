defmodule SurrealDB.Connection do
  @moduledoc """
  WebSocket GenServer for the SurrealDB RPC protocol.

  Uses `WebSockex` to maintain a persistent WebSocket connection to
  SurrealDB. Handles request/response matching, live query callbacks,
  reconnection with automatic live query re-subscription, and telemetry.

  ## Starting

      opts = [
        hostname: "localhost",
        port: 8000,
        username: "root",
        password: "root",
        namespace: "test",
        database: "test"
      ]

      {:ok, pid} = SurrealDB.Connection.start_link(opts)
  """

  use WebSockex

  alias SurrealDB.Connection.State
  alias SurrealDB.Protocol
  alias SurrealDB.Telemetry

  require Logger

  @doc "Starts the WebSocket connection without linking."
  @spec start(keyword()) :: {:ok, pid} | {:error, term()}
  def start(opts \\ []) do
    generic_start(opts, :start)
  end

  @doc "Starts the WebSocket connection linked to the caller."
  @spec start_link(keyword()) :: {:ok, pid} | {:error, term()}
  def start_link(opts \\ []) do
    generic_start(opts, :start_link)
  end

  @doc "Sends a SurrealQL query and awaits the response."
  @spec query(pid(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def query(pid, sql, vars \\ %{}, opts \\ []) do
    exec_method(pid, "query", [sql: sql, vars: vars], opts)
  end

  @doc "Signs in with credentials."
  @spec signin(pid(), map()) :: {:ok, map()} | {:error, term()}
  def signin(pid, payload) do
    exec_method(pid, "signin", [payload: payload], [])
  end

  @doc "Selects namespace and database."
  @spec use(pid(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def use(pid, ns, db) do
    exec_method(pid, "use", [ns: ns, db: db], [])
  end

  @doc "Creates a record."
  @spec create(pid(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def create(pid, thing, data \\ %{}) do
    exec_method(pid, "create", [thing: thing, data: data], [])
  end

  @doc "Selects records."
  @spec select(pid(), String.t()) :: {:ok, map()} | {:error, term()}
  def select(pid, thing) do
    exec_method(pid, "select", [thing: thing], [])
  end

  @doc "Updates a record."
  @spec update(pid(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def update(pid, thing, data) do
    exec_method(pid, "update", [thing: thing, data: data], [])
  end

  @doc "Merges data into a record."
  @spec merge(pid(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def merge(pid, thing, data) do
    exec_method(pid, "merge", [thing: thing, data: data], [])
  end

  @doc "Deletes a record."
  @spec delete(pid(), String.t()) :: {:ok, map()} | {:error, term()}
  def delete(pid, thing) do
    exec_method(pid, "delete", [thing: thing], [])
  end

  @doc """
  Registers a live query with a callback.

  The callback receives `(notification_map, query_uuid)` on each event.
  """
  @spec live_query(pid(), String.t(), map(), function()) :: {:ok, map()} | {:error, term()}
  def live_query(pid, sql, vars \\ %{}, callback) do
    start_time = System.monotonic_time()

    result = exec_method(pid, "query", [sql: sql, vars: vars], [])

    case result do
      {:ok, %{"result" => [%{"result" => lq_id}]}} ->
        WebSockex.cast(pid, {:register_live_query, sql, lq_id, callback})
        Telemetry.query_stop("live_query", [sql: sql], start_time)
        {:ok, %{query_id: lq_id}}

      other ->
        Telemetry.query_exception("live_query", [sql: sql], start_time, other)
        other
    end
  end

  @doc "Kills an active live query."
  @spec kill(pid(), String.t()) :: {:ok, map()} | {:error, term()}
  def kill(pid, query_uuid) do
    exec_method(pid, "kill", [query_uuid: query_uuid], [])
  end

  @doc "Pings the server."
  @spec ping(pid()) :: {:ok, map()} | {:error, term()}
  def ping(pid) do
    exec_method(pid, "ping", [], [])
  end

  @doc "Returns info about the current authenticated user."
  @spec info(pid()) :: {:ok, map()} | {:error, term()}
  def info(pid) do
    exec_method(pid, "info", [], [])
  end

  @doc "Returns all registered live queries as `[{sql, callback}]`."
  @spec all_live_queries(pid()) :: [{String.t(), function()}]
  def all_live_queries(pid) do
    State.all_live_queries(:sys.get_state(pid))
  end

  @doc """
  Waits until the WebSocket connection is ready (handshake complete).
  Returns `:ok` or `{:error, :timeout}`.
  """
  @spec wait_for_ready(pid(), pos_integer()) :: :ok | {:error, :timeout}
  def wait_for_ready(pid, timeout \\ 5_000) do
    deadline = System.monotonic_time() + System.convert_time_unit(timeout, :millisecond, :native)
    wait_loop(pid, deadline)
  end

  @doc """
  Authenticates a connection (signin + use). Must be called AFTER the
  WebSocket handshake completes (`wait_for_ready/1` returns `:ok`).
  """
  @spec authenticate(pid()) :: :ok | {:error, term()}
  def authenticate(pid) do
    config = :sys.get_state(pid).config
    auth_payload = %{user: config[:username], pass: config[:password]}
    ns = config[:namespace]
    db = config[:database]

    with {:ok, _} <- signin(pid, auth_payload),
         {:ok, _} <- use(pid, ns, db) do
      :ok
    end
  end

  # ----- WebSockex callbacks -----

  @impl true
  def handle_connect(_conn, state) do
    Telemetry.connection_event(:connect, %{
      hostname: state.config[:hostname],
      port: state.config[:port]
    })

    {:ok, state}
  end

  @impl true
  def handle_disconnect(conn_status, state) do
    attempt = conn_status.attempt_number
    backoff_max = state.config[:backoff_max] || 10_000
    backoff_step = state.config[:backoff_step] || 50
    sleep = min(backoff_max, attempt * backoff_step)

    Telemetry.connection_event(:disconnect, %{reason: conn_status.reason})
    Logger.debug("[SurrealDB] Disconnected (attempt #{attempt}), reconnect in #{sleep}ms")

    Process.sleep(sleep)
    {:reconnect, State.set_auth_ready(state, false)}
  end

  @impl true
  def handle_cast({:register_live_query, sql, query_id, callback}, state) do
    {:ok, State.register_live_query(state, sql, query_id, callback)}
  end

  @impl true
  def handle_cast({method, args, id, task}, state) do
    {payload_id, payload} = Protocol.build_payload(method, args, id)
    {:reply, {:text, payload}, State.register_task(state, payload_id, task)}
  end

  @impl true
  def handle_frame({_type, msg}, state) do
    case Jason.decode(msg) do
      {:ok, json} ->
        id = Map.get(json, "id")

        case State.get_task(state, id) do
          nil ->
            # No matching task — might be a live query notification
            notify_if_live_query(state, json)

          task ->
            if Process.alive?(task.pid) do
              Process.send(task.pid, {:query_result, json, id}, [])
            end
        end

        {:ok, delete_if_task(state, id)}

      {:error, reason} ->
        Logger.warning("[SurrealDB] Invalid JSON: #{inspect(reason)}")
        {:ok, state}
    end
  end

  @impl true
  def terminate(reason, _state) do
    Logger.debug("[SurrealDB] Terminated: #{inspect(reason)}")
    :ok
  end

  # ----- Private helpers -----

  defp generic_start(opts, fun_name) do
    config = SurrealDB.Config.compile(opts)
    hostname = config[:hostname]
    port = config[:port]
    scheme = if config[:tls], do: "wss", else: "ws"
    url = "#{scheme}://#{hostname}:#{port}/rpc"

    state = State.new(config)
    Process.put(:surrealdb_config, config)
    ws_opts = if name = config[:name], do: [name: name], else: []
    apply(WebSockex, fun_name, [url, __MODULE__, state, ws_opts])
  end

  defp exec_method(pid, method, args, opts) do
    start_time = System.monotonic_time()
    Telemetry.query_start(method, args)

    id = Protocol.request_id()

    config =
      if pid == self(), do: Process.get(:surrealdb_config), else: :sys.get_state(pid).config

    timeout = Keyword.get(opts, :timeout, config[:query_timeout] || 5_000)

    task =
      Task.async(fn ->
        receive do
          {:query_result, json, ^id} ->
            cond do
              Map.has_key?(json, "error") ->
                {:error, json["error"]}

              method == "query" and is_list(json["result"]) ->
                errors =
                  Enum.filter(json["result"], &match?(%{"status" => "ERR"}, &1))

                if errors == [] do
                  {:ok, json}
                else
                  details =
                    Enum.map(errors, fn err ->
                      err["detail"] || err["message"] || err["info"] || inspect(err)
                    end)

                  {:error, {:sql_error, details}}
                end

              true ->
                {:ok, json}
            end

          {:query_error, reason, ^id} ->
            {:error, reason}
        after
          timeout -> {:error, :timeout}
        end
      end)

    WebSockex.cast(pid, {method, args, id, task})
    result = Task.await(task, timeout + 100)

    case result do
      {:ok, _} -> Telemetry.query_stop(method, args, start_time)
      {:error, _} -> Telemetry.query_exception(method, args, start_time, result)
    end

    result
  end

  defp delete_if_task(state, nil), do: state
  defp delete_if_task(state, id), do: State.delete_task(state, id)

  defp notify_if_live_query(state, json) do
    with %{"result" => %{"action" => action, "id" => lq_id}} <- json,
         %{callback: callback} <- State.get_live_query(state, lq_id) do
      Telemetry.live_query_notification(lq_id, action, json)
      callback.(json, lq_id)
    else
      _ -> :ok
    end
  end

  defp wait_loop(pid, deadline) do
    if System.monotonic_time() >= deadline, do: {:error, :timeout}

    case ping(pid) do
      {:ok, _} ->
        :ok

      _ ->
        Process.sleep(100)
        wait_loop(pid, deadline)
    end
  end
end
