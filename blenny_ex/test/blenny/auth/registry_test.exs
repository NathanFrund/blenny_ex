defmodule Blenny.AuthRegistryTest do
  use ExUnit.Case, async: false

  setup do
    Blenny.AuthRegistry.start()

    on_exit(fn ->
      Blenny.AuthRegistry.stop()
    end)

    :ok
  end

  test "starts and registers a provider" do
    Blenny.AuthRegistry.register(%{
      module: BlennyTest.AuthTestModule,
      fetch_session: :some_function,
      login_route: "/auth/signin"
    })

    provider = Blenny.AuthRegistry.registered()
    assert provider != nil
    assert provider.module == BlennyTest.AuthTestModule
    assert provider.login_route == "/auth/signin"
  end

  test "returns nil when nothing registered" do
    assert Blenny.AuthRegistry.registered() == nil
  end

  test "raises on duplicate registration" do
    Blenny.AuthRegistry.register(%{
      module: BlennyTest.AuthTestModule,
      fetch_session: :fn1,
      login_route: "/a"
    })

    assert_raise ArgumentError, ~r{already registered}, fn ->
      Blenny.AuthRegistry.register(%{
        module: BlennyTest.AuthTestModule,
        fetch_session: :fn2,
        login_route: "/b"
      })
    end
  end

  test "start is idempotent" do
    assert Blenny.AuthRegistry.start() == :ok
    assert Blenny.AuthRegistry.start() == :ok
  end

  test "stop is safe when already stopped" do
    Blenny.AuthRegistry.stop()
    assert Blenny.AuthRegistry.stop() == :ok
  end
end
