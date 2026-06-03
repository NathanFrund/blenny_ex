defmodule Blenny.IntentTest do
  use ExUnit.Case, async: true

  test "routing/0 returns the three routing intents" do
    assert Blenny.Intent.routing() == [:ui, :command, :notification]
  end

  test "all/0 returns routing intents plus :all" do
    assert Blenny.Intent.all() == [:ui, :command, :notification, :all]
  end

  test "to_topic/1 maps each intent to its topic" do
    assert Blenny.Intent.to_topic(:ui) == "blenny:intent:ui"
    assert Blenny.Intent.to_topic(:command) == "blenny:intent:command"
    assert Blenny.Intent.to_topic(:notification) == "blenny:intent:notification"
  end

  test "user_topic/1 formats user topic" do
    assert Blenny.Intent.user_topic("user-42") == "blenny:user:user-42"
  end

  test "parse/1 returns {:ok, intent} for valid intents" do
    assert Blenny.Intent.parse("ui") == {:ok, :ui}
    assert Blenny.Intent.parse("command") == {:ok, :command}
    assert Blenny.Intent.parse("notification") == {:ok, :notification}
    assert Blenny.Intent.parse("all") == {:ok, :all}
  end

  test "parse/1 returns :error for invalid intents" do
    assert Blenny.Intent.parse("bogus") == :error
    assert Blenny.Intent.parse("") == :error
  end

  test "parse_list/1 returns [:all] for nil or empty input" do
    assert Blenny.Intent.parse_list(nil) == [:all]
    assert Blenny.Intent.parse_list("") == [:all]
  end

  test "parse_list/1 parses comma-separated intents" do
    assert Blenny.Intent.parse_list("ui,command") == [:ui, :command]
    assert Blenny.Intent.parse_list("notification") == [:notification]
  end

  test "parse_list/1 strips invalid intents and falls back to :all" do
    assert Blenny.Intent.parse_list("ui,bogus,command") == [:ui, :command]
    assert Blenny.Intent.parse_list("bogus") == [:all]
  end

  test "accepts?/2 returns true for matching intent" do
    assert Blenny.Intent.accepts?([:ui], :ui)
    refute Blenny.Intent.accepts?([:ui], :command)
  end

  test "accepts?/2 with :all accepts everything" do
    assert Blenny.Intent.accepts?([:all], :ui)
    assert Blenny.Intent.accepts?([:all], :command)
    assert Blenny.Intent.accepts?([:all], :notification)
  end

  test "accepts?/2 with :direct always returns true" do
    assert Blenny.Intent.accepts?([], :direct)
    assert Blenny.Intent.accepts?([:ui], :direct)
  end
end
