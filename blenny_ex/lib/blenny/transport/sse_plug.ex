defmodule Blenny.Transport.SSEPlug do
  @moduledoc """
  A Plug that opens a long-lived SSE connection using the Datastar wire format
  (via the `dstar` package).

  Clients connect to `/sse?intent=ui,command&user_id=xxx` and receive
  Datastar-formatted SSE events (`datastar-patch-elements`,
  `datastar-patch-signals`, `datastar-execute-script`).

  In the PubSub-direct architecture, the SSE process subscribes directly
  to `Phoenix.PubSub` topics (`blenny:intent:*`, `blenny:user:*`) and
  routes messages to the client based on declared intents.
  """

  import Plug.Conn

  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    intents = Blenny.Intent.parse_list(conn.params["intent"])

    conn =
      conn
      |> put_resp_header("content-type", "text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("x-accel-buffering", "no")
      |> send_chunked(200)

    conn_id = id()
    user_id = conn.params["user_id"]

    conn_struct =
      Blenny.Connection.new(conn_id, :sse,
        transport_pid: self(),
        user_id: user_id,
        intents: intents
      )

    Process.flag(:trap_exit, true)

    transport_config = Blenny.Config.get_all(:transport)
    rate_config = transport_config[:rate_limit] || []
    max_messages = rate_config[:max_messages]
    window_ms = rate_config[:window_ms] || 1000

    case Blenny.Hub.register_connection(conn_struct) do
      {:ok, _conn} ->
        pubsub = Blenny.pub_sub()

        for intent <- Blenny.Intent.routing() do
          Phoenix.PubSub.subscribe(pubsub, Blenny.Intent.to_topic(intent), link: true)
        end

        user_topic = Blenny.Intent.user_topic(user_id || conn_id)
        Phoenix.PubSub.subscribe(pubsub, user_topic, link: true)

        sse_loop(conn, conn_id, intents, max_messages, window_ms)

      {:error, _reason} ->
        conn
        |> put_resp_header("retry-after", "10")
        |> send_resp(429, "Too Many Requests")
    end
  end

  defp sse_loop(conn, conn_id, intents, max_messages, window_ms) do
    receive do
      {:blenny_msg, intent, payload} ->
        if Blenny.Intent.accepts?(intents, intent) do
          if max_messages && Blenny.RateLimiter.check(:msg_rate, max_messages, window_ms) != :ok do
            :telemetry.execute(
              [:blenny, :transport, :sse, :rate_limited],
              %{},
              %{conn_id: conn_id}
            )

            sse_loop(conn, conn_id, intents, max_messages, window_ms)
          else
            case write_events(conn, payload) do
              {:ok, conn} -> sse_loop(conn, conn_id, intents, max_messages, window_ms)
              {:error, _conn} -> cleanup(conn, conn_id)
            end
          end
        else
          sse_loop(conn, conn_id, intents, max_messages, window_ms)
        end

      {:blenny_drain, _deadline} ->
        safe_execute_script(
          conn,
          ~s|setTimeout(() => location.reload(), Math.floor(Math.random() * 5000) + 1000)|
        )

        cleanup(conn, conn_id)

      {:blenny_replaced, _new_pid} ->
        safe_execute_script(conn, ~s|console.log("Session replaced")|)
        cleanup(conn, conn_id)

      {:EXIT, _from, _reason} ->
        cleanup(conn, conn_id)
    end
  end

  defp cleanup(conn, conn_id) do
    Blenny.Hub.unregister_connection(conn_id)
    conn
  end

  defp write_events(conn, payload) do
    with {:ok, conn} <- Dstar.check_connection(conn),
         {:ok, conn} <- safe_patch_elements(conn, payload[:html]),
         {:ok, conn} <- safe_patch_signals(conn, payload[:signals]) do
      safe_execute_script(conn, payload[:script])
    end
  end

  defp safe_patch_elements(conn, nil), do: {:ok, conn}

  defp safe_patch_elements(conn, html) when is_binary(html) do
    case extract_selector(html) do
      nil ->
        {:ok, conn}

      selector ->
        try do
          {:ok, Dstar.patch_elements(conn, html, selector: selector)}
        rescue
          _ -> {:error, conn}
        end
    end
  end

  defp safe_patch_elements(conn, _), do: {:ok, conn}

  defp safe_patch_signals(conn, nil), do: {:ok, conn}

  defp safe_patch_signals(conn, signals) when is_map(signals) do
    try do
      {:ok, Dstar.patch_signals(conn, signals)}
    rescue
      _ -> {:error, conn}
    end
  end

  defp safe_patch_signals(conn, _), do: {:ok, conn}

  defp safe_execute_script(conn, nil), do: {:ok, conn}

  defp safe_execute_script(conn, script) when is_binary(script) do
    try do
      {:ok, Dstar.execute_script(conn, script)}
    rescue
      _ -> {:error, conn}
    end
  end

  defp safe_execute_script(conn, _), do: {:ok, conn}

  @doc false
  def extract_selector(html) do
    case Regex.run(~r/\sid=['"]([^'"]+)['"]/, html) do
      [_, id] -> "##{id}"
      nil -> nil
    end
  end

  defp id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
