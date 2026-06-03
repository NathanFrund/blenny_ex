defmodule Blenny.Module.LoaderTest do
  use ExUnit.Case, async: false

  setup do
    # Save existing config
    existing_registered = Application.get_env(:blenny_ex, :registered_modules, [])
    existing_modules = Application.get_env(:blenny_ex, :modules, [])

    on_exit(fn ->
      Application.put_env(:blenny_ex, :registered_modules, existing_registered)
      Application.put_env(:blenny_ex, :modules, existing_modules)
    end)

    :ok
  end

  test "validate! passes with no conflicts" do
    assert :ok = Blenny.Module.Loader.validate!([BlennyTest.ModuleDeclarative])
  end

  test "validate! raises on capability conflicts" do
    assert_raise ArgumentError, ~r/capability/, fn ->
      Blenny.Module.Loader.validate!([
        BlennyTest.ModuleWithCapability,
        BlennyTest.ModuleWithCapability
      ])
    end
  end

  test "modules includes configured and discovered modules" do
    Application.put_env(:blenny_ex, :modules, [BlennyTest.ModuleDeclarative])

    mods = Blenny.Module.Loader.modules()
    assert BlennyTest.ModuleDeclarative in mods
  end

  test "modules does not duplicate entries" do
    Application.put_env(:blenny_ex, :modules, [
      BlennyTest.ModuleDeclarative,
      BlennyTest.ModuleDeclarative
    ])

    mods = Blenny.Module.Loader.modules()
    assert length(Enum.filter(mods, &(&1 == BlennyTest.ModuleDeclarative))) == 1
  end
end
