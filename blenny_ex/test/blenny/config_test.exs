defmodule Blenny.ConfigTest do
  use ExUnit.Case, async: true

  test "get/1 returns default values when not configured" do
    assert Blenny.Config.get(:hub) == [max_connections: 10_000, max_per_user: 100]
    assert Blenny.Config.get(:transport) == [idle_timeout_ms: 300_000, auth_required: false]
  end

  test "get/1 returns configured values when set" do
    Application.put_env(:blenny_ex, :transport, idle_timeout_ms: 600_000)
    result = Blenny.Config.get(:transport)
    assert result[:idle_timeout_ms] == 600_000
    assert result[:auth_required] == false
    Application.delete_env(:blenny_ex, :transport)
  end

  test "get/1 with atom key delegates to list" do
    assert Blenny.Config.get(:hub) == Blenny.Config.get([:hub])
  end

  test "get_all/1 returns full keyword section" do
    result = Blenny.Config.get_all(:hub)
    assert result[:max_connections] == 10_000
    assert result[:max_per_user] == 100
  end

  test "get_all/1 merges configured values over defaults" do
    Application.put_env(:blenny_ex, :hub, max_connections: 500)
    result = Blenny.Config.get_all(:hub)
    assert result[:max_connections] == 500
    assert result[:max_per_user] == 100
    Application.delete_env(:blenny_ex, :hub)
  end
end
