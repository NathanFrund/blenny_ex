defmodule Blenny.Connection.RegistryTest do
  use ExUnit.Case, async: false

  setup do
    Blenny.Connection.Registry.start_link()
    on_exit(fn -> Blenny.Connection.Registry.clear() end)
    :ok
  end

  test "register and lookup a connection" do
    conn = Blenny.Connection.new("reg-1", :liveview)
    assert {:ok, ^conn} = Blenny.Connection.Registry.register(conn)

    assert Blenny.Connection.Registry.lookup("reg-1") == conn
  end

  test "lookup returns nil for unknown id" do
    assert Blenny.Connection.Registry.lookup("nonexistent") == nil
  end

  test "unregister removes a connection" do
    conn = Blenny.Connection.new("reg-2", :sse)
    Blenny.Connection.Registry.register(conn)

    assert Blenny.Connection.Registry.unregister("reg-2") == conn
    assert Blenny.Connection.Registry.lookup("reg-2") == nil
  end

  test "unregister returns nil for unknown id" do
    assert Blenny.Connection.Registry.unregister("nonexistent") == nil
  end

  test "all returns all registered connections" do
    c1 = Blenny.Connection.new("all-1", :liveview)
    c2 = Blenny.Connection.new("all-2", :sse)
    Blenny.Connection.Registry.register(c1)
    Blenny.Connection.Registry.register(c2)

    result = Blenny.Connection.Registry.all()
    assert length(result) == 2
    assert c1 in result
    assert c2 in result
  end

  test "count returns the number of connections" do
    Blenny.Connection.Registry.register(Blenny.Connection.new("cnt-1", :liveview))
    assert Blenny.Connection.Registry.count() == 1

    Blenny.Connection.Registry.register(Blenny.Connection.new("cnt-2", :sse))
    assert Blenny.Connection.Registry.count() == 2
  end

  test "clear removes all connections" do
    Blenny.Connection.Registry.register(Blenny.Connection.new("clr-1", :liveview))
    assert Blenny.Connection.Registry.count() == 1

    Blenny.Connection.Registry.clear()
    assert Blenny.Connection.Registry.count() == 0
  end

  test "user index allows per-user lookups" do
    c1 = Blenny.Connection.new("u-1", :liveview, user_id: "alice")
    c2 = Blenny.Connection.new("u-2", :sse, user_id: "alice")
    c3 = Blenny.Connection.new("u-3", :liveview, user_id: "bob")
    Blenny.Connection.Registry.register(c1)
    Blenny.Connection.Registry.register(c2)
    Blenny.Connection.Registry.register(c3)

    alice_con = Blenny.Connection.Registry.lookup_by_user("alice")
    assert length(alice_con) == 2
    assert c1 in alice_con
    assert c2 in alice_con

    bob_con = Blenny.Connection.Registry.lookup_by_user("bob")
    assert length(bob_con) == 1
    assert hd(bob_con).id == "u-3"
  end

  test "user index returns empty for unknown user" do
    assert Blenny.Connection.Registry.lookup_by_user("nobody") == []
  end

  test "dedup key lookup finds existing connection" do
    c1 = Blenny.Connection.new("d-1", :liveview, user_id: "dedup_user")
    Blenny.Connection.Registry.register(c1)

    found = Blenny.Connection.Registry.lookup_by_dedup_key("dedup_user", :liveview)
    assert found != nil
    assert found.id == "d-1"
  end

  test "dedup key lookup returns nil for different conn type" do
    c1 = Blenny.Connection.new("d-2", :liveview, user_id: "dedup_user2")
    Blenny.Connection.Registry.register(c1)

    assert Blenny.Connection.Registry.lookup_by_dedup_key("dedup_user2", :sse) == nil
  end

  test "dedup key uses conn id when no user_id" do
    c1 = Blenny.Connection.new("anon-dedup", :liveview)
    Blenny.Connection.Registry.register(c1)

    found = Blenny.Connection.Registry.lookup_by_dedup_key("anon-dedup", :liveview)
    assert found != nil
    assert found.id == "anon-dedup"
  end

  test "unregister removes dedup and user index entries" do
    c1 = Blenny.Connection.new("clean-1", :liveview, user_id: "clean_user")
    Blenny.Connection.Registry.register(c1)
    Blenny.Connection.Registry.unregister("clean-1")

    assert Blenny.Connection.Registry.lookup("clean-1") == nil
    assert Blenny.Connection.Registry.lookup_by_user("clean_user") == []
    assert Blenny.Connection.Registry.lookup_by_dedup_key("clean_user", :liveview) == nil
  end
end
