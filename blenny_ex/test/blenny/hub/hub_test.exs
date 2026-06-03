defmodule Blenny.HubTest do
  use ExUnit.Case, async: false

  @hub_name :"test_hub_#{System.unique_integer([:positive])}"

  setup do
    start_supervised!({Blenny.Hub, [name: @hub_name]})
    %{hub: @hub_name}
  end

  test "register_connection stores a connection", %{hub: hub} do
    conn = Blenny.Connection.new("hub-1", :liveview, transport_pid: self())
    assert {:ok, _} = Blenny.Hub.register_connection(hub, conn)

    assert Blenny.Hub.connection_count(hub) == 1

    listed = Blenny.Hub.list_connections(hub)
    assert length(listed) == 1
    assert hd(listed).id == "hub-1"
  end

  test "register_connection dedup replaces existing connection", %{hub: hub} do
    test_pid = self()

    old_pid =
      spawn(fn ->
        receive do
          {:blenny_replaced, _new_pid} -> send(test_pid, :replaced)
        end
      end)

    old_conn =
      Blenny.Connection.new("dedup-1", :liveview, user_id: "same_user", transport_pid: old_pid)

    new_conn =
      Blenny.Connection.new("dedup-2", :liveview, user_id: "same_user", transport_pid: self())

    assert {:ok, _} = Blenny.Hub.register_connection(hub, old_conn)
    assert {:ok, _} = Blenny.Hub.register_connection(hub, new_conn)

    # Old connection should have been replaced (single entry for user+type)
    assert Blenny.Hub.connection_count(hub) == 1

    # Old process should have received :blenny_replaced
    assert_receive :replaced
  end

  test "unregister_connection removes and returns connection", %{hub: hub} do
    conn = Blenny.Connection.new("hub-2", :sse, transport_pid: self())
    {:ok, _} = Blenny.Hub.register_connection(hub, conn)

    returned = Blenny.Hub.unregister_connection(hub, "hub-2")
    assert returned.id == "hub-2"

    assert Blenny.Hub.connection_count(hub) == 0
  end

  test "lookup_connection returns registered connection", %{hub: hub} do
    conn = Blenny.Connection.new("hub-3", :liveview)
    {:ok, _} = Blenny.Hub.register_connection(hub, conn)

    found = Blenny.Hub.lookup_connection(hub, "hub-3")
    assert found.id == "hub-3"
  end

  test "lookup_connection returns nil for unknown", %{hub: hub} do
    assert Blenny.Hub.lookup_connection(hub, "nope") == nil
  end

  test "DOWN from transport process triggers cleanup", %{hub: hub} do
    pid = spawn(fn -> Process.sleep(:infinity) end)
    conn = Blenny.Connection.new("down-1", :sse, transport_pid: pid)
    {:ok, _} = Blenny.Hub.register_connection(hub, conn)

    assert Blenny.Hub.connection_count(hub) == 1

    Process.exit(pid, :kill)

    # Wait for DOWN message to be processed
    :timer.sleep(50)

    assert Blenny.Hub.connection_count(hub) == 0
    assert Blenny.Hub.lookup_connection(hub, "down-1") == nil
  end

  test "dedup_key uses user_id when present" do
    c1 = Blenny.Connection.new("k-1", :liveview, user_id: "user-1")
    c2 = Blenny.Connection.new("k-2", :liveview)

    assert Blenny.Hub.dedup_key(c1) == "user-1"
    assert Blenny.Hub.dedup_key(c2) == "k-2"
  end

  test "rejects when max_connections exceeded" do
    hub_name = :"max_conn_hub_#{System.unique_integer([:positive])}"
    {:ok, pid} = Blenny.Hub.start_link(name: hub_name, max_connections: 1, max_per_user: 5)
    on_exit(fn -> Process.exit(pid, :kill) end)

    c1 = Blenny.Connection.new("c1", :sse, transport_pid: self())
    assert {:ok, _} = Blenny.Hub.register_connection(hub_name, c1)

    c2 = Blenny.Connection.new("c2", :liveview, transport_pid: self())
    assert {:error, :too_many_connections} = Blenny.Hub.register_connection(hub_name, c2)
  end

  test "rejects when max_per_user exceeded" do
    hub_name = :"per_user_hub_#{System.unique_integer([:positive])}"
    {:ok, pid} = Blenny.Hub.start_link(name: hub_name, max_connections: 10, max_per_user: 1)
    on_exit(fn -> Process.exit(pid, :kill) end)

    c1 = Blenny.Connection.new("c1", :sse, user_id: "bob", transport_pid: self())
    assert {:ok, _} = Blenny.Hub.register_connection(hub_name, c1)

    c2 = Blenny.Connection.new("c2", :liveview, user_id: "bob", transport_pid: self())
    assert {:error, :too_many_per_user} = Blenny.Hub.register_connection(hub_name, c2)
  end

  # ── Telemetry ───────────────────────────────────────────────────

  def telemetry_handler(event_name, measurements, metadata, config) do
    send(config[:test_pid], {event_name, measurements, metadata})
  end

  defp attach_telemetry_handler do
    handler_id = "hub-test-#{System.unique_integer([:positive])}"

    events = [
      [:blenny, :hub, :connection, :register],
      [:blenny, :hub, :connection, :unregister],
      [:blenny, :hub, :connection, :rejected]
    ]

    config = %{test_pid: self()}

    for event <- events do
      :telemetry.attach("#{handler_id}-#{inspect(event)}", event, &telemetry_handler/4, config)
    end

    on_exit(fn ->
      for event <- events do
        :telemetry.detach("#{handler_id}-#{inspect(event)}")
      end
    end)
  end

  test "emits register telemetry on successful connection", %{hub: hub} do
    attach_telemetry_handler()

    conn = Blenny.Connection.new("t-reg-1", :liveview, user_id: "alice", transport_pid: self())
    {:ok, _} = Blenny.Hub.register_connection(hub, conn)

    assert_receive {[:blenny, :hub, :connection, :register], %{count: count}, %{user_id: "alice", conn_type: :liveview}}
    assert count >= 1
  end

  test "emits rejected telemetry on max_connections" do
    attach_telemetry_handler()

    lim_hub = :"telem_max_conn_#{System.unique_integer([:positive])}"
    {:ok, pid} = Blenny.Hub.start_link(name: lim_hub, max_connections: 1, max_per_user: 10)
    on_exit(fn -> Process.exit(pid, :kill) end)

    c1 = Blenny.Connection.new("t-rej-1", :sse, transport_pid: self())
    assert {:ok, _} = Blenny.Hub.register_connection(lim_hub, c1)

    c2 = Blenny.Connection.new("t-rej-2", :liveview, transport_pid: self())
    assert {:error, :too_many_connections} = Blenny.Hub.register_connection(lim_hub, c2)

    assert_receive {[:blenny, :hub, :connection, :rejected], %{count: _}, %{limit_type: :max_connections}}
  end

  test "emits rejected telemetry on max_per_user" do
    attach_telemetry_handler()

    lim_hub = :"telem_max_user_#{System.unique_integer([:positive])}"
    {:ok, pid} = Blenny.Hub.start_link(name: lim_hub, max_connections: 10, max_per_user: 1)
    on_exit(fn -> Process.exit(pid, :kill) end)

    c1 = Blenny.Connection.new("t-per-1", :sse, user_id: "charlie", transport_pid: self())
    assert {:ok, _} = Blenny.Hub.register_connection(lim_hub, c1)

    c2 = Blenny.Connection.new("t-per-2", :liveview, user_id: "charlie", transport_pid: self())
    assert {:error, :too_many_per_user} = Blenny.Hub.register_connection(lim_hub, c2)

    assert_receive {[:blenny, :hub, :connection, :rejected], %{count: _}, %{limit_type: :max_per_user}}
  end

  test "emits unregister telemetry on explicit unregister", %{hub: hub} do
    attach_telemetry_handler()

    conn = Blenny.Connection.new("t-unreg-1", :sse, user_id: "dave", transport_pid: self())
    {:ok, _} = Blenny.Hub.register_connection(hub, conn)
    Blenny.Hub.unregister_connection(hub, "t-unreg-1")

    assert_receive {[:blenny, :hub, :connection, :unregister], %{count: _}, %{user_id: "dave", conn_type: :sse, reason: :explicit}}
  end

  test "emits unregister telemetry on process DOWN", %{hub: hub} do
    attach_telemetry_handler()

    pid = spawn(fn -> Process.sleep(:infinity) end)
    conn = Blenny.Connection.new("t-down-1", :liveview, user_id: "eve", transport_pid: pid)
    {:ok, _} = Blenny.Hub.register_connection(hub, conn)

    Process.exit(pid, :kill)
    :timer.sleep(50)

    assert_receive {[:blenny, :hub, :connection, :unregister], %{count: _}, %{user_id: "eve", conn_type: :liveview, reason: :process_down}}
  end
end
