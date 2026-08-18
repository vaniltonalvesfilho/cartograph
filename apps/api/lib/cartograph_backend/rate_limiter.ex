defmodule CartographBackend.RateLimiter do
  @moduledoc """
  Fixed-window request counter backed by an ETS table.

  `hit/3` counts one attempt against a key and says whether it is still under
  the limit for the current window. Counting happens in the caller's process
  via `:ets.update_counter/4`, which is atomic, so the GenServer is only here
  to own the table and sweep expired windows.

  Two deliberate limitations:

    * windows are fixed, not sliding, so a caller can spend its whole budget at
      the end of one window and again at the start of the next. For login and
      2FA throttling that is a rounding error against the brute-force rates
      this is meant to stop.
    * counters are per node. With several nodes behind a load balancer the
      effective limit is `limit * nodes`. Anything stricter needs shared state
      (Redis, or a CRDT over the existing cluster).
  """

  use GenServer

  @table __MODULE__
  @sweep_interval :timer.minutes(5)

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Counts one hit against `key` and reports whether it is allowed.

  Returns `:ok`, or `{:error, retry_after_seconds}` once the count for the
  current window exceeds `limit`.

  `now` is injectable so tests can pin a window instead of racing the clock.
  """
  def hit(key, limit, window_ms, now \\ System.system_time(:millisecond))
      when is_integer(limit) and is_integer(window_ms) do
    window = div(now, window_ms)
    expires_at = (window + 1) * window_ms
    record_key = {key, window}

    count = :ets.update_counter(@table, record_key, {2, 1}, {record_key, 0, expires_at})

    if count <= limit do
      :ok
    else
      {:error, max(ceil((expires_at - now) / 1000), 1)}
    end
  end

  @doc """
  Drops every window recorded for `key`.

  Called after an attempt succeeds, so that a user who mistyped a password a
  few times does not stay throttled for the rest of the window.
  """
  def reset(key) do
    :ets.match_delete(@table, {{key, :_}, :_, :_})
    :ok
  end

  @doc false
  # Test support: forget every counter.
  def reset_all, do: :ets.delete_all_objects(@table)

  # ── GenServer ────────────────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    :ets.new(@table, [
      :set,
      :named_table,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    now = System.system_time(:millisecond)
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}])
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep_interval)
end
