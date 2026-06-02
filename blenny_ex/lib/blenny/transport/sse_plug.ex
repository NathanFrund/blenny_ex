defmodule Blenny.Transport.SSEPlug do
  @moduledoc """
  A Plug that opens a long-lived SSE connection using the Datastar wire format.

  Clients connect to `/sse?intent=ui,data&session_id=xxx` and receive
  Datastar-formatted SSE events (`datastar-patch-elements`,
  `datastar-patch-signals`, `datastar-execute-script`).

  ## Wire Format

  Messages from the Hub are formatted as Datastar SSE events.
  Each `data` line uses Datastar's `key value` pair format:

      event: datastar-patch-elements
      data: elements <div id="status">Updated</div>

      event: datastar-patch-signals
      data: signals {"cpu":45,"mem":62}

      event: datastar-execute-script
      data: script console.log("hi")

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
          {:error, _reason} -> cleanup(conn, conn_id)
        end

      {:blenny_replaced, _new_id} ->
        write_event(conn, "datastar-execute-script", ~s|script console.log("Session replaced")|)
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
    with {:ok, conn} <- maybe_write_event(conn, msg[:html], "datastar-patch-elements"),
         {:ok, conn} <- maybe_write_event(conn, msg[:signals], "datastar-patch-signals") do
      maybe_write_script(conn, msg[:script])
    end
  end

  defp maybe_write_event(conn, nil, _event), do: {:ok, conn}

  defp maybe_write_event(conn, html, "datastar-patch-elements") when is_binary(html) do
    write_event(conn, "datastar-patch-elements", "elements #{html}")
  end

  defp maybe_write_event(conn, signals, "datastar-patch-signals") when is_map(signals) do
    write_event(conn, "datastar-patch-signals", "signals #{Jason.encode!(signals)}")
  end

  defp maybe_write_event(conn, _value, _event), do: {:ok, conn}

  defp maybe_write_script(conn, nil), do: {:ok, conn}
  defp maybe_write_script(conn, script) when is_binary(script) do
    write_event(conn, "datastar-execute-script", script)
  end
  defp maybe_write_script(conn, _), do: {:ok, conn}

  defp write_event(conn, event, data) do
    chunk(conn, "event: #{event}\ndata: #{data}\n\n")
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
