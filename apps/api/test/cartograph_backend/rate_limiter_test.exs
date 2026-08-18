defmodule CartographBackend.RateLimiterTest do
  @moduledoc """
  The counter itself, with the clock pinned so window behaviour is exact.
  """
  use ExUnit.Case, async: false

  alias CartographBackend.RateLimiter

  @window 60_000

  # A window boundary, so `now + offset` stays inside one window.
  defp base, do: 1_000 * @window

  defp key(name), do: {__MODULE__, name, System.unique_integer()}

  test "allows exactly `limit` hits in a window" do
    k = key(:limit)

    for _ <- 1..3 do
      assert :ok = RateLimiter.hit(k, 3, @window, base())
    end

    assert {:error, _} = RateLimiter.hit(k, 3, @window, base())
  end

  test "reports how long until the window opens again" do
    k = key(:retry)

    assert :ok = RateLimiter.hit(k, 1, @window, base())
    assert {:error, retry_after} = RateLimiter.hit(k, 1, @window, base() + 15_000)

    # 60s window entered at +15s leaves 45s.
    assert retry_after == 45
  end

  test "the budget comes back in the next window" do
    k = key(:rollover)

    assert :ok = RateLimiter.hit(k, 1, @window, base())
    assert {:error, _} = RateLimiter.hit(k, 1, @window, base())
    assert :ok = RateLimiter.hit(k, 1, @window, base() + @window)
  end

  test "counters are per key" do
    a = key(:a)
    b = key(:b)

    assert :ok = RateLimiter.hit(a, 1, @window, base())
    assert {:error, _} = RateLimiter.hit(a, 1, @window, base())
    assert :ok = RateLimiter.hit(b, 1, @window, base())
  end

  test "reset/1 drops the key's windows" do
    k = key(:reset)

    assert :ok = RateLimiter.hit(k, 1, @window, base())
    assert {:error, _} = RateLimiter.hit(k, 1, @window, base())

    RateLimiter.reset(k)

    assert :ok = RateLimiter.hit(k, 1, @window, base())
  end
end
