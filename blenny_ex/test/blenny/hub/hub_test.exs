defmodule Blenny.HubTest do
  use ExUnit.Case, async: false

  @hub_name :"test_hub_#{System.unique_integer([:positive])}"

  setup do
    start_supervised!({Blenny.Hub, [name: @hub_name]})
    %{hub: @hub_name}
  end

  test "register_connection stores a connection", %{hub: hub} do
    conn = Blenny.Connection.new("hub-1", :liveview, transport_pid: self())
    assert :ok = Blenny.Hub.register_connection(hub, conn)

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

    assert :ok = Blenny.Hub.register_connection(hub, old_conn)
    assert :ok = Blenny.Hub.register_connection(hub, new_conn)

    # Old connection should have been replaced (single entry for user+type)
    assert Blenny.Hub.connection_count(hub) == 1

    # Old process should have received :blenny_replaced
    assert_receive :replaced
  end

  test "unregister_connection removes and returns connection", %{hub: hub} do
    conn = Blenny.Connection.new("hub-2", :sse, transport_pid: self())
    :ok = Blenny.Hub.register_connection(hub, conn)

    returned = Blenny.Hub.unregister_connection(hub, "hub-2")
    assert returned.id == "hub-2"

    assert Blenny.Hub.connection_count(hub) == 0
  end

  test "lookup_connection returns registered connection", %{hub: hub} do
    conn = Blenny.Connection.new("hub-3", :liveview)
    :ok = Blenny.Hub.register_connection(hub, conn)

    found = Blenny.Hub.lookup_connection(hub, "hub-3")
    assert found.id == "hub-3"
  end

  test "lookup_connection returns nil for unknown", %{hub: hub} do
    assert Blenny.Hub.lookup_connection(hub, "nope") == nil
  end

  test "DOWN from transport process triggers cleanup", %{hub: hub} do
    pid = spawn(fn -> Process.sleep(:infinity) end)
    conn = Blenny.Connection.new("down-1", :sse, transport_pid: pid)
    :ok = Blenny.Hub.register_connection(hub, conn)

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
end
