defmodule Blenny.Storage.UUIDTest do
  use ExUnit.Case, async: true

  describe "generate/0" do
    test "returns a string" do
      assert is_binary(Blenny.Storage.UUID.generate())
    end

    test "returns a valid UUIDv4 format" do
      uuid = Blenny.Storage.UUID.generate()

      assert String.match?(
               uuid,
               ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
             )
    end

    test "returns unique values on successive calls" do
      uuids = for _ <- 1..100, do: Blenny.Storage.UUID.generate()
      assert length(Enum.uniq(uuids)) == 100
    end

    test "version nibble is always 4" do
      uuid = Blenny.Storage.UUID.generate()
      [_, _, ver_part | _] = String.split(uuid, "-")
      assert String.starts_with?(ver_part, "4")
    end

    test "variant nibble is 8, 9, a, or b" do
      uuid = Blenny.Storage.UUID.generate()
      [_, _, _, var_part | _] = String.split(uuid, "-")
      first = String.first(var_part)
      assert first in ~w(8 9 a b)
    end
  end
end
