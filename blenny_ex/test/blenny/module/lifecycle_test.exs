defmodule Blenny.Module.LifecycleTest do
  use ExUnit.Case, async: false

  @supervisor_name :"test_sup_#{System.unique_integer([:positive])}"

  setup do
    start_supervised!({Registry, keys: :unique, name: Blenny.ModuleRegistry})
    start_supervised!({DynamicSupervisor, name: @supervisor_name, strategy: :one_for_one})

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
end
