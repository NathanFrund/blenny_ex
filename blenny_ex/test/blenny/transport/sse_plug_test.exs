defmodule Blenny.Transport.SSEPlugTest do
  use ExUnit.Case, async: false

  import Blenny.Test.SSEHelpers

  # ── Helpers ───────────────────────────────────────────────────────

  defp chunked_conn do
    Plug.Test.conn(:get, "/sse?intent=all")
    |> Plug.Conn.fetch_query_params()
    |> Dstar.SSE.start()
  end

  defp conn_chunks(conn) do
    {_, state} = conn.adapter
    state.chunks
  end

  # ================================================================
  # extract_selector/1
  # ================================================================

  describe "extract_selector/1" do
    test "returns nil for HTML without id" do
      assert Blenny.Transport.SSEPlug.extract_selector("<div>no id</div>") == nil
    end

    test "extracts id with double-quoted attribute" do
      html = ~s'<div id="counter" class="x">42</div>'
      assert Blenny.Transport.SSEPlug.extract_selector(html) == "#counter"
    end

    test "extracts id with single-quoted attribute" do
      html = ~s'<div id=\'status\'>ok</div>'
      assert Blenny.Transport.SSEPlug.extract_selector(html) == "#status"
    end

    test "extracts the first id when multiple elements present" do
      html = ~s'<div id="first">a</div><div id="second">b</div>'
      assert Blenny.Transport.SSEPlug.extract_selector(html) == "#first"
    end

    test "returns nil for empty string" do
      assert Blenny.Transport.SSEPlug.extract_selector("") == nil
    end
  end

  # ================================================================
  # Datastar wire format (pure string assertions)
  # ================================================================

  describe "Datastar wire format" do
    test "signals patch frame format" do
      frame = Dstar.Signals.format_patch(%{"cpu" => 42, "mem" => 65.3})

      assert frame =~ "event: datastar-patch-signals"
      assert frame =~ ~r/data: signals.*"cpu": ?42/
      assert frame =~ ~r/data: signals.*"mem": ?65\.3/
      assert String.ends_with?(String.trim(frame), "\n\n") or String.ends_with?(frame, "\n\n")
    end

    test "elements patch frame with id-based selector omits selector line" do
      html = ~s'<div id="status">Updated</div>'
      frame = Dstar.Elements.format_patch(html)

      assert frame =~ "event: datastar-patch-elements"
      refute frame =~ "data: selector"
      assert frame =~ ~r/data: elements.*Updated/
    end

    test "elements patch frame with explicit selector" do
      html = ~s'<span>inner</span>'
      frame = Dstar.Elements.format_patch(html, selector: "#target")

      assert frame =~ "event: datastar-patch-elements"
      assert frame =~ "data: selector #target"
      assert frame =~ "data: elements <span>inner</span>"
    end

    test "script execution via chunked conn produces elements event" do
      conn = chunked_conn()
      conn = Dstar.Scripts.execute(conn, "alert('hi')", auto_remove: false)
      chunks = conn_chunks(conn)
      assert chunks =~ "event: datastar-patch-elements"
      assert chunks =~ "data: selector body"
      assert chunks =~ "data: mode append"
      assert chunks =~ ~r/data: elements.*alert/
    end

    test "execute_script format via elements" do
      html = ~s'<script data-effect="el.remove()">console.log("test")</script>'
      frame = Dstar.Elements.format_patch(html, selector: "body", mode: :append)

      assert frame =~ "event: datastar-patch-elements"
      assert frame =~ "data: selector body"
      assert frame =~ "data: mode append"
      assert frame =~ "data: elements <script"
    end

    test "multiple data lines in single event" do
      html = ~s'<div id="x">line1</div>'
      frame = Dstar.Elements.format_patch(html, selector: "#x")

      assert frame =~ "data: selector #x"
      # elements with multiline HTML
    end

    test "check_connection sends heartbeat comment" do
      conn = chunked_conn()
      {:ok, conn} = Dstar.check_connection(conn)
      chunks = conn_chunks(conn)
      assert String.starts_with?(chunks, ": ")
    end
  end

  # ================================================================
  # Chunked conn wire format (using Plug.Test adapter)
  # ================================================================

  describe "chunked SSE output via Plug.Test" do
    test "signals patch produces chunked data" do
      conn = chunked_conn()
      conn = Dstar.patch_signals(conn, %{"cpu" => 42})
      chunks = conn_chunks(conn)
      assert chunks =~ "event: datastar-patch-signals"
      assert chunks =~ ~r/data: signals.*"cpu": ?42/
    end

    test "elements patch produces chunked data" do
      conn = chunked_conn()
      html = ~s'<div id="status">ok</div>'
      conn = Dstar.patch_elements(conn, html, selector: "#status")
      chunks = conn_chunks(conn)
      assert chunks =~ "event: datastar-patch-elements"
      assert chunks =~ "data: selector #status"
      assert chunks =~ "data: elements <div id=\"status\">ok</div>"
    end

    test "execute_script produces chunked data" do
      conn = chunked_conn()
      conn = Dstar.execute_script(conn, "console.log('test')")
      chunks = conn_chunks(conn)
      assert chunks =~ "event: datastar-patch-elements"
      assert chunks =~ "data: selector body"
      assert chunks =~ "data: mode append"
      assert chunks =~ ~r/data: elements.*console\.log/
    end

    test "check_connection produces comment chunk" do
      conn = chunked_conn()
      {:ok, conn} = Dstar.check_connection(conn)
      chunks = conn_chunks(conn)
      assert chunks =~ ": "
    end

    test "multiple operations accumulate in order" do
      conn = chunked_conn()

      {:ok, conn} = Dstar.check_connection(conn)
      conn = Dstar.patch_signals(conn, %{"cpu" => 42})
      conn = Dstar.patch_elements(conn, ~s'<div id="s">ok</div>', selector: "#s")
      conn = Dstar.execute_script(conn, "console.log('end')")

      chunks = conn_chunks(conn)

      # Find positions of each event in the chunk stream
      heart_pos = pos_in(chunks, ": ")
      signals_pos = pos_in(chunks, "datastar-patch-signals")
      elements_pos = pos_in(chunks, "datastar-patch-elements")
      script_pos = pos_in(chunks, "console.log('end')")

      assert heart_pos == 0
      assert signals_pos < elements_pos
      assert elements_pos < script_pos
    end
  end

  # ================================================================
  # Chronological accuracy (frame ordering)
  # ================================================================

  describe "chronological frame ordering" do
    test "sequential writes maintain order in chunk stream" do
      conn = chunked_conn()

      markers = ["marker_a", "marker_b", "marker_c"]

      conn =
        Enum.reduce(markers, conn, fn marker, c ->
          Dstar.patch_signals(c, %{"marker" => marker})
        end)

      chunks = conn_chunks(conn)

      pos1 = pos_in(chunks, "marker_a")
      pos2 = pos_in(chunks, "marker_b")
      pos3 = pos_in(chunks, "marker_c")

      assert pos1 != :infinity, "marker_a not found in chunks"
      assert pos2 != :infinity, "marker_b not found in chunks"
      assert pos3 != :infinity, "marker_c not found in chunks"
      assert pos1 < pos2, "first event comes before second"
      assert pos2 < pos3, "second event comes before third"
    end

    test "mixed signal types maintain insertion order" do
      conn = chunked_conn()

      conn = Dstar.patch_signals(conn, %{"step" => "signals_first"})
      conn = Dstar.patch_elements(conn, ~s'<div id="a">elements_second</div>', selector: "#a")
      conn = Dstar.patch_signals(conn, %{"step" => "signals_third"})

      chunks = conn_chunks(conn)

      pos_sig1 = pos_in(chunks, "signals_first")
      pos_elem = pos_in(chunks, "elements_second")
      pos_sig2 = pos_in(chunks, "signals_third")

      assert pos_sig1 != :infinity
      assert pos_elem != :infinity
      assert pos_sig2 != :infinity
      assert pos_sig1 < pos_elem, "first signals before elements"
      assert pos_elem < pos_sig2, "elements before second signals"
    end

    test "signals with timestamps appear in send order" do
      conn = chunked_conn()

      conn = Dstar.patch_signals(conn, %{"seq" => "first"})
      conn = Dstar.patch_signals(conn, %{"seq" => "second"})
      conn = Dstar.patch_signals(conn, %{"seq" => "third"})

      chunks = conn_chunks(conn)

      pos1 = pos_in(chunks, "first")
      pos2 = pos_in(chunks, "second")
      pos3 = pos_in(chunks, "third")

      assert pos1 != :infinity
      assert pos2 != :infinity
      assert pos3 != :infinity
      assert pos1 < pos2, "first before second"
      assert pos2 < pos3, "second before third"
    end
  end

  # ================================================================
  # Integration with Bandit (full end-to-end)
  # ================================================================

  describe "streaming under Bandit" do
    @pubsub :sse_test_pubsub_bandit
    @moduletag :bandit

    setup do
      start_supervised!({Phoenix.PubSub.Supervisor, name: @pubsub})
      Application.put_env(:blenny_ex, :pub_sub, @pubsub)

      start_supervised!({Blenny.Hub, [name: Blenny.Hub]})

      bandit_pid =
        start_supervised!(
          {Bandit,
           [
             plug: Blenny.Test.SSEEndpoint,
             port: 0,
             thousand_island_options: [shutdown_timeout: 100]
           ]}
        )

      {:ok, info} = ThousandIsland.listener_info(bandit_pid)
      {_ip, port} = info

      {:ok, port: port, pubsub: @pubsub}
    end

    test "responds with 200 and SSE headers", %{port: port} do
      {_socket, headers} = connect_and_request(port)

      assert headers =~ "200"
      assert headers =~ "text/event-stream"
      assert headers =~ "no-cache"
      assert headers =~ "x-accel-buffering"
    end

    test "receives signals event from PubSub broadcast", %{port: port, pubsub: pubsub} do
      {socket, _headers} = connect_and_request(port)

      :timer.sleep(100)

      raw = publish_and_read(pubsub, :ui, %{signals: %{"cpu" => 42}}, socket)
      events = extract_events(raw)

      assert length(events) >= 1

      sig_event = Enum.find(events, fn ev -> String.contains?(ev, "datastar-patch-signals") end)
      assert sig_event, "expected a signals event, got: #{inspect(events)}"
      assert sig_event =~ ~r/signals.*"cpu": ?42/
    end

    test "receives elements event from PubSub broadcast", %{port: port, pubsub: pubsub} do
      {socket, _headers} = connect_and_request(port)

      :timer.sleep(100)

      raw =
        publish_and_read(
          pubsub,
          :ui,
          %{html: ~s'<div id="status">Updated</div>'},
          socket
        )

      events = extract_events(raw)

      elem_event =
        Enum.find(events, fn ev -> String.contains?(ev, "datastar-patch-elements") end)

      assert elem_event, "expected an elements event, got: #{inspect(events)}"
      assert elem_event =~ "selector #status"
      assert elem_event =~ "elements <div id=\"status\">Updated</div>"
    end

    test "receives execute_script from PubSub broadcast", %{port: port, pubsub: pubsub} do
      {socket, _headers} = connect_and_request(port)

      :timer.sleep(100)

      raw =
        publish_and_read(
          pubsub,
          :ui,
          %{script: "console.log('bandit-integration')"},
          socket
        )

      events = extract_events(raw)

      script_event =
        Enum.find(events, fn ev ->
          String.contains?(ev, "datastar-patch-elements") and
            String.contains?(ev, "console.log('bandit-integration')") and
            String.contains?(ev, "selector body")
        end)

      assert script_event,
             "expected a script-like elements event, got: #{inspect(events)}"
    end

    test "frames arrive in chronological order under Bandit", %{port: port, pubsub: pubsub} do
      {socket, _headers} = connect_and_request(port)

      :timer.sleep(100)

      events_data = [
        %{signals: %{"seq" => 10, "msg" => "alpha"}},
        %{signals: %{"seq" => 20, "msg" => "beta"}},
        %{signals: %{"seq" => 30, "msg" => "gamma"}}
      ]

      raw =
        Enum.reduce(events_data, "", fn payload, acc ->
          more =
            publish_and_read(
              pubsub,
              :ui,
              payload,
              socket,
              300
            )

          acc <> more
        end)

      all_events = extract_events(raw)

      sig_events =
        Enum.filter(all_events, fn ev -> String.contains?(ev, "datastar-patch-signals") end)

      assert length(sig_events) >= 3,
             "expected at least 3 signals events, got #{length(sig_events)}"

      # Verify events appear in the order they were published by content
      first_pos = Enum.find_index(sig_events, &String.contains?(&1, ~s/"msg":"alpha"/))
      second_pos = Enum.find_index(sig_events, &String.contains?(&1, ~s/"msg":"beta"/))
      third_pos = Enum.find_index(sig_events, &String.contains?(&1, ~s/"msg":"gamma"/))

      refute is_nil(first_pos), "alpha event not found"
      refute is_nil(second_pos), "beta event not found"
      refute is_nil(third_pos), "gamma event not found"

      assert first_pos < second_pos, "alpha before beta"
      assert second_pos < third_pos, "beta before gamma"
    end

    test "combined payload (html + signals + script) produces multiple events", %{
      port: port,
      pubsub: pubsub
    } do
      {socket, _headers} = connect_and_request(port)

      :timer.sleep(100)

      raw =
        publish_and_read(
          pubsub,
          :ui,
          %{
            html: ~s'<div id="main">Hello</div>',
            signals: %{"greeting" => "hello"},
            script: "console.log('combined')"
          },
          socket
        )

      events = extract_events(raw)

      signals_events = Enum.filter(events, &String.contains?(&1, "datastar-patch-signals"))
      elements_events = Enum.filter(events, &String.contains?(&1, "datastar-patch-elements"))

      assert length(signals_events) >= 1,
             "expected at least 1 signals event from combined payload"

      assert length(elements_events) >= 1,
             "expected at least 1 elements event from combined payload"
    end

    test "intent filtering prevents delivery of non-matching intents", %{
      port: port,
      pubsub: pubsub
    } do
      {socket, _headers} = connect_and_request(port, "/sse?intent=ui")

      :timer.sleep(100)

      # Read any initial data
      _initial = read_raw(socket, 300)

      # Publish to a non-ui intent that this connection doesn't subscribe to
      raw = publish_and_read(pubsub, :command, %{signals: %{"cmd" => "ignored"}}, socket)

      events = extract_events(raw)

      cmd_events =
        Enum.filter(events, &String.contains?(&1, ~s("cmd":"ignored")))

      if length(cmd_events) > 0 do
        # The raw data might still contain leftovers from initial read;
        # we check explicitly that command wasn't delivered
        flunk("command intent was delivered despite filtering for ui intent only")
      end

      # Now publish to the matching intent
      raw2 = publish_and_read(pubsub, :ui, %{signals: %{"ui" => "delivered"}}, socket)

      all_data = raw2
      events2 = extract_events(all_data)

      assert Enum.any?(events2, &String.contains?(&1, ~s("ui":"delivered"))),
             "UI intent should be delivered"
    end
  end

  # ── Private helpers ───────────────────────────────────────────────

  defp pos_in(chunks, substring) do
    case :binary.match(chunks, substring) do
      {pos, _} -> pos
      :nomatch -> :infinity
    end
  end
end
