defmodule Blenny.Storage.Impl.SurrealDBTest do
  use ExUnit.Case, async: true

  alias Blenny.Storage.Impl.SurrealDB

  describe "module" do
    test "exports expected callbacks" do
      exports = SurrealDB.__info__(:functions)
      assert Keyword.has_key?(exports, :start_link) and Keyword.get(exports, :start_link) == 1
    end
  end
end
