defmodule Blenny.SurrealDB.PublisherBridgeTest do
  use ExUnit.Case, async: true

  alias Blenny.SurrealDB.PublisherBridge

  describe "start_link/1" do
    test "starts with valid options" do
      pid = start_supervised!({PublisherBridge, connection: self(), subscriptions: []})
      assert is_pid(pid)
    end
  end

  describe "subscriptions/1" do
    test "returns empty list for no subscriptions" do
      pid = start_supervised!({PublisherBridge, connection: self(), subscriptions: []})
      assert PublisherBridge.subscriptions(pid) == []
    end
  end

  describe "module exports" do
    test "exports expected functions" do
      exports = PublisherBridge.__info__(:functions)
      assert Keyword.has_key?(exports, :start_link) and Keyword.get(exports, :start_link) == 1
      assert Keyword.has_key?(exports, :unsubscribe) and Keyword.get(exports, :unsubscribe) == 2

      assert Keyword.has_key?(exports, :subscriptions) and
               Keyword.get(exports, :subscriptions) == 1
    end
  end
end
