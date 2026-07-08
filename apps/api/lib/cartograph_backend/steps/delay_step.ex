defmodule CartographBackend.Steps.DelayStep do
  @moduledoc """
  Sleeps for a configurable number of seconds. Useful for demos, pacing, and
  giving downstream systems time to settle. Honours cancellation: it wakes up
  every 200 ms to check whether the execution was stopped.

      step "delay" { seconds 3 }
  """
  @behaviour CartographBackend.Steps.Step

  alias CartographBackend.Engine.StepContext

  @impl true
  def name, do: "delay"

  @impl true
  def execute(%StepContext{params: params} = ctx) do
    seconds = params |> Map.get("seconds", 1) |> to_int(1)
    total_ms = max(0, seconds * 1000)

    StepContext.info(ctx, "Waiting #{seconds}s…")
    sleep_in_chunks(total_ms, ctx)

    {:ok, ctx}
  end

  defp sleep_in_chunks(remaining_ms, _ctx) when remaining_ms <= 0, do: :ok

  defp sleep_in_chunks(remaining_ms, ctx) do
    if StepContext.cancelled?(ctx) do
      :ok
    else
      chunk = min(200, remaining_ms)
      Process.sleep(chunk)
      sleep_in_chunks(remaining_ms - chunk, ctx)
    end
  end

  defp to_int(v, _default) when is_integer(v), do: v

  defp to_int(v, default) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      :error -> default
    end
  end

  defp to_int(_v, default), do: default
end
