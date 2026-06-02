defmodule Blenny.Transport.SSEPlug do
  @moduledoc """
  A Plug that opens a long-lived SSE connection using the Datastar wire format
  (via the `dstar` package).

  Clients connect to `/sse?intent=ui,data&session_id=xxx` and receive
  Datastar-formatted SSE events (`datastar-patch-elements`,
  `datastar-patch-signals`, `datastar-execute-script`).

  Wire formatting is handled by `Dstar` — signals via `Dstar.patch_signals/2`,
  element patches via `Dstar.patch_elements/3` (with selector extracted from
  the HTML `id` attribute), and script execution via `Dstar.execute_script/2`.
  Connection health is checked with `Dstar.check_connection/1` before each
  write.

  ## Registration

  Each SSE connection registers with `Blenny.Hub` using `:sse` as the
  `conn_type`. Session-level dedup is enforced — if a session already has
  a LiveView or SSE connection, the old one is replaced.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    _intents = Blenny.Intent.parse_list(conn.params["intent"])
    session_id = conn.params["session_id"] || default_session_id(conn)

    conn =
      conn
      |> put_resp_header("content-type", "text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("x-accel-buffering", "no")
      |> send_chunked(200)

    conn_id = id()
    user_id = conn.params["user_id"]

    conn_struct =
      Blenny.Connection.new(conn_id, session_id, :sse,
        transport_pid: self(),
        user_id: user_id
      )

    Process.flag(:trap_exit, true)
    {:ok, _} = Blenny.Hub.register_connection(conn_struct)

    sse_loop(conn, conn_id)
  end

  defp sse_loop(conn, conn_id) do
    receive do
      {:blenny_message, ^conn_id, msg} ->
        case write_events(conn, msg) do
          {:ok, conn} -> sse_loop(conn, conn_id)
          {:error, _conn} -> cleanup(conn, conn_id)
        end

      {:blenny_replaced, _new_id} ->
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

  defp write_events(conn, msg) do
    with {:ok, conn} <- Dstar.check_connection(conn),
         {:ok, conn} <- safe_patch_elements(conn, msg[:html]),
         {:ok, conn} <- safe_patch_signals(conn, msg[:signals]) do
      safe_execute_script(conn, msg[:script])
    end
  end

  defp safe_patch_elements(conn, nil), do: {:ok, conn}
  defp safe_patch_elements(conn, html) when is_binary(html) do
    case extract_selector(html) do
      nil -> {:ok, conn}
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

  defp extract_selector(html) do
    case Regex.run(~r/\sid=['"]([^'"]+)['"]/, html) do
      [_, id] -> "##{id}"
      nil -> nil
    end
  end

  defp id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp default_session_id(conn) do
    case conn.private do
      %{plug_session: %{"_csrf_token" => _} = session} ->
        session["_blenny_session_id"] || id()

      _ ->
        id()
    end
  end
end
