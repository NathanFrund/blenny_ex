defmodule Blenny.ConfigTest do
  use ExUnit.Case, async: false

  test "get/1 returns default values when not configured" do
    assert Blenny.Config.get(:hub) == [max_connections: 10_000, max_per_user: 100, drain_timeout: 30_000]
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

  describe "validate!/0" do
    setup do
      saved = Application.get_all_env(:blenny_ex)

      on_exit(fn ->
        Enum.each(Application.get_all_env(:blenny_ex), fn {k, _} ->
          Application.delete_env(:blenny_ex, k)
        end)

        Enum.each(saved, fn {k, v} -> Application.put_env(:blenny_ex, k, v) end)
      end)
    end

    test "passes with valid config" do
      Application.put_env(:blenny_ex, :pub_sub, :test_pub_sub)
      assert :ok = Blenny.Config.validate!()
    end

    test "raises when pub_sub is missing" do
      Application.delete_env(:blenny_ex, :pub_sub)

      assert_raise NimbleOptions.ValidationError, ~r/pub_sub/, fn ->
        Blenny.Config.validate!()
      end
    end

    test "raises when pub_sub is not an atom" do
      Application.put_env(:blenny_ex, :pub_sub, "not_an_atom")

      assert_raise NimbleOptions.ValidationError, fn ->
        Blenny.Config.validate!()
      end
    end

    test "raises on unknown keys" do
      Application.put_env(:blenny_ex, :pub_sub, :test_pub_sub)
      Application.put_env(:blenny_ex, :unknown_key, "oops")

      assert_raise NimbleOptions.ValidationError, fn ->
        Blenny.Config.validate!()
      end
    end

    test "raises when hub.max_connections is not a positive integer" do
      Application.put_env(:blenny_ex, :pub_sub, :test_pub_sub)
      Application.put_env(:blenny_ex, :hub, max_connections: -1)

      assert_raise NimbleOptions.ValidationError, fn ->
        Blenny.Config.validate!()
      end
    end

    test "accepts valid hub config" do
      Application.put_env(:blenny_ex, :pub_sub, :test_pub_sub)
      Application.put_env(:blenny_ex, :hub, max_connections: 50, max_per_user: 5)
      assert :ok = Blenny.Config.validate!()
    end

    test "accepts valid transport config" do
      Application.put_env(:blenny_ex, :pub_sub, :test_pub_sub)
      Application.put_env(:blenny_ex, :transport, idle_timeout_ms: 600_000, auth_required: true)
      assert :ok = Blenny.Config.validate!()
    end
  end
end
