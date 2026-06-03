defmodule Blenny.BootstrapTest do
  use ExUnit.Case, async: false

  @pubsub_name :"test_bs_pubsub_#{System.unique_integer([:positive])}"

  setup do
    start_supervised!({Phoenix.PubSub, name: @pubsub_name})
    start_supervised!({Registry, keys: :unique, name: Blenny.ModuleRegistry})
    start_supervised!({DynamicSupervisor, name: Blenny.ModuleSupervisor, strategy: :one_for_one})
    start_supervised!({Blenny.Hub, [name: Blenny.Hub]})

    Application.put_env(:blenny_ex, :pub_sub, @pubsub_name)
    Application.put_env(:blenny_ex, :modules, [BlennyTest.ModuleDeclarative])

    on_exit(fn ->
      Application.delete_env(:blenny_ex, :pub_sub)
      Application.delete_env(:blenny_ex, :modules)
      Blenny.AuthRegistry.stop()
    end)

    :ok
  end

  test "boot returns :ok with valid setup" do
    assert :ok = Blenny.Bootstrap.boot()
  end

  test "boot raises when ModuleRegistry is missing" do
    stop_supervised(Blenny.ModuleRegistry)

    assert_raise RuntimeError, ~r/ModuleRegistry/, fn ->
      Blenny.Bootstrap.boot()
    end
  end

  test "boot raises when ModuleSupervisor is missing" do
    stop_supervised(Blenny.ModuleSupervisor)

    assert_raise RuntimeError, ~r/ModuleSupervisor/, fn ->
      Blenny.Bootstrap.boot()
    end
  end
end
