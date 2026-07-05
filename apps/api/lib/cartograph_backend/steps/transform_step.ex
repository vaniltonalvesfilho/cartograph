defmodule CartographBackend.Steps.TransformStep do
  @behaviour CartographBackend.Steps.Step

  alias CartographBackend.Engine.StepContext

  @impl true
  def name, do: "transform"

  @impl true
  def execute(%StepContext{params: params} = ctx) do
    op = Map.get(params, "operation", "uppercase")
    files = StepContext.get_state(ctx, "files", [])
    StepContext.info(ctx, "Applying transform '#{op}' to #{length(files)} file(s)")

    result = Enum.reduce_while(files, {:ok, %{}}, fn file, {:ok, acc} ->
      if StepContext.cancelled?(ctx) do
        StepContext.info(ctx, "Cancellation requested; stopping transform loop")
        {:halt, {:ok, acc}}
      else
        case apply_transform(file, op, ctx) do
          {:ok, {filename, content}} ->
            # Small delay so live-log streaming is visible in the dashboard
            Process.sleep(300)
            {:cont, {:ok, Map.put(acc, filename, content)}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end
    end)

    case result do
      {:ok, transformed} -> {:ok, StepContext.put_state(ctx, "transformed", transformed)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp apply_transform(file, op, ctx) do
    case File.read(file) do
      {:error, reason} ->
        {:error, "Failed to read #{Path.basename(file)}: #{reason}"}

      {:ok, content} ->
        case transform(content, op) do
          {:error, reason} ->
            {:error, reason}

          {:ok, result} ->
            StepContext.info(ctx, "  transformed #{Path.basename(file)} (#{byte_size(content)} -> #{byte_size(result)} chars)")
            {:ok, {Path.basename(file), result}}
        end
    end
  end

  defp transform(content, "uppercase"), do: {:ok, String.upcase(content)}
  defp transform(content, "lowercase"), do: {:ok, String.downcase(content)}
  defp transform(content, "reverse"),   do: {:ok, String.reverse(content)}
  defp transform(content, "lineCount") do
    count = content |> String.split("\n") |> length()
    {:ok, "lines: #{count}"}
  end
  defp transform(_content, op), do: {:error, "Unknown operation: #{op}"}
end
