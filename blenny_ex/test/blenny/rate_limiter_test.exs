defmodule Blenny.RateLimiterTest do
  use ExUnit.Case, async: true

  setup do
    Blenny.RateLimiter.reset(:test_key)
    Blenny.RateLimiter.reset(:burst_key)
    :ok
  end

  test "allows up to max_messages within the window" do
    assert Blenny.RateLimiter.check(:test_key, 3, 1000) == :ok
    assert Blenny.RateLimiter.check(:test_key, 3, 1000) == :ok
    assert Blenny.RateLimiter.check(:test_key, 3, 1000) == :ok
  end

  test "rejects when limit exceeded" do
    for _ <- 1..3 do
      Blenny.RateLimiter.check(:test_key, 3, 1000)
    end

    assert Blenny.RateLimiter.check(:test_key, 3, 1000) == {:error, :rate_limited}
  end

  test "previous key state does not affect separate keys" do
    for _ <- 1..3 do
      Blenny.RateLimiter.check(:burst_key, 3, 1000)
    end

    assert Blenny.RateLimiter.check(:other_key, 3, 1000) == :ok
  end

  test "reset clears the counter" do
    for _ <- 1..3 do
      Blenny.RateLimiter.check(:test_key, 3, 1000)
    end

    assert Blenny.RateLimiter.check(:test_key, 3, 1000) == {:error, :rate_limited}

    Blenny.RateLimiter.reset(:test_key)
    assert Blenny.RateLimiter.check(:test_key, 3, 1000) == :ok
  end

  test "window slides — old timestamps expire" do
    assert Blenny.RateLimiter.check(:test_key, 2, 50) == :ok
    assert Blenny.RateLimiter.check(:test_key, 2, 50) == :ok
    assert Blenny.RateLimiter.check(:test_key, 2, 50) == {:error, :rate_limited}

    # Wait for window to expire
    :timer.sleep(60)

    assert Blenny.RateLimiter.check(:test_key, 2, 50) == :ok
  end
end
