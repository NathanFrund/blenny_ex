defmodule Blenny.RateLimiter do
  @moduledoc """
  Process-local sliding window rate limiter.

  Uses the process dictionary to track timestamps per key.
  Each process has its own independent counters — ideal for per-connection
  rate limiting where the limiting process and the consuming process are
  one and the same.

  ## Usage

      case Blenny.RateLimiter.check(:my_key, 100, 1000) do
        :ok -> # proceed
        {:error, :rate_limited} -> # back off
      end
  """

  @doc """
  Checks whether an action is within the rate limit for the given key.

  Maintains a sliding window of timestamps in the process dictionary.
  Expired timestamps (older than `window_ms`) are pruned on each check.

  Returns `:ok` if under the limit, `{:error, :rate_limited}` if exceeded.
  """
  @spec check(atom(), pos_integer(), pos_integer()) :: :ok | {:error, :rate_limited}
  def check(key, max_messages, window_ms \\ 1000) when max_messages > 0 and window_ms > 0 do
    now = System.monotonic_time(:millisecond)
    cutoff = now - window_ms

    timestamps = Process.get(key, [])
    recent = for(t <- timestamps, t > cutoff, do: t)

    if length(recent) >= max_messages do
      {:error, :rate_limited}
    else
      Process.put(key, [now | recent])
      :ok
    end
  end

  @doc """
  Resets the rate limit counter for the given key.
  """
  @spec reset(atom()) :: :ok
  def reset(key) do
    Process.delete(key)
    :ok
  end
end
