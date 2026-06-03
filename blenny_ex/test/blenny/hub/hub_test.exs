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
end
