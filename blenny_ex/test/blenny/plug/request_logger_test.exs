defmodule Blenny.Plug.RequestLoggerTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn
  import ExUnit.CaptureLog

  defp default_opts, do: Blenny.Plug.RequestLogger.init([])

  test "logs method, path, status, and duration on response" do
    log =
      capture_log(fn ->
        conn(:get, "/dashboard")
        |> put_private(:plug_request_id, "req-1")
        |> Blenny.Plug.RequestLogger.call(default_opts())
        |> send_resp(200, "ok")
      end)

    assert log =~ "GET /dashboard -> 200"
    assert log =~ "ms)"
  end

  test "includes request_id in metadata" do
    log =
      capture_log(
        [metadata: [:request_id]],
        fn ->
          conn(:post, "/api/data")
          |> put_private(:plug_request_id, "req-abc")
          |> Blenny.Plug.RequestLogger.call(default_opts())
          |> send_resp(201, "created")
        end
      )

    assert log =~ "request_id=req-abc"
  end

  test "skips request_id when not present" do
    log =
      capture_log(
        [metadata: [:request_id]],
        fn ->
          conn(:get, "/")
          |> Blenny.Plug.RequestLogger.call(default_opts())
          |> send_resp(200, "ok")
        end
      )

    refute log =~ "request_id="
  end

  test "uses custom log level" do
    opts = Blenny.Plug.RequestLogger.init(log_level: :warning)

    log =
      capture_log(fn ->
        conn(:get, "/admin")
        |> Blenny.Plug.RequestLogger.call(opts)
        |> send_resp(200, "ok")
      end)

    assert log =~ "[warning]"
  end

  test "does not log when log_level is false" do
    opts = Blenny.Plug.RequestLogger.init(log_level: false)

    log =
      capture_log(fn ->
        conn(:get, "/health")
        |> Blenny.Plug.RequestLogger.call(opts)
        |> send_resp(200, "ok")
      end)

    refute log =~ "GET /health"
  end

  test "does not log excluded paths" do
    opts = Blenny.Plug.RequestLogger.init(exclude_paths: ["/health"])

    log =
      capture_log(fn ->
        conn(:get, "/health/ping")
        |> Blenny.Plug.RequestLogger.call(opts)
        |> send_resp(200, "ok")
      end)

    refute log =~ "GET /health/ping"
  end

  test "logs non-excluded paths" do
    opts = Blenny.Plug.RequestLogger.init(exclude_paths: ["/health"])

    log =
      capture_log(fn ->
        conn(:get, "/dashboard")
        |> Blenny.Plug.RequestLogger.call(opts)
        |> send_resp(200, "ok")
      end)

    assert log =~ "GET /dashboard -> 200"
  end
end
