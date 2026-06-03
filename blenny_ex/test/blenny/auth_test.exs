defmodule Blenny.AuthTest do
  use ExUnit.Case, async: true

  test "struct has id, role, and metadata fields" do
    auth = %Blenny.Auth{}
    assert auth.id == nil
    assert auth.role == nil
    assert auth.metadata == %{}
  end

  test "struct can be created with values" do
    auth = %Blenny.Auth{id: "user-1", role: "admin", metadata: %{tenant: "acme"}}
    assert auth.id == "user-1"
    assert auth.role == "admin"
    assert auth.metadata == %{tenant: "acme"}
  end

  test "pattern matches on struct" do
    auth = %Blenny.Auth{id: "u1", role: "user"}

    assert match?(%Blenny.Auth{id: "u1"}, auth)
    assert match?(%Blenny.Auth{role: "user"}, auth)
    refute match?(%Blenny.Auth{role: "admin"}, auth)
  end

  test "struct is a map" do
    assert is_map(%Blenny.Auth{})
    assert Map.get(%Blenny.Auth{}, :__struct__) == Blenny.Auth
  end
end
