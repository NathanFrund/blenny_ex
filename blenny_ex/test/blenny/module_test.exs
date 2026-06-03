defmodule Blenny.ModuleTest do
  use ExUnit.Case, async: true

  test "declarative module has default child_spec returning :skip" do
    assert BlennyTest.ModuleDeclarative.child_spec([]) == :skip
  end

  test "stateful module defines custom child_spec" do
    spec = BlennyTest.ModuleStateful.child_spec([])
    assert spec.id == BlennyTest.ModuleStateful
    assert spec.start == {BlennyTest.ModuleStateful, :start_link, []}
    assert spec.restart == :permanent
  end

  test "module implements required callbacks" do
    assert BlennyTest.ModuleDeclarative.name() == "declarative"
    assert BlennyTest.ModuleDeclarative.routes() == []
    assert BlennyTest.ModuleDeclarative.capabilities() == []
    assert BlennyTest.ModuleDeclarative.subscriptions() == []
  end
end
