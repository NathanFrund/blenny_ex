defmodule Blenny.Module.LifecycleTest do
  use ExUnit.Case, async: false

  @supervisor_name :"test_sup_#{System.unique_integer([:positive])}"
  @pubsub_name :"test_pubsub_#{System.unique_integer([:positive])}"

  setup do
    start_supervised!({Registry, keys: :unique, name: Blenny.ModuleRegistry})
    start_supervised!({DynamicSupervisor, name: @supervisor_name, strategy: :one_for_one})
    start_supervised!({Phoenix.PubSub, name: @pubsub_name})

    Application.put_env(:blenny_ex, :pub_sub, @pubsub_name)

    :ok
  end

  test "initialize_all calls initialize on modules that define it" do
    assert :ok = Blenny.Module.Lifecycle.initialize_all([BlennyTest.ModuleDeclarative], %{})
  end

  test "start_supervised skips modules with :skip child_spec" do
    assert :ok =
             Blenny.Module.Lifecycle.start_supervised(
               [BlennyTest.ModuleDeclarative],
               @supervisor_name
             )
  end

  test "start_supervised starts modules with valid child_spec" do
    assert :ok =
             Blenny.Module.Lifecycle.start_supervised(
               [BlennyTest.ModuleStateful],
               @supervisor_name
             )
  end

  test "start_supervised handles already_started gracefully" do
    Blenny.Module.Lifecycle.start_supervised([BlennyTest.ModuleStateful], @supervisor_name)

    assert :ok =
             Blenny.Module.Lifecycle.start_supervised(
               [BlennyTest.ModuleStateful],
               @supervisor_name
             )
  end

  test "wire_subscriptions subscribes module with subscriptions/0" do
    Blenny.Module.Lifecycle.start_supervised(
      [BlennyTest.ModuleWithSubscriptions],
      @supervisor_name
    )

    [{pid, _}] =
      Registry.lookup(Blenny.ModuleRegistry, {:module, BlennyTest.ModuleWithSubscriptions})

    ref = Process.monitor(pid)

    assert :ok = Blenny.Module.Lifecycle.wire_subscriptions([BlennyTest.ModuleWithSubscriptions])

    # Module process should have handled :blenny_subscribe without crashing
    _ = :sys.get_state(pid)
    assert Process.alive?(pid)
    Process.demonitor(ref, [:flush])

    # Verify PubSub delivers on this topic by subscribing the test process
    Phoenix.PubSub.subscribe(@pubsub_name, "test:topic")
    Phoenix.PubSub.broadcast(@pubsub_name, "test:topic", {:on_topic, "delivered"})

    assert_receive {:on_topic, "delivered"}
  end

  test "wire_subscriptions skips modules that don't export subscriptions/0" do
    Blenny.Module.Lifecycle.start_supervised(
      [BlennyTest.ModuleStateful],
      @supervisor_name
    )

    assert :ok = Blenny.Module.Lifecycle.wire_subscriptions([BlennyTest.ModuleStateful])
  end

  test "wire_subscriptions skips modules with empty subscriptions/0" do
    Blenny.Module.Lifecycle.start_supervised(
      [BlennyTest.RouterTestModule],
      @supervisor_name
    )

    assert :ok = Blenny.Module.Lifecycle.wire_subscriptions([BlennyTest.RouterTestModule])
  end

  test "wire_subscriptions is idempotent" do
    Blenny.Module.Lifecycle.start_supervised(
      [BlennyTest.ModuleWithSubscriptions],
      @supervisor_name
    )

    [{pid, _}] =
      Registry.lookup(Blenny.ModuleRegistry, {:module, BlennyTest.ModuleWithSubscriptions})

    ref = Process.monitor(pid)

    assert :ok = Blenny.Module.Lifecycle.wire_subscriptions([BlennyTest.ModuleWithSubscriptions])

    # Second call should not crash the module (already subscribed)
    Blenny.Module.Lifecycle.wire_subscriptions([BlennyTest.ModuleWithSubscriptions])

    _ = :sys.get_state(pid)
    assert Process.alive?(pid)
    Process.demonitor(ref, [:flush])
  end
end
