defmodule Blenny.Plug.RequestLogger do
  @moduledoc """
  Logs HTTP request completion with method, path, status, and duration.

  Place in a Phoenix pipeline after `fetch_session` and `Blenny.Plug.FetchSession`:

      pipeline :browser do
        plug :accepts, ["html"]
        plug :fetch_session
        plug Blenny.Plug.FetchSession
        plug Blenny.Plug.RequestLogger
        plug :fetch_live_flash
        plug :put_root_layout, html: {MyAppWeb.Layouts, :root}
        plug :protect_from_forgery
        plug :put_secure_browser_headers
      end

  ## Options

    * `:log_level` — the log level to use (default: `:info`). Set to `false` to disable.
    * `:exclude_paths` — list of path prefixes to exclude from logging (default: `[]`).

  Logged metadata: `method`, `path`, `status`, `duration_ms`, `request_id` (if present).
  """

  import Plug.Conn
  require Logger

  def init(opts) do
    %{
      log_level: Keyword.get(opts, :log_level, :info),
      exclude_paths: Keyword.get(opts, :exclude_paths, [])
    }
  end

  def call(conn, %{log_level: false}) do
    conn
  end

  def call(conn, %{log_level: log_level, exclude_paths: exclusions}) do
    start = System.monotonic_time()

    excluded? = Enum.any?(exclusions, &String.starts_with?(conn.request_path, &1))

    if excluded? do
      conn
    else
      register_before_send(conn, fn conn ->
        duration =
          System.monotonic_time()
          |> Kernel.-(start)
          |> System.convert_time_unit(:native, :millisecond)

        metadata = [
          method: conn.method,
          path: conn.request_path,
          status: conn.status,
          duration_ms: duration
        ]

        metadata =
          if conn.private[:plug_request_id] do
            Keyword.put(metadata, :request_id, conn.private[:plug_request_id])
          else
            metadata
          end

        Logger.log(
          log_level,
          fn -> "#{conn.method} #{conn.request_path} -> #{conn.status} (#{duration}ms)" end,
          metadata
        )

        conn
      end)
    end
  end
end
